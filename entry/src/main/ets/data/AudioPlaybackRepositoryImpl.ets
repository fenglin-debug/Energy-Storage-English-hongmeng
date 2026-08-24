import { media } from '@kit.MediaKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common, wantAgent } from '@kit.AbilityKit';
import { avSession } from '@kit.AVSessionKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import {
  AudioQueueItem, AudioTransitionReason, PlaybackSnapshot, PlaybackTransition
} from '../domain/Models';
import { AudioPlaybackRepository, Unsubscribe } from '../domain/Repositories';
import { DatabaseService } from './DatabaseService';

export class AudioPlaybackRepositoryImpl implements AudioPlaybackRepository {
  private readonly database: DatabaseService;
  private readonly context: common.UIAbilityContext;
  private player: media.AVPlayer | null = null;
  private session: avSession.AVSession | null = null;
  private backgroundRunning: boolean = false;
  private openedFd: number | null = null;
  private queue: AudioQueueItem[] = [];
  private queueIndex: number = -1;
  private autoAdvance: boolean = false;
  private repeatAll: boolean = false;
  private reshuffleOnRepeat: boolean = false;
  private transitionRunning: boolean = false;
  private current: PlaybackSnapshot = {
    assetId: null, state: 'idle', positionMs: 0, durationMs: 0, speed: 1,
    queueIndex: -1, queueSize: 0, transition: null, errorCode: null
  };
  private listeners = new Set<(snapshot: PlaybackSnapshot) => void>();

  constructor(database: DatabaseService, context: common.UIAbilityContext) {
    this.database = database; this.context = context;
  }

  snapshot(): PlaybackSnapshot {
    return {
      assetId: this.current.assetId, state: this.current.state, positionMs: this.current.positionMs,
      durationMs: this.current.durationMs, speed: this.current.speed, queueIndex: this.current.queueIndex,
      queueSize: this.current.queueSize, transition: this.current.transition, errorCode: this.current.errorCode
    };
  }

  async play(assetId: string, speed: number): Promise<void> {
    await this.playQueue([{ assetId: assetId, title: await this.displayTitle(assetId), subtitle: '' }],
      0, 0, speed, false, false, false);
  }

  async playQueue(items: AudioQueueItem[], startIndex: number, startPositionMs: number, speed: number,
    autoAdvance: boolean, repeatAll: boolean, reshuffleOnRepeat: boolean = false): Promise<void> {
    if (items.length === 0) throw new Error('EMPTY_AUDIO_QUEUE');
    if (startIndex < 0 || startIndex >= items.length) throw new Error('INVALID_AUDIO_QUEUE_INDEX');
    await this.disposeAll(false);
    this.queue = items.slice(); this.queueIndex = startIndex; this.autoAdvance = autoAdvance;
    this.repeatAll = repeatAll; this.reshuffleOnRepeat = reshuffleOnRepeat;
    await this.ensureMediaSession(); await this.publishQueue();
    await this.startQueueItem(startIndex, Math.max(0, startPositionMs), speed, null);
  }

  async pause(): Promise<void> { if (this.player !== null) await this.player.pause(); }

  async resume(): Promise<void> {
    if (this.player === null && this.queueIndex >= 0) {
      await this.startQueueItem(this.queueIndex, this.current.positionMs, this.current.speed, null);
    } else if (this.player !== null) {
      if (this.player.state === 'completed') this.player.seek(0, media.SeekMode.SEEK_CLOSEST);
      await this.player.play(); await this.startBackground();
    }
  }

  async seekTo(positionMs: number): Promise<void> {
    if (this.player !== null) this.player.seek(Math.max(0, Math.floor(positionMs)), media.SeekMode.SEEK_CLOSEST);
  }

  async skipToNext(): Promise<void> {
    if (this.queue.length <= 1) return;
    let next = this.queueIndex + 1;
    if (next >= this.queue.length) {
      if (!this.repeatAll) return;
      if (this.reshuffleOnRepeat) { this.shuffleAvoidingCurrent(); await this.publishQueue(); }
      next = 0;
    }
    await this.moveTo(next, AudioTransitionReason.MANUAL_NEXT);
  }

  async skipToPrevious(): Promise<void> {
    if (this.queue.length <= 1) return;
    let previous = this.queueIndex - 1;
    if (previous < 0) previous = this.repeatAll ? this.queue.length - 1 : 0;
    await this.moveTo(previous, AudioTransitionReason.MANUAL_PREVIOUS);
  }

  async stop(): Promise<void> { await this.disposeAll(true); }

  subscribe(listener: (snapshot: PlaybackSnapshot) => void): Unsubscribe {
    this.listeners.add(listener); listener(this.snapshot());
    return (): void => { this.listeners.delete(listener); };
  }

  private async moveTo(index: number, reason: AudioTransitionReason): Promise<void> {
    if (this.transitionRunning || index < 0 || index >= this.queue.length) return;
    this.transitionRunning = true;
    const transition: PlaybackTransition = {
      fromAssetId: this.current.assetId, toAssetId: this.queue[index].assetId,
      fromPositionMs: this.current.positionMs, reason: reason
    };
    try { await this.startQueueItem(index, 0, this.current.speed, transition); }
    finally { this.transitionRunning = false; }
  }

  private async startQueueItem(index: number, startPositionMs: number, speed: number,
    transition: PlaybackTransition | null): Promise<void> {
    await this.releasePlayer();
    const item = this.queue[index]; const path = await this.assetPath(item.assetId);
    if (path === null) throw new Error('AUDIO_ASSET_NOT_FOUND');
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY); this.openedFd = file.fd;
    const stat = fs.statSync(path); const player = await media.createAVPlayer();
    this.player = player; this.queueIndex = index;
    this.current = {
      assetId: item.assetId, state: 'loading', positionMs: startPositionMs, durationMs: 0, speed: speed,
      queueIndex: index, queueSize: this.queue.length, transition: transition, errorCode: null
    };
    this.emit(); this.bind(player);
    player.fdSrc = { fd: file.fd, offset: 0, length: stat.size };
    await this.waitForState(player, 'initialized'); await player.prepare(); await this.waitForState(player, 'prepared');
    await player.setSpeed(this.speedValue(speed));
    if (startPositionMs > 0) player.seek(Math.floor(startPositionMs), media.SeekMode.SEEK_CLOSEST);
    await this.publishCurrentMetadata(); await player.play(); await this.startBackground();
    this.current.transition = null;
  }

  private bind(player: media.AVPlayer): void {
    player.on('stateChange', (state: string) => {
      if (this.player !== player) return;
      this.current.state = state; this.current.durationMs = player.duration; this.emit(); this.updateSessionState();
      if (state === 'completed') this.handleCompleted();
      else if (state === 'error') this.stopBackground();
    });
    player.on('timeUpdate', (position: number) => {
      if (this.player !== player) return;
      this.current.positionMs = position; this.emit(); this.updateSessionState();
    });
    player.on('durationUpdate', (duration: number) => {
      if (this.player !== player) return;
      this.current.durationMs = duration; this.emit(); this.publishCurrentMetadata();
    });
    player.on('error', (error: BusinessError) => {
      if (this.player !== player) return;
      this.current.state = 'error'; this.current.errorCode = `MEDIA_${error.code}`; this.emit();
    });
  }

  private async handleCompleted(): Promise<void> {
    if (this.transitionRunning) return;
    this.current.positionMs = this.current.durationMs; this.emit();
    if (!this.autoAdvance || this.queue.length <= 1) { await this.stopBackground(); return; }
    let next = this.queueIndex + 1;
    if (next >= this.queue.length) {
      if (!this.repeatAll) { await this.stopBackground(); return; }
      if (this.reshuffleOnRepeat) { this.shuffleAvoidingCurrent(); await this.publishQueue(); }
      next = 0;
    }
    await this.moveTo(next, AudioTransitionReason.AUTOMATIC);
  }

  private shuffleAvoidingCurrent(): void {
    const currentAssetId = this.current.assetId;
    for (let index = this.queue.length - 1; index > 0; index--) {
      const swap = Math.floor(Math.random() * (index + 1));
      const value = this.queue[index]; this.queue[index] = this.queue[swap]; this.queue[swap] = value;
    }
    if (this.queue.length > 1 && this.queue[0].assetId === currentAssetId) {
      const value = this.queue[0]; this.queue[0] = this.queue[1]; this.queue[1] = value;
    }
  }

  private waitForState(player: media.AVPlayer, expected: string): Promise<void> {
    if (player.state === expected) return Promise.resolve();
    return new Promise<void>((resolve, reject) => {
      const startedAt = Date.now();
      const timer = setInterval(() => {
        const state = player.state;
        if (state === 'error') { clearInterval(timer); reject(new Error('MEDIA_PREPARE_FAILED')); }
        else if (state === expected) { clearInterval(timer); resolve(); }
        else if (Date.now() - startedAt > 10_000) {
          clearInterval(timer); reject(new Error(`MEDIA_STATE_TIMEOUT_${expected}`));
        }
      }, 50);
    });
  }

  private async ensureMediaSession(): Promise<void> {
    if (this.session !== null) return;
    const session = await avSession.createAVSession(this.context, 'bess-audio', 'audio'); this.session = session;
    session.on('play', () => { this.resume(); }); session.on('pause', () => { this.pause(); });
    session.on('stop', () => { this.stop(); }); session.on('seek', (position: number) => { this.seekTo(position); });
    session.on('playNext', () => { this.skipToNext(); }); session.on('playPrevious', () => { this.skipToPrevious(); });
    await session.setAVQueueTitle('BESS 储能英语文章'); await session.activate();
  }

  private async publishQueue(): Promise<void> {
    if (this.session === null) return;
    const items: avSession.AVQueueItem[] = this.queue.map((item: AudioQueueItem, index: number) => {
      const description: avSession.AVMediaDescription = {
        assetId: item.assetId,
        title: item.title,
        subtitle: item.subtitle
      };
      const queueItem: avSession.AVQueueItem = { itemId: index, description: description };
      return queueItem;
    });
    await this.session.setAVQueueItems(items);
  }

  private async publishCurrentMetadata(): Promise<void> {
    if (this.session === null || this.queueIndex < 0 || this.queueIndex >= this.queue.length) return;
    const item = this.queue[this.queueIndex];
    const previous = this.queue.length > 1 ? this.queue[(this.queueIndex - 1 + this.queue.length) % this.queue.length].assetId : undefined;
    const next = this.queue.length > 1 ? this.queue[(this.queueIndex + 1) % this.queue.length].assetId : undefined;
    try {
      await this.session.setAVMetadata({ assetId: item.assetId, title: item.title, artist: item.subtitle,
        duration: this.current.durationMs, previousAssetId: previous, nextAssetId: next });
    } catch (_) {}
  }

  private async updateSessionState(): Promise<void> {
    if (this.session === null) return;
    let state = avSession.PlaybackState.PLAYBACK_STATE_PREPARE;
    if (this.current.state === 'playing') state = avSession.PlaybackState.PLAYBACK_STATE_PLAY;
    else if (this.current.state === 'paused') state = avSession.PlaybackState.PLAYBACK_STATE_PAUSE;
    else if (this.current.state === 'completed') state = avSession.PlaybackState.PLAYBACK_STATE_COMPLETED;
    try {
      await this.session.setAVPlaybackState({ state: state, speed: this.current.speed, activeItemId: this.queueIndex,
        position: { elapsedTime: this.current.positionMs, updateTime: Date.now() } });
    } catch (_) {}
  }

  private async releasePlayer(): Promise<void> {
    const old = this.player; this.player = null;
    if (old !== null) { try { await old.stop(); } catch (_) {} try { await old.release(); } catch (_) {} }
    if (this.openedFd !== null) { try { fs.closeSync(this.openedFd); } catch (_) {} this.openedFd = null; }
  }

  private async disposeAll(withTransition: boolean): Promise<void> {
    const transition: PlaybackTransition | null = withTransition && this.current.assetId !== null ? {
      fromAssetId: this.current.assetId, toAssetId: null, fromPositionMs: this.current.positionMs,
      reason: AudioTransitionReason.STOPPED
    } : null;
    await this.releasePlayer(); await this.stopBackground();
    if (this.session !== null) {
      try { await this.session.deactivate(); } catch (_) {} try { await this.session.destroy(); } catch (_) {}
      this.session = null;
    }
    this.queue = []; this.queueIndex = -1; this.autoAdvance = false; this.repeatAll = false; this.reshuffleOnRepeat = false;
    this.current = { assetId: null, state: 'idle', positionMs: 0, durationMs: 0, speed: 1,
      queueIndex: -1, queueSize: 0, transition: transition, errorCode: null };
    this.emit(); this.current.transition = null;
  }

  private speedValue(speed: number): media.PlaybackSpeed {
    if (speed < 1.0) return media.PlaybackSpeed.SPEED_FORWARD_0_75_X;
    if (speed <= 1.0) return media.PlaybackSpeed.SPEED_FORWARD_1_00_X;
    return media.PlaybackSpeed.SPEED_FORWARD_1_25_X;
  }

  private async startBackground(): Promise<void> {
    if (this.backgroundRunning) return;
    const agent = await wantAgent.getWantAgent({ wants: [{ bundleName: 'com.bess.salestrainer', abilityName: 'EntryAbility' }],
      actionType: wantAgent.OperationType.START_ABILITY, requestCode: 20021,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG] });
    await backgroundTaskManager.startBackgroundRunning(this.context,
      backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK, agent);
    this.backgroundRunning = true;
  }

  private async stopBackground(): Promise<void> {
    if (!this.backgroundRunning) return;
    try { await backgroundTaskManager.stopBackgroundRunning(this.context); } catch (_) {}
    this.backgroundRunning = false;
  }

  private async displayTitle(assetId: string): Promise<string> {
    const result = await this.database.get().querySql('SELECT title FROM articles WHERE audioAssetId=? LIMIT 1', [assetId]);
    try { return result.goToFirstRow() ? result.getString(0) : 'BESS 英语训练'; } finally { result.close(); }
  }

  private async assetPath(assetId: string): Promise<string | null> {
    const result = await this.database.get().querySql('SELECT localPath FROM audio_file_index WHERE assetId=?', [assetId]);
    try { return result.goToFirstRow() ? result.getString(0) : null; } finally { result.close(); }
  }

  private emit(): void { const value = this.snapshot(); this.listeners.forEach(listener => listener(value)); }
}
