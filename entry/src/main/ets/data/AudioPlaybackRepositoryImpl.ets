import { media } from '@kit.MediaKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common, wantAgent } from '@kit.AbilityKit';
import { avSession } from '@kit.AVSessionKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { PlaybackSnapshot } from '../domain/Models';
import { AudioPlaybackRepository, Unsubscribe } from '../domain/Repositories';
import { DatabaseService } from './DatabaseService';

export class AudioPlaybackRepositoryImpl implements AudioPlaybackRepository {
  private readonly database: DatabaseService;
  private readonly context: common.UIAbilityContext;
  private player: media.AVPlayer | null = null;
  private session: avSession.AVSession | null = null;
  private backgroundRunning: boolean = false;
  private openedFd: number | null = null;
  private current: PlaybackSnapshot = { assetId: null, state: 'idle', positionMs: 0, durationMs: 0, speed: 1, errorCode: null };
  private listeners = new Set<(snapshot: PlaybackSnapshot) => void>();

  constructor(database: DatabaseService, context: common.UIAbilityContext) {
    this.database = database; this.context = context;
  }

  snapshot(): PlaybackSnapshot {
    return { assetId: this.current.assetId, state: this.current.state, positionMs: this.current.positionMs,
      durationMs: this.current.durationMs, speed: this.current.speed, errorCode: this.current.errorCode };
  }

  async play(assetId: string, speed: number): Promise<void> {
    await this.disposePlayer();
    const path = await this.assetPath(assetId);
    if (path === null) throw new Error('AUDIO_ASSET_NOT_FOUND');
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY); this.openedFd = file.fd;
    const stat = fs.statSync(path);
    const player = await media.createAVPlayer(); this.player = player;
    this.current = { assetId: assetId, state: 'loading', positionMs: 0, durationMs: 0, speed: speed, errorCode: null };
    this.bind(player);
    player.fdSrc = { fd: file.fd, offset: 0, length: stat.size };
    await this.waitForState(player, 'initialized');
    await player.prepare();
    await this.waitForState(player, 'prepared');
    await player.setSpeed(this.speedValue(speed));
    await this.ensureMediaSession(assetId);
    await player.play();
    await this.startBackground();
  }

  async pause(): Promise<void> { if (this.player !== null) await this.player.pause(); }
  async resume(): Promise<void> {
    if (this.player !== null) { await this.player.play(); await this.startBackground(); }
  }
  async seekTo(positionMs: number): Promise<void> {
    if (this.player !== null) this.player.seek(Math.max(0, Math.floor(positionMs)), media.SeekMode.SEEK_CLOSEST);
  }
  async stop(): Promise<void> { await this.disposePlayer(); }

  subscribe(listener: (snapshot: PlaybackSnapshot) => void): Unsubscribe {
    this.listeners.add(listener); listener(this.snapshot());
    return (): void => { this.listeners.delete(listener); };
  }

  private bind(player: media.AVPlayer): void {
    player.on('stateChange', (state: string) => {
      this.current.state = state; this.current.durationMs = player.duration; this.emit(); this.updateSessionState();
      if (state === 'completed' || state === 'error') this.stopBackground();
    });
    player.on('timeUpdate', (position: number) => {
      this.current.positionMs = position; this.emit(); this.updateSessionState();
    });
    player.on('durationUpdate', (duration: number) => { this.current.durationMs = duration; this.emit(); });
    player.on('error', (error: BusinessError) => {
      this.current.state = 'error'; this.current.errorCode = `MEDIA_${error.code}`; this.emit();
    });
  }

  private waitForState(player: media.AVPlayer, expected: string): Promise<void> {
    if (player.state === expected) return Promise.resolve();
    return new Promise<void>((resolve, reject) => {
      const startedAt = Date.now();
      const timer = setInterval(() => {
        const state = player.state;
        if (state === 'error') {
          clearInterval(timer); reject(new Error('MEDIA_PREPARE_FAILED'));
        } else if (state === expected) {
          clearInterval(timer); resolve();
        } else if (Date.now() - startedAt > 10_000) {
          clearInterval(timer); reject(new Error(`MEDIA_STATE_TIMEOUT_${expected}`));
        }
      }, 50);
    });
  }

  private async disposePlayer(): Promise<void> {
    if (this.player !== null) {
      try { await this.player.stop(); } catch (_) {}
      try { await this.player.release(); } catch (_) {}
      this.player = null;
    }
    if (this.openedFd !== null) { try { fs.closeSync(this.openedFd); } catch (_) {} this.openedFd = null; }
    await this.stopBackground();
    if (this.session !== null) {
      try { await this.session.deactivate(); } catch (_) {}
      try { await this.session.destroy(); } catch (_) {}
      this.session = null;
    }
    this.current = { assetId: null, state: 'idle', positionMs: 0, durationMs: 0, speed: 1, errorCode: null };
    this.emit();
  }

  private speedValue(speed: number): media.PlaybackSpeed {
    if (speed < 1.0) return media.PlaybackSpeed.SPEED_FORWARD_0_75_X;
    if (speed <= 1.0) return media.PlaybackSpeed.SPEED_FORWARD_1_00_X;
    return media.PlaybackSpeed.SPEED_FORWARD_1_25_X;
  }

  private async ensureMediaSession(assetId: string): Promise<void> {
    const session = await avSession.createAVSession(this.context, 'bess-audio', 'audio');
    this.session = session;
    session.on('play', () => { this.resume(); });
    session.on('pause', () => { this.pause(); });
    session.on('stop', () => { this.stop(); });
    session.on('seek', (position: number) => { this.seekTo(position); });
    await session.setAVMetadata({
      assetId: assetId, title: await this.displayTitle(assetId), artist: 'BESS 储能英语实战',
      duration: this.current.durationMs
    });
    await session.activate();
    await this.updateSessionState();
  }

  private async updateSessionState(): Promise<void> {
    if (this.session === null) return;
    let state = avSession.PlaybackState.PLAYBACK_STATE_PREPARE;
    if (this.current.state === 'playing') state = avSession.PlaybackState.PLAYBACK_STATE_PLAY;
    else if (this.current.state === 'paused') state = avSession.PlaybackState.PLAYBACK_STATE_PAUSE;
    else if (this.current.state === 'completed') state = avSession.PlaybackState.PLAYBACK_STATE_COMPLETED;
    try {
      await this.session.setAVPlaybackState({ state: state, speed: this.current.speed,
        position: { elapsedTime: this.current.positionMs, updateTime: Date.now() } });
    } catch (_) {}
  }

  private async startBackground(): Promise<void> {
    if (this.backgroundRunning) return;
    const agent = await wantAgent.getWantAgent({
      wants: [{ bundleName: 'com.bess.salestrainer', abilityName: 'EntryAbility' }],
      actionType: wantAgent.OperationType.START_ABILITY, requestCode: 20021,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    });
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
