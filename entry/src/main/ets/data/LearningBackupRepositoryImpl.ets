import { deviceInfo } from '@kit.BasicServicesKit';
import { bundleManager } from '@kit.AbilityKit';
import {
  AppSupportInfo, DocumentRef, LearningBackupCounts, LearningBackupInspection, OperationResult
} from '../domain/Models';
import { LearningBackupRepository } from '../domain/Repositories';
import { DatabaseService, DATABASE_VERSION } from './DatabaseService';
import { FileService } from './FileService';
import {
  DecodedLearningBackup, LearningBackupCodec, MAX_BACKUP_CONTAINER_BYTES
} from './LearningBackupCodec';
import { LearningDataStore } from './LearningDataStore';
import { ArchiveLimits, safeArchive } from './SafeArchive';
import { SettingsRepositoryImpl } from './SettingsRepositoryImpl';
import { utf8 } from './Binary';

const APP_VERSION_NAME = '0.2.2';
const APP_VERSION_CODE = 4;
const BACKUP_LIMITS: ArchiveLimits = {
  maxContainerBytes: MAX_BACKUP_CONTAINER_BYTES,
  maxEntryBytes: 32 * 1024 * 1024 + 64 * 1024,
  maxTotalBytes: 34 * 1024 * 1024,
  maxEntries: 2
};

interface PreviewRecord {
  decoded: DecodedLearningBackup;
  corpusMatches: boolean;
}

interface DiagnosticsReport {
  formatVersion: number; generatedAtEpochMs: number; appVersionName: string; appVersionCode: number;
  databaseVersion: number; systemName: string; systemVersion: string; architecture: string;
  corpusPackageKey: string | null; corpusContentVersion: string | null;
  recordCounts: LearningBackupCounts;
  lastBackupAtEpochMs: number | null; lastErrorCode: string | null;
  signingFingerprint: string;
}

export class LearningBackupRepositoryImpl implements LearningBackupRepository {
  private readonly previews = new Map<string, PreviewRecord>();
  private lastErrorCode: string | null = null;
  private readonly database: DatabaseService;
  private readonly files: FileService;
  private readonly settings: SettingsRepositoryImpl;
  private readonly codec: LearningBackupCodec;

  constructor(
    database: DatabaseService, files: FileService, settings: SettingsRepositoryImpl,
    codec: LearningBackupCodec
  ) {
    this.database = database; this.files = files; this.settings = settings; this.codec = codec;
  }

  async export(destination: DocumentRef, password?: string): Promise<OperationResult> {
    try {
      const state = new LearningDataStore(this.database);
      const payload = await state.snapshot();
      const corpusPackageKey = await this.database.metadata('active_corpus_package_key');
      const corpusContentVersion = await this.database.metadata('active_corpus_content_version');
      const now = Date.now();
      const bytes = await this.codec.encode(payload, {
        createdAtEpochMs: now, appVersionName: APP_VERSION_NAME, appVersionCode: APP_VERSION_CODE,
        databaseVersion: DATABASE_VERSION, corpusPackageKey: corpusPackageKey,
        corpusContentVersion: corpusContentVersion
      }, password);
      this.files.writeDocument(destination, bytes);
      const appSettings = await this.settings.get();
      appSettings.lastBackupAtEpochMs = now;
      await this.settings.save(appSettings);
      return this.success('学习记录已导出');
    } catch (error) {
      return this.failure(error);
    }
  }

  async inspect(source: DocumentRef, password?: string): Promise<LearningBackupInspection> {
    // HarmonyOS zlib requires the temporary input path to use a ZIP suffix.
    // The public backup remains a .bessbackup container.
    const zipPath = this.files.tempFile('backup-inspect', '.zip');
    const outputPath = this.files.tempDirectory('backup-unpacked');
    try {
      const bytes = this.files.copyDocumentToPath(source, zipPath, MAX_BACKUP_CONTAINER_BYTES);
      const entries = safeArchive.inspect(bytes, BACKUP_LIMITS);
      const actual = entries.map(item => item.name).sort().join('|');
      const expected = this.codec.expectedEntries().sort().join('|');
      if (actual !== expected) throw new Error('INVALID_BACKUP_ENTRIES');
      await safeArchive.extractValidated(zipPath, outputPath, bytes, BACKUP_LIMITS);
      const header = this.files.readPath(`${outputPath}/manifest.json`, 64 * 1024);
      const payload = this.files.readPath(`${outputPath}/learning-data.bin`, 32 * 1024 * 1024 + 16);
      const decoded = await this.codec.decode(header, payload, password);
      const activePackage = await this.database.metadata('active_corpus_package_key');
      const activeVersion = await this.database.metadata('active_corpus_content_version');
      const matches = decoded.header.corpusPackageKey === activePackage &&
        decoded.header.corpusContentVersion === activeVersion;
      const previewId = this.newId('preview');
      this.previews.set(previewId, { decoded: decoded, corpusMatches: matches });
      this.lastErrorCode = null;
      return {
        previewId: previewId, createdAtEpochMs: decoded.header.createdAtEpochMs,
        appVersionName: decoded.header.appVersionName, appVersionCode: decoded.header.appVersionCode,
        databaseVersion: decoded.header.databaseVersion, corpusPackageKey: decoded.header.corpusPackageKey,
        corpusContentVersion: decoded.header.corpusContentVersion, corpusMatches: matches,
        encrypted: decoded.header.encrypted, counts: decoded.header.counts
      };
    } catch (error) {
      this.lastErrorCode = this.errorCode(error);
      throw new Error(this.lastErrorCode);
    } finally {
      this.files.removeTree(zipPath);
      this.files.removeTree(outputPath);
    }
  }

  async restore(previewId: string): Promise<OperationResult> {
    const preview = this.previews.get(previewId);
    if (preview === undefined) return this.failure(new Error('PREVIEW_NOT_FOUND'));
    try {
      await new LearningDataStore(this.database).replaceAll(preview.decoded.payload, preview.corpusMatches);
      this.previews.delete(previewId);
      return this.success(preview.corpusMatches ? '学习记录已完整恢复' : '记录已恢复，旧语料断点已安全终止');
    } catch (error) {
      return this.failure(error);
    }
  }

  async discardPreview(previewId: string): Promise<void> { this.previews.delete(previewId); }

  async getSupportInfo(): Promise<AppSupportInfo> {
    const state = new LearningDataStore(this.database);
    const settings = await this.settings.get();
    return {
      appVersionName: APP_VERSION_NAME, appVersionCode: APP_VERSION_CODE,
      databaseVersion: DATABASE_VERSION,
      corpusPackageKey: await this.database.metadata('active_corpus_package_key'),
      corpusContentVersion: await this.database.metadata('active_corpus_content_version'),
      recordCounts: await state.databaseCounts(), lastBackupAtEpochMs: settings.lastBackupAtEpochMs,
      lastErrorCode: this.lastErrorCode, systemVersion: deviceInfo.osFullName,
      architecture: deviceInfo.abiList, signingFingerprint: await this.signingFingerprint()
    };
  }

  async exportDiagnostics(destination: DocumentRef): Promise<OperationResult> {
    try {
      const support = await this.getSupportInfo();
      const report: DiagnosticsReport = {
        formatVersion: 1, generatedAtEpochMs: Date.now(), appVersionName: support.appVersionName,
        appVersionCode: support.appVersionCode, databaseVersion: support.databaseVersion,
        systemName: 'HarmonyOS', systemVersion: deviceInfo.osFullName,
        architecture: deviceInfo.abiList, corpusPackageKey: support.corpusPackageKey,
        corpusContentVersion: support.corpusContentVersion, recordCounts: support.recordCounts,
        lastBackupAtEpochMs: support.lastBackupAtEpochMs, lastErrorCode: support.lastErrorCode,
        signingFingerprint: support.signingFingerprint
      };
      this.files.writeDocument(destination, utf8(JSON.stringify(report, null, 2)));
      return this.success('诊断报告已导出');
    } catch (error) {
      return this.failure(error);
    }
  }

  private async signingFingerprint(): Promise<string> {
    try {
      const info = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_SIGNATURE_INFO);
      if (info.signatureInfo.fingerprint.length > 0) return info.signatureInfo.fingerprint;
    } catch (_) {}
    return '不可用';
  }

  private success(message: string): OperationResult {
    this.lastErrorCode = null;
    return { ok: true, errorCode: null, message: message };
  }

  private failure(error: Object): OperationResult {
    const code = this.errorCode(error);
    this.lastErrorCode = code;
    return { ok: false, errorCode: code, message: this.userMessage(code) };
  }

  private errorCode(error: Object): string {
    const value = String(error);
    const marker = value.lastIndexOf(':');
    const raw = marker >= 0 ? value.slice(marker + 1) : value;
    const code = raw.trim().replace(new RegExp('[^A-Z0-9_]', 'g'), '_');
    return code.length === 0 ? 'UNKNOWN_ERROR' : code;
  }

  private userMessage(code: string): string {
    if (code === 'WRONG_PASSWORD_OR_DAMAGED') return '密码错误或备份已损坏';
    if (code === 'PASSWORD_REQUIRED') return '此备份需要密码';
    if (code.includes('TOO_LARGE') || code.includes('ZIP_BOMB')) return '备份文件超出安全限制';
    return `操作失败（${code}）`;
  }

  private newId(prefix: string): string {
    return `${prefix}-${Date.now()}-${Math.floor(Math.random() * 1_000_000_000)}`;
  }
}
