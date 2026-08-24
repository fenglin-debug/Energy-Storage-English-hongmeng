import { Article, AudioTransitionReason, PlaybackSnapshot } from '../domain/Models';
import { ArticleRepository, AudioPlaybackRepository, Unsubscribe } from '../domain/Repositories';

export class ArticlePlaybackProgressCoordinator {
  private readonly articles: ArticleRepository;
  private readonly audio: AudioPlaybackRepository;
  private byAssetId = new Map<string, Article>();
  private lastPeriodic = new Map<string, number>();
  private completedAssets = new Set<string>();
  private lastTransitionKey: string = '';
  private unsubscribe: Unsubscribe | null = null;

  constructor(articles: ArticleRepository, audio: AudioPlaybackRepository) {
    this.articles = articles; this.audio = audio;
  }

  async start(): Promise<void> {
    if (this.unsubscribe !== null) return;
    await this.refreshArticles();
    this.unsubscribe = this.audio.subscribe(value => { this.handle(value); });
  }

  private async handle(value: PlaybackSnapshot): Promise<void> {
    const transition = value.transition;
    if (transition !== null && transition.fromAssetId !== null) {
      const key = `${transition.fromAssetId}|${transition.toAssetId ?? ''}|${transition.fromPositionMs}|${transition.reason}`;
      if (key !== this.lastTransitionKey) {
        this.lastTransitionKey = key;
        const previous = await this.articleFor(transition.fromAssetId);
        if (previous !== null && transition.fromPositionMs > 0 &&
          !(transition.reason === AudioTransitionReason.AUTOMATIC && this.completedAssets.has(transition.fromAssetId))) {
          await this.articles.saveProgress(previous.id, transition.fromPositionMs, false);
        }
        this.completedAssets.delete(transition.fromAssetId);
      }
    }
    if (value.assetId === null) return;
    const article = await this.articleFor(value.assetId); if (article === null) return;
    if (value.state === 'completed') {
      if (!this.completedAssets.has(value.assetId)) {
        this.completedAssets.add(value.assetId);
        await this.articles.saveProgress(article.id, article.durationMs, true);
      }
    } else if (value.state === 'paused' && value.positionMs > 0) {
      await this.articles.saveProgress(article.id, value.positionMs, false);
    } else if (value.state === 'playing' && value.positionMs > 0) {
      this.completedAssets.delete(value.assetId);
      const now = Date.now(); const last = this.lastPeriodic.get(value.assetId) ?? 0;
      if (now - last >= 5000) {
        this.lastPeriodic.set(value.assetId, now);
        await this.articles.saveProgress(article.id, value.positionMs, false);
      }
    }
  }

  private async articleFor(assetId: string): Promise<Article | null> {
    let value = this.byAssetId.get(assetId) ?? null;
    if (value === null) { await this.refreshArticles(); value = this.byAssetId.get(assetId) ?? null; }
    return value;
  }

  private async refreshArticles(): Promise<void> {
    const values = await this.articles.list(); this.byAssetId.clear();
    values.forEach(item => { this.byAssetId.set(item.audioAssetId, item); });
  }
}
