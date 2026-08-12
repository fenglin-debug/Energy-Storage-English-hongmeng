import { relationalStore } from '@kit.ArkData';
import { CorpusPreview, DocumentRef, OperationResult } from '../domain/Models';
import { CorpusRepository } from '../domain/Repositories';
import { DatabaseService } from './DatabaseService';
import { FileService } from './FileService';
import { CryptoService } from './CryptoService';
import { CORPUS_LIMITS, PackageValidator, ValidatedCorpus } from './PackageValidator';

const CONTENT_TABLES: string[] = [
  'dialogue_pair_phrases', 'dialogue_pair_words', 'dialogue_pairs', 'dialogue_turns', 'scenarios',
  'vocabulary_aliases', 'vocabulary_entries', 'phrases', 'examples', 'audio_assets', 'audio_file_index'
];

export class CorpusRepositoryImpl implements CorpusRepository {
  private readonly previews = new Map<string, Uint8Array>();
  private readonly database: DatabaseService;
  private readonly files: FileService;
  private readonly crypto: CryptoService;
  constructor(database: DatabaseService, files: FileService, crypto: CryptoService) {
    this.database = database; this.files = files; this.crypto = crypto;
  }

  async activeVersion(): Promise<string | null> { return await this.database.metadata('active_corpus_content_version'); }

  async inspectPackage(source: DocumentRef): Promise<CorpusPreview> {
    const bytes = this.files.readDocument(source, CORPUS_LIMITS.maxContainerBytes);
    const zipPath = this.files.tempFile('corpus-preview', '.zip');
    const extracted = this.files.tempDirectory('corpus-preview-unpacked');
    try {
      this.files.writePath(zipPath, bytes);
      const pack = await new PackageValidator(this.files, this.crypto).corpus(bytes, zipPath, extracted);
      const incoming = new Map<string, string>();
      for (const item of pack.vocabulary) incoming.set(`v:${item.id}`, item.contentHash);
      for (const item of pack.phrases) incoming.set(`p:${item.id}`, item.contentHash);
      for (const item of pack.examples) incoming.set(`e:${item.id}`, item.contentHash);
      for (const item of pack.scenarios) incoming.set(`s:${item.id}`, item.contentHash);
      for (const item of pack.audioAssets) incoming.set(`a:${item.id}`, item.sha256);
      const current = new Map<string, string>();
      await this.addCurrentHashes(current, 'vocabulary_entries', 'v');
      await this.addCurrentHashes(current, 'phrases', 'p');
      await this.addCurrentHashes(current, 'examples', 'e');
      await this.addCurrentHashes(current, 'scenarios', 's');
      await this.addCurrentHashes(current, 'audio_assets', 'a', 'sha256');
      let added = 0; let updated = 0; let unchanged = 0; let removed = 0;
      incoming.forEach((hash: string, key: string) => {
        const previous = current.get(key);
        if (previous === undefined) added += 1;
        else if (previous === hash) unchanged += 1;
        else updated += 1;
      });
      current.forEach((_hash: string, key: string) => { if (!incoming.has(key)) removed += 1; });
      const previewId = `corpus-${Date.now()}-${Math.floor(Math.random() * 1000000)}`;
      this.previews.set(previewId, bytes);
      return {
        previewId: previewId, packageId: pack.manifest.packageId, contentVersion: pack.manifest.contentVersion,
        vocabularyCount: pack.vocabulary.length, phraseCount: pack.phrases.length,
        exampleCount: pack.examples.length, scenarioCount: pack.scenarios.length,
        audioCount: pack.audioAssets.length, addedCount: added, updatedCount: updated,
        removedCount: removed, unchangedCount: unchanged
      };
    } finally {
      this.files.removeTree(zipPath); this.files.removeTree(extracted);
    }
  }

  async activatePreview(previewId: string): Promise<OperationResult> {
    const bytes = this.previews.get(previewId);
    if (bytes === undefined) return this.failure(new Error('CORPUS_PREVIEW_NOT_FOUND'));
    try {
      const result = await this.install(bytes, false);
      if (result.ok) this.previews.delete(previewId);
      return result;
    } catch (error) { return this.failure(error); }
  }

  async discardPreview(previewId: string): Promise<void> { this.previews.delete(previewId); }

  async importPackage(source: DocumentRef): Promise<OperationResult> {
    try {
      const preview = await this.inspectPackage(source);
      return await this.activatePreview(preview.previewId);
    } catch (error) { return this.failure(error); }
  }

  async restoreBundled(): Promise<OperationResult> {
    try { return await this.install(await this.files.rawFile('bundled.besspack'), true); }
    catch (error) { return this.failure(error); }
  }

  async ensureBundledActivated(): Promise<void> {
    if (await this.activeVersion() !== null) return;
    const result = await this.restoreBundled();
    if (!result.ok) throw new Error(result.errorCode ?? 'CORPUS_INSTALL_FAILED');
  }

  private async install(bytes: Uint8Array, bundled: boolean): Promise<OperationResult> {
    // HarmonyOS zlib requires the temporary input path to use a ZIP suffix.
    // The public package remains a .besspack container.
    const zipPath = this.files.tempFile('corpus', '.zip');
    const extracted = this.files.tempDirectory('corpus-unpacked');
    let finalAudioDirectory: string | null = null;
    let previousAudioPaths: string[] = [];
    try {
      previousAudioPaths = await this.audioPaths();
      this.files.writePath(zipPath, bytes);
      const validator = new PackageValidator(this.files, this.crypto);
      const pack = await validator.corpus(bytes, zipPath, extracted);
      const packageKey = `${pack.manifest.packageId}:${pack.manifest.contentVersion}`;
      finalAudioDirectory = `${this.files.requireContext().filesDir}/corpus/${this.safeSegment(packageKey)}-${Date.now()}`;
      this.files.ensureDirectory(finalAudioDirectory);
      await this.database.transaction(async (store: relationalStore.RdbStore) => {
        for (const table of CONTENT_TABLES) await store.executeSql(`DELETE FROM ${table}`);
        await this.insertContent(store, pack, finalAudioDirectory as string);
        const manifestHash = await this.crypto.sha256(this.files.readPath(`${extracted}/manifest.json`, 1024 * 1024));
        await store.executeSql(`INSERT OR REPLACE INTO corpus_versions VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          [packageKey, pack.manifest.packageId, pack.manifest.schemaVersion, pack.manifest.contentVersion,
            pack.vocabulary.length, pack.scenarios.length, pack.turns.length, pack.pairs.length,
            pack.audioAssets.length, manifestHash, bundled ? 1 : 0, Date.now()]);
        await store.executeSql('INSERT OR REPLACE INTO active_corpus VALUES (1, ?)', [packageKey]);
        await store.executeSql("INSERT OR REPLACE INTO app_metadata VALUES ('active_corpus_package_key', ?)", [packageKey]);
        await store.executeSql("INSERT OR REPLACE INTO app_metadata VALUES ('active_corpus_content_version', ?)", [pack.manifest.contentVersion]);
        await store.executeSql(`UPDATE vocabulary_session_checkpoints SET status='EXPIRED',updatedAtEpochMs=?
          WHERE status='IN_PROGRESS' AND corpusVersion<>?`, [Date.now(), pack.manifest.contentVersion]);
        await store.executeSql(`UPDATE scenario_sessions SET status='ABORTED_CORPUS_CHANGED',updatedAtEpochMs=?
          WHERE status='IN_PROGRESS' AND (scenarioId='RANDOM' OR scenarioContentHash NOT IN
          (SELECT contentHash FROM scenarios WHERE id=scenario_sessions.scenarioId))`, [Date.now()]);
      });
      for (const path of previousAudioPaths) this.files.removeTree(path);
      return { ok: true, errorCode: null, message: bundled ? '内置语料已恢复' : '语料包已导入' };
    } catch (error) {
      if (finalAudioDirectory !== null) this.files.removeTree(finalAudioDirectory);
      throw new Error(String(error));
    } finally {
      this.files.removeTree(zipPath); this.files.removeTree(extracted);
    }
  }

  private async insertContent(store: relationalStore.RdbStore, pack: ValidatedCorpus, audioDirectory: string): Promise<void> {
    for (const item of pack.vocabulary) {
      await store.executeSql(`INSERT INTO vocabulary_entries VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)`,
        [item.id, item.term, item.normalizedTerm, item.ipa, item.partOfSpeech ?? '', item.chineseGloss,
          item.englishDefinition ?? null, JSON.stringify(item.collocations ?? []), item.exampleSentenceEn,
          item.exampleSentenceZh ?? null, item.commonMistakes, item.topic, JSON.stringify(item.scenarioTags ?? []),
          item.cefrLevel, item.wordAudioAssetId, item.exampleAudioAssetId, item.contentSource ?? 'CORE', item.contentHash]);
      for (const alias of item.aliases ?? []) await store.executeSql('INSERT INTO vocabulary_aliases VALUES (?, ?, ?)',
        [item.id, alias, alias.trim().toLowerCase()]);
    }
    for (const item of pack.phrases) await store.executeSql(`INSERT INTO phrases VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)`,
      [item.id, item.industry ?? '', item.scene ?? '', item.category ?? '', item.textEn, item.textZh,
        JSON.stringify(item.linkedTermIds ?? []), item.sourceType ?? '', item.audioAssetId, item.contentHash]);
    for (const item of pack.examples) await store.executeSql(`INSERT INTO examples VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)`,
      [item.id, item.industry ?? '', item.scene ?? '', item.speaker ?? '', item.textEn, item.textZh,
        JSON.stringify(item.linkedTermIds ?? []), item.dialogueGroupId ?? null, item.sourceType ?? '', item.audioAssetId, item.contentHash]);
    for (const item of pack.scenarios) await store.executeSql(`INSERT INTO scenarios VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)`,
      [item.id, item.title, item.topic, item.salesStage, item.customerRole, item.difficulty,
        item.projectType, item.estimatedMinutes, item.description ?? null, item.contentHash]);
    for (const item of pack.turns) await store.executeSql(`INSERT INTO dialogue_turns VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [item.id, item.scenarioId, item.turnNo, item.speaker, item.textEn, item.textZh ?? null,
        item.hint ?? null, item.audioAssetId ?? null, item.contentHash]);
    for (const item of pack.pairs) await store.executeSql(`INSERT INTO dialogue_pairs VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [item.id, item.scenarioId, item.pairIndex, item.customerTurnId, item.salesTurnId,
        item.referenceCoreEn, item.referenceChineseHint, JSON.stringify(item.formalAlternatives),
        JSON.stringify(item.scoringPoints), item.riskNote ?? null, item.contentHash]);
    for (const item of pack.pairWords) await store.executeSql('INSERT INTO dialogue_pair_words VALUES (?, ?, ?)',
      [item.pairId, item.wordId, item.sortOrder ?? 0]);
    for (const item of pack.pairPhrases) await store.executeSql('INSERT INTO dialogue_pair_phrases VALUES (?, ?, ?)',
      [item.pairId, item.phraseId, item.sortOrder ?? 0]);
    for (const asset of pack.audioAssets) {
      await store.executeSql('INSERT INTO audio_assets VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [asset.id, asset.kind, asset.relativePath, asset.sha256, asset.mimeType ?? 'audio/mp4',
          asset.codec ?? 'aac-lc', asset.durationMs, asset.sizeBytes]);
      const local = `${audioDirectory}/${this.safeSegment(asset.id)}.m4a`;
      this.files.copyPath(`${pack.extractedPath}/${asset.relativePath}`, local, 64 * 1024 * 1024);
      await store.executeSql('INSERT INTO audio_file_index VALUES (?, ?, ?)', [asset.id, local, 'CORPUS']);
    }
  }

  private safeSegment(value: string): string { return value.replace(new RegExp('[^A-Za-z0-9._-]', 'g'), '_'); }
  private async addCurrentHashes(output: Map<string, string>, table: string, prefix: string,
    hashColumn: string = 'contentHash'): Promise<void> {
    const result = await this.database.get().querySql(`SELECT id,${hashColumn} FROM ${table}`);
    try {
      if (result.goToFirstRow()) do { output.set(`${prefix}:${result.getString(0)}`, result.getString(1)); }
      while (result.goToNextRow());
    } finally { result.close(); }
  }
  private async audioPaths(): Promise<string[]> {
    const result = await this.database.get().querySql("SELECT localPath FROM audio_file_index WHERE source='CORPUS'");
    const output: string[] = [];
    try { if (result.goToFirstRow()) do { output.push(result.getString(0)); } while (result.goToNextRow()); } finally { result.close(); }
    return output;
  }
  private failure(error: Object): OperationResult {
    const raw = String(error); const marker = raw.lastIndexOf(':');
    const code = (marker >= 0 ? raw.slice(marker + 1) : raw).trim().replace(new RegExp('[^A-Z0-9_]', 'g'), '_');
    return { ok: false, errorCode: code || 'CORPUS_IMPORT_FAILED', message: `语料操作失败（${code || 'CORPUS_IMPORT_FAILED'}）` };
  }
}
