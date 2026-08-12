import { relationalStore } from '@kit.ArkData';
import { Article, ArticleParagraph, DocumentRef, OperationResult } from '../domain/Models';
import { ArticleRepository } from '../domain/Repositories';
import { DatabaseService } from './DatabaseService';
import { FileService } from './FileService';
import { CryptoService } from './CryptoService';
import { ARTICLE_LIMITS, PackageValidator, ValidatedArticlePackage } from './PackageValidator';
import { booleanValue, integerValue, nullableInteger, queryRows, stringValue } from './RdbHelpers';
import { utf8String } from './Binary';

interface LrcCue {
  start: number;
  textEn: string;
  textZh: string;
}

export const MAX_LOCAL_AUDIO_BYTES = 100 * 1024 * 1024;
export const MAX_LOCAL_AUDIO_DURATION_MS = 30 * 60 * 1000;
export const MAX_SUBTITLE_BYTES = 2 * 1024 * 1024;
export const MAX_SUBTITLE_CUES = 10_000;
export const DIRECT_AUDIO_EXTENSIONS: string[] = ['m4a', 'mp3', 'wav'];

export function stableLocalArticleId(audioSha256: string): string {
  return `ART-LOCAL-${audioSha256.slice(0, 20).toUpperCase()}`;
}

export class ArticleRepositoryImpl implements ArticleRepository {
  private readonly database: DatabaseService;
  private readonly files: FileService;
  private readonly crypto: CryptoService;
  constructor(database: DatabaseService, files: FileService, crypto: CryptoService) {
    this.database = database; this.files = files; this.crypto = crypto;
  }

  async list(): Promise<Article[]> {
    return await queryRows(this.database.get(),
      `SELECT a.*, COALESCE(p.lastPositionMs, 0) lastPositionMs FROM articles a
       LEFT JOIN article_progress p ON p.articleId = a.id ORDER BY a.createdAtEpochMs DESC`, mapArticle);
  }

  async get(articleId: string): Promise<Article | null> {
    const rows = await queryRows(this.database.get(),
      `SELECT a.*, COALESCE(p.lastPositionMs, 0) lastPositionMs FROM articles a
       LEFT JOIN article_progress p ON p.articleId = a.id WHERE a.id = ?`, mapArticle, [articleId]);
    return rows.length === 0 ? null : rows[0];
  }

  async randomId(): Promise<string | null> {
    const result = await this.database.get().querySql(`SELECT id FROM articles WHERE contentScope!='UNSPECIFIED' ORDER BY RANDOM() LIMIT 1`);
    try { return result.goToFirstRow() ? result.getString(0) : null; } finally { result.close(); }
  }

  async randomIds(): Promise<string[]> {
    const result = await this.database.get().querySql(`SELECT id FROM articles WHERE contentScope!='UNSPECIFIED' ORDER BY RANDOM()`);
    const output: string[] = [];
    try { if (result.goToFirstRow()) do { output.push(result.getString(0)); } while (result.goToNextRow()); } finally { result.close(); }
    return output;
  }

  async saveProgress(articleId: string, positionMs: number, completed: boolean): Promise<void> {
    const now = Date.now();
    await this.database.get().executeSql(
      `INSERT INTO article_progress(articleId,lastPositionMs,listenCount,completedAtEpochMs,updatedAtEpochMs)
       VALUES(?,?,?, ?,?) ON CONFLICT(articleId) DO UPDATE SET
       lastPositionMs=excluded.lastPositionMs,
       listenCount=article_progress.listenCount + CASE WHEN excluded.completedAtEpochMs IS NULL THEN 0 ELSE 1 END,
       completedAtEpochMs=COALESCE(excluded.completedAtEpochMs, article_progress.completedAtEpochMs),
       updatedAtEpochMs=excluded.updatedAtEpochMs`,
      [articleId, Math.max(0, Math.floor(positionMs)), completed ? 1 : 0, completed ? now : null, now]);
  }

  async importPackage(source: DocumentRef): Promise<OperationResult> {
    try { return await this.installPackage(this.files.readDocument(source, ARTICLE_LIMITS.maxContainerBytes), false); }
    catch (error) { return this.failure(error); }
  }

  async ensureBundledArticles(): Promise<void> {
    const result = await this.database.get().querySql("SELECT COUNT(*) FROM articles WHERE source='BUNDLED'");
    try { if (result.goToFirstRow() && result.getLong(0) > 0) return; } finally { result.close(); }
    const operation = await this.installPackage(await this.files.rawFile('bundled.bessarticle'), true);
    if (!operation.ok) throw new Error(operation.errorCode ?? 'ARTICLE_INSTALL_FAILED');
  }

  async importAudio(audio: DocumentRef, subtitle: DocumentRef | null, audioDisplayName: string,
    subtitleDisplayName: string, title: string, topic: string, includeInRandomPractice: boolean): Promise<OperationResult> {
    try {
      if (title.trim().length === 0) throw new Error('EMPTY_TITLE');
      const extension = this.extension(audioDisplayName);
      if (!DIRECT_AUDIO_EXTENSIONS.includes(extension)) throw new Error('UNSUPPORTED_AUDIO_FORMAT');
      const audioBytes = this.files.readDocument(audio, MAX_LOCAL_AUDIO_BYTES);
      if (audioBytes.length === 0) throw new Error('EMPTY_AUDIO');
      const durationMs = await this.files.mediaDuration(audio);
      if (durationMs > MAX_LOCAL_AUDIO_DURATION_MS) throw new Error('AUDIO_TOO_LONG');
      let paragraphs: ArticleParagraph[] = [];
      if (subtitle !== null) {
        const subtitleBytes = this.files.readDocument(subtitle, MAX_SUBTITLE_BYTES);
        const subtitleText = this.strictUtf8(subtitleBytes);
        paragraphs = this.parseSubtitles(subtitleText, this.extension(subtitleDisplayName), durationMs);
      }
      const audioHash = await this.crypto.sha256(audioBytes);
      const id = stableLocalArticleId(audioHash);
      const directory = `${this.files.requireContext().filesDir}/articles/imported`;
      this.files.ensureDirectory(directory);
      const localPath = `${directory}/${id}.${extension}`;
      const oldRows = await queryRows(this.database.get(), `SELECT a.createdAtEpochMs,i.localPath FROM articles a
        LEFT JOIN audio_file_index i ON i.assetId=a.audioAssetId WHERE a.id=?`, mapExistingArticle, [id]);
      this.files.writePath(localPath, audioBytes);
      await this.database.transaction(async (store: relationalStore.RdbStore) => {
        await store.executeSql('INSERT OR REPLACE INTO articles VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [id, title.trim(), '', topic.trim().length === 0 ? '本地导入' : topic.trim(), JSON.stringify(paragraphs),
            `article-audio-${id}`, durationMs, 'IMPORTED', includeInRandomPractice ? 'BESS' : 'UNSPECIFIED',
            audioHash, oldRows[0]?.createdAtEpochMs ?? Date.now()]);
        await store.executeSql('INSERT OR REPLACE INTO audio_file_index VALUES (?, ?, ?)', [`article-audio-${id}`, localPath, 'ARTICLE']);
      });
      if (oldRows.length > 0 && oldRows[0].localPath !== null && oldRows[0].localPath !== localPath) this.files.removeTree(oldRows[0].localPath);
      return { ok: true, errorCode: null, message: oldRows.length === 0 ? '文章已导入' : '同一音频已更新，收听进度已保留' };
    } catch (error) { return this.failure(error); }
  }

  async deleteImported(articleId: string): Promise<OperationResult> {
    try {
      const result = await this.database.get().querySql(
        `SELECT i.localPath FROM articles a JOIN audio_file_index i ON i.assetId=a.audioAssetId
         WHERE a.id=? AND a.source='IMPORTED'`, [articleId]);
      let path: string | null = null;
      try { if (result.goToFirstRow()) path = result.getString(0); } finally { result.close(); }
      if (path === null) throw new Error('ARTICLE_NOT_DELETABLE');
      await this.database.transaction(async store => {
        await store.executeSql('DELETE FROM article_progress WHERE articleId=?', [articleId]);
        await store.executeSql('DELETE FROM audio_file_index WHERE assetId=(SELECT audioAssetId FROM articles WHERE id=?)', [articleId]);
        await store.executeSql('DELETE FROM articles WHERE id=?', [articleId]);
      });
      this.files.removeTree(path);
      return { ok: true, errorCode: null, message: '导入文章已删除' };
    } catch (error) { return this.failure(error); }
  }

  private async installPackage(bytes: Uint8Array, bundled: boolean): Promise<OperationResult> {
    // HarmonyOS zlib requires the temporary input path to use a ZIP suffix.
    // The public package remains a .bessarticle container.
    const zipPath = this.files.tempFile('articles', '.zip');
    const extracted = this.files.tempDirectory('articles-unpacked');
    const installedPaths: string[] = [];
    const previousPaths: string[] = [];
    try {
      this.files.writePath(zipPath, bytes);
      const pack = await new PackageValidator(this.files, this.crypto).articles(bytes, zipPath, extracted);
      for (const article of pack.manifest.articles) {
        const result = await this.database.get().querySql('SELECT localPath FROM audio_file_index WHERE assetId=?', [`article-audio-${article.id}`]);
        try { if (result.goToFirstRow()) previousPaths.push(result.getString(0)); } finally { result.close(); }
      }
      const directory = `${this.files.requireContext().filesDir}/articles/${bundled ? 'bundled' : 'packages'}/${Date.now()}-${Math.floor(Math.random() * 1_000_000)}`;
      this.files.ensureDirectory(directory);
      await this.database.transaction(async store => {
        await this.insertArticlePackage(store, pack, directory, bundled, installedPaths);
      });
      for (const path of previousPaths) if (!installedPaths.includes(path)) this.files.removeTree(path);
      return { ok: true, errorCode: null, message: `已导入 ${pack.manifest.articles.length} 篇文章` };
    } catch (error) {
      for (const path of installedPaths) this.files.removeTree(path);
      throw new Error(String(error));
    } finally { this.files.removeTree(zipPath); this.files.removeTree(extracted); }
  }

  private async insertArticlePackage(store: relationalStore.RdbStore, pack: ValidatedArticlePackage,
    directory: string, bundled: boolean, installedPaths: string[]): Promise<void> {
    for (const article of pack.manifest.articles) {
      const audioAssetId = `article-audio-${article.id}`;
      const localPath = `${directory}/${this.safeSegment(article.id)}.m4a`;
      this.files.copyPath(`${pack.extractedPath}/${article.audioFile}`, localPath, 32 * 1024 * 1024);
      installedPaths.push(localPath);
      await store.executeSql(`INSERT OR REPLACE INTO articles VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [article.id, article.title, article.titleZh ?? '', article.topic, JSON.stringify(article.paragraphs),
          audioAssetId, article.durationMs, bundled ? 'BUNDLED' : 'IMPORTED', article.contentScope ?? 'UNSPECIFIED',
          article.contentHash, Date.now()]);
      await store.executeSql('INSERT OR REPLACE INTO audio_file_index VALUES (?, ?, ?)',
        [audioAssetId, localPath, 'ARTICLE']);
    }
  }

  private parseSubtitles(text: string, extension: string, audioDurationMs: number): ArticleParagraph[] {
    const output = extension === 'srt' ? this.parseSrt(text) : extension === 'lrc' ? this.parseLrc(text, audioDurationMs) : [];
    if (output.length === 0) throw new Error(extension === 'srt' || extension === 'lrc' ? 'EMPTY_SUBTITLE' : 'UNSUPPORTED_SUBTITLE_FORMAT');
    if (output.length > MAX_SUBTITLE_CUES) throw new Error('TOO_MANY_SUBTITLE_CUES');
    this.validateTimeline(output, audioDurationMs);
    return output;
  }

  private parseSrt(text: string): ArticleParagraph[] {
    const output: ArticleParagraph[] = [];
    for (const block of text.replace(new RegExp('\\r', 'g'), '').split(new RegExp('\\n\\s*\\n'))) {
      const lines = block.split('\n').filter(item => item.trim().length > 0);
      const timingIndex = lines.findIndex(item => item.includes('-->'));
      if (timingIndex < 0 || timingIndex + 1 >= lines.length) throw new Error('INVALID_SUBTITLE_TIMELINE');
      const times = lines[timingIndex].split('-->');
      if (times.length !== 2) throw new Error('INVALID_SUBTITLE_TIMELINE');
      const start = this.timeMs(times[0]); const end = this.timeMs(times[1].trim().split(' ')[0]);
      if (start < 0 || end <= start) throw new Error('INVALID_SUBTITLE_CUE');
      const content = lines.slice(timingIndex + 1).map(item => this.cleanText(item)).filter(item => item.length > 0);
      const english = content.filter(item => !this.containsChinese(item)).join(' ');
      const chinese = content.filter(item => this.containsChinese(item)).join(' ');
      if (english.length === 0) throw new Error('INVALID_SUBTITLE_TIMELINE');
      output.push({ textEn: english, textZh: chinese, startMs: start, endMs: end });
    }
    return output;
  }

  private parseLrc(text: string, audioDurationMs: number): ArticleParagraph[] {
    const pending: LrcCue[] = [];
    for (const line of text.replace(new RegExp('\\r', 'g'), '').split('\n')) {
      const match = new RegExp('^\\[(\\d{1,3}):(\\d{2})(?:[.:](\\d{1,3}))?\\](.*)$').exec(line.trim());
      if (match === null || match[4].trim().length === 0) continue;
      const fraction = (match[3] ?? '0').padEnd(3, '0').slice(0, 3);
      const parts = match[4].trim().split(new RegExp('\\s*[｜|]\\s*'), 2);
      const english = this.cleanText(parts[0] ?? ''); const chinese = this.cleanText(parts[1] ?? '');
      if (english.length === 0) throw new Error('INVALID_SUBTITLE_TIMELINE');
      pending.push({ start: Number(match[1]) * 60_000 + Number(match[2]) * 1000 + Number(fraction), textEn: english, textZh: chinese });
    }
    const output: ArticleParagraph[] = [];
    for (let index = 0; index < pending.length; index++) {
      const item = pending[index];
      output.push({ textEn: item.textEn, textZh: item.textZh, startMs: item.start,
        endMs: index + 1 < pending.length ? pending[index + 1].start : audioDurationMs });
    }
    return output;
  }

  private timeMs(value: string): number {
    const match = new RegExp('^(?:(\\d{1,2}):)?(\\d{1,2}):(\\d{2})[,.](\\d{1,3})$').exec(value.trim());
    if (match === null) return -1;
    const minutes = Number(match[2]); const seconds = Number(match[3]);
    if (minutes > 59 || seconds > 59) return -1;
    const fraction = Number(match[4].padEnd(3, '0').slice(0, 3));
    return Number(match[1] ?? 0) * 3_600_000 + minutes * 60_000 + seconds * 1000 + fraction;
  }

  private validateTimeline(cues: ArticleParagraph[], audioDurationMs: number): void {
    let previousEnd = -1;
    cues.forEach(cue => {
      const start = cue.startMs ?? -1; const end = cue.endMs ?? -1;
      if (start < 0 || end <= start || start < previousEnd || end > audioDurationMs) throw new Error('INVALID_SUBTITLE_TIMELINE');
      previousEnd = end;
    });
  }

  private strictUtf8(bytes: Uint8Array): string {
    if (bytes.length >= 2 && ((bytes[0] === 0xFF && bytes[1] === 0xFE) || (bytes[0] === 0xFE && bytes[1] === 0xFF))) {
      throw new Error('INVALID_SUBTITLE_ENCODING');
    }
    const body = bytes.length >= 3 && bytes[0] === 0xEF && bytes[1] === 0xBB && bytes[2] === 0xBF ? bytes.slice(3) : bytes;
    const text = utf8String(body);
    if (text.includes('\uFFFD')) throw new Error('INVALID_SUBTITLE_ENCODING');
    return text;
  }

  private cleanText(value: string): string {
    return value.replace(new RegExp('<[^>]+>', 'g'), '').replace(new RegExp('\\s+', 'g'), ' ').trim();
  }

  private containsChinese(value: string): boolean { return new RegExp('[\\u3400-\\u9FFF]').test(value); }
  private extension(value: string): string { const dot = value.lastIndexOf('.'); return dot < 0 ? '' : value.slice(dot + 1).toLowerCase(); }

  private safeSegment(value: string): string { return value.replace(new RegExp('[^A-Za-z0-9._-]', 'g'), '_'); }
  private failure(error: Object): OperationResult {
    const raw = String(error); const marker = raw.lastIndexOf(':');
    const code = (marker >= 0 ? raw.slice(marker + 1) : raw).trim().replace(new RegExp('[^A-Z0-9_]', 'g'), '_') || 'ARTICLE_OPERATION_FAILED';
    return { ok: false, errorCode: code, message: `文章操作失败（${code}）` };
  }
}

function mapArticle(r: relationalStore.ResultSet): Article {
  return { id: stringValue(r, 'id'), title: stringValue(r, 'title'), titleZh: stringValue(r, 'titleZh'),
    topic: stringValue(r, 'topic'), paragraphs: JSON.parse(stringValue(r, 'paragraphsJson')) as ArticleParagraph[],
    audioAssetId: stringValue(r, 'audioAssetId'), durationMs: integerValue(r, 'durationMs'), source: stringValue(r, 'source'),
    contentScope: stringValue(r, 'contentScope'), contentHash: stringValue(r, 'contentHash'),
    lastPositionMs: integerValue(r, 'lastPositionMs'), includeInRandomPractice: stringValue(r, 'contentScope') !== 'UNSPECIFIED' };
}

interface ExistingArticle { createdAtEpochMs: number; localPath: string | null; }
function mapExistingArticle(r: relationalStore.ResultSet): ExistingArticle {
  return { createdAtEpochMs: integerValue(r, 'createdAtEpochMs'), localPath: nullableStringValue(r, 'localPath') };
}

function nullableStringValue(r: relationalStore.ResultSet, name: string): string | null {
  const index = r.getColumnIndex(name); return r.isColumnNull(index) ? null : r.getString(index);
}
