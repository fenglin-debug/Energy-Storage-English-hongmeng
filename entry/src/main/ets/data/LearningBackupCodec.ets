import {
  LearningBackupCounts,
  LearningBackupPayload
} from '../domain/Models';
import { base64, fromBase64, utf8, utf8String } from './Binary';
import { cryptoService } from './CryptoService';
import { safeArchive } from './SafeArchive';

export const BACKUP_FORMAT_VERSION = 1;
export const MAX_BACKUP_CONTAINER_BYTES = 40 * 1024 * 1024;
const MAX_PAYLOAD_BYTES = 32 * 1024 * 1024;
const MAX_HEADER_BYTES = 64 * 1024;
const MAX_RECORDS = 500_000;
const MAX_ID_LENGTH = 512;
const MAX_QUEUE_JSON_LENGTH = 1024 * 1024;
const DEFAULT_ITERATIONS = 600_000;
const MIN_ITERATIONS = 100_000;
const MAX_ITERATIONS = 2_000_000;
const HEADER_ENTRY = 'manifest.json';
const PAYLOAD_ENTRY = 'learning-data.bin';
const NONE = 'NONE_SHA256';
const ENCRYPTED = 'AES_256_GCM_PBKDF2_HMAC_SHA256';
const JVM_LONG_MAX_TEXT = '9223372036854775807';

export interface BackupMetadata {
  createdAtEpochMs: number;
  appVersionName: string;
  appVersionCode: number;
  databaseVersion: number;
  corpusPackageKey: string | null;
  corpusContentVersion: string | null;
}

export interface LearningBackupHeader {
  formatVersion: number;
  createdAtEpochMs: number;
  appVersionName: string;
  appVersionCode: number;
  databaseVersion: number;
  corpusPackageKey: string | null;
  corpusContentVersion: string | null;
  encrypted: boolean;
  algorithm: string;
  kdfIterations: number | null;
  saltBase64: string | null;
  nonceBase64: string | null;
  payloadSha256: string;
  counts: LearningBackupCounts;
}

export interface DecodedLearningBackup {
  header: LearningBackupHeader;
  payload: LearningBackupPayload;
}

export class LearningBackupCodec {
  async encode(payload: LearningBackupPayload, metadata: BackupMetadata,
    password?: string): Promise<Uint8Array> {
    this.validatePayload(payload);
    // Android uses Long.MAX_VALUE as the "mastered / never due" sentinel.
    // ArkTS numbers cannot represent it exactly, so preserve the wire value
    // while using Number.MAX_SAFE_INTEGER inside the HarmonyOS database.
    const payloadJson = JSON.stringify(payload).replace(
      new RegExp('"dueAtEpochMs":9007199254740991', 'g'), `"dueAtEpochMs":${JVM_LONG_MAX_TEXT}`);
    const plain = utf8(payloadJson);
    if (plain.length > MAX_PAYLOAD_BYTES) throw new Error('FILE_TOO_LARGE');
    const counts = this.counts(payload);
    const useEncryption = password !== undefined && password.length > 0;
    let header: LearningBackupHeader;
    let storedPayload: Uint8Array;
    if (useEncryption) {
      this.validatePassword(password as string);
      const salt = cryptoService.random(16);
      const nonce = cryptoService.random(12);
      header = this.createHeader(metadata, true, ENCRYPTED, DEFAULT_ITERATIONS,
        base64(salt), base64(nonce), '', counts);
      storedPayload = await cryptoService.encryptAesGcm(plain, password as string, salt, nonce,
        DEFAULT_ITERATIONS, utf8(JSON.stringify(header)));
    } else {
      header = this.createHeader(metadata, false, NONE, null, null, null, '', counts);
      storedPayload = plain;
    }
    header.payloadSha256 = await cryptoService.sha256(storedPayload);
    const headerBytes = utf8(JSON.stringify(header));
    if (headerBytes.length > MAX_HEADER_BYTES) throw new Error('INVALID_HEADER');
    const entries = new Map<string, Uint8Array>();
    entries.set(HEADER_ENTRY, headerBytes);
    entries.set(PAYLOAD_ENTRY, storedPayload);
    const archive = safeArchive.createStored(entries);
    if (archive.length > MAX_BACKUP_CONTAINER_BYTES) throw new Error('FILE_TOO_LARGE');
    return archive;
  }

  async decode(headerBytes: Uint8Array, storedPayload: Uint8Array,
    password?: string): Promise<DecodedLearningBackup> {
    if (headerBytes.length > MAX_HEADER_BYTES || storedPayload.length > MAX_PAYLOAD_BYTES + 16) {
      throw new Error('FILE_TOO_LARGE');
    }
    this.validateJsonDepth(headerBytes, 32);
    const header = JSON.parse(utf8String(headerBytes)) as LearningBackupHeader;
    this.validateHeader(header);
    const digest = await cryptoService.sha256(storedPayload);
    if (digest.toLowerCase() !== header.payloadSha256.toLowerCase()) {
      throw new Error('WRONG_PASSWORD_OR_DAMAGED');
    }
    let plain: Uint8Array;
    if (header.encrypted) {
      if (password === undefined || password.length === 0) throw new Error('PASSWORD_REQUIRED');
      try {
        const aadHeader = this.createHeader({
          createdAtEpochMs: header.createdAtEpochMs,
          appVersionName: header.appVersionName,
          appVersionCode: header.appVersionCode,
          databaseVersion: header.databaseVersion,
          corpusPackageKey: header.corpusPackageKey,
          corpusContentVersion: header.corpusContentVersion
        }, true, header.algorithm, header.kdfIterations, header.saltBase64,
        header.nonceBase64, '', header.counts);
        plain = await cryptoService.decryptAesGcm(storedPayload, password,
          fromBase64(header.saltBase64 as string), fromBase64(header.nonceBase64 as string),
          header.kdfIterations as number, utf8(JSON.stringify(aadHeader)));
      } catch (_) {
        throw new Error('WRONG_PASSWORD_OR_DAMAGED');
      }
    } else {
      plain = storedPayload;
    }
    if (plain.length > MAX_PAYLOAD_BYTES) throw new Error('FILE_TOO_LARGE');
    this.validateJsonDepth(plain, 32);
    const safeJson = utf8String(plain).replace(
      new RegExp('"dueAtEpochMs":9223372036854775807', 'g'), '"dueAtEpochMs":9007199254740991');
    const payload = JSON.parse(safeJson) as LearningBackupPayload;
    this.validatePayload(payload);
    if (!this.sameCounts(this.counts(payload), header.counts)) throw new Error('COUNT_MISMATCH');
    return { header: header, payload: payload };
  }

  expectedEntries(): string[] {
    return [HEADER_ENTRY, PAYLOAD_ENTRY];
  }

  private createHeader(metadata: BackupMetadata, encrypted: boolean, algorithm: string,
    iterations: number | null, salt: string | null, nonce: string | null, hash: string,
    counts: LearningBackupCounts): LearningBackupHeader {
    return {
      formatVersion: BACKUP_FORMAT_VERSION,
      createdAtEpochMs: metadata.createdAtEpochMs,
      appVersionName: metadata.appVersionName,
      appVersionCode: metadata.appVersionCode,
      databaseVersion: metadata.databaseVersion,
      corpusPackageKey: metadata.corpusPackageKey,
      corpusContentVersion: metadata.corpusContentVersion,
      encrypted: encrypted,
      algorithm: algorithm,
      kdfIterations: iterations,
      saltBase64: salt,
      nonceBase64: nonce,
      payloadSha256: hash,
      counts: counts
    };
  }

  private validateHeader(header: LearningBackupHeader): void {
    const required = ['formatVersion', 'createdAtEpochMs', 'appVersionName', 'appVersionCode',
      'databaseVersion', 'corpusPackageKey', 'corpusContentVersion', 'encrypted', 'algorithm',
      'kdfIterations', 'saltBase64', 'nonceBase64', 'payloadSha256', 'counts'];
    const actual = Object.keys(header).sort();
    if (JSON.stringify(actual) !== JSON.stringify(required.sort())) throw new Error('UNKNOWN_HEADER_FIELD');
    if (header.formatVersion !== BACKUP_FORMAT_VERSION) throw new Error('UNSUPPORTED_FORMAT');
    if (!Number.isSafeInteger(header.createdAtEpochMs) || header.createdAtEpochMs < 0 ||
      !Number.isSafeInteger(header.appVersionCode) || !Number.isSafeInteger(header.databaseVersion) ||
      header.appVersionName.length === 0 || header.appVersionName.length > 64 ||
      (header.corpusPackageKey !== null && header.corpusPackageKey.length > MAX_ID_LENGTH) ||
      (header.corpusContentVersion !== null && header.corpusContentVersion.length > MAX_ID_LENGTH)) {
      throw new Error('INVALID_HEADER');
    }
    if (!new RegExp('^[0-9a-fA-F]{64}$').test(header.payloadSha256)) throw new Error('INVALID_HASH');
    if (header.encrypted) {
      if (header.algorithm !== ENCRYPTED || header.kdfIterations === null ||
        header.kdfIterations < MIN_ITERATIONS || header.kdfIterations > MAX_ITERATIONS ||
        header.saltBase64 === null || header.nonceBase64 === null ||
        fromBase64(header.saltBase64).length !== 16 || fromBase64(header.nonceBase64).length !== 12) {
        throw new Error('INVALID_ENCRYPTION_HEADER');
      }
    } else if (header.algorithm !== NONE || header.kdfIterations !== null ||
      header.saltBase64 !== null || header.nonceBase64 !== null) {
      throw new Error('INVALID_PLAIN_HEADER');
    }
  }

  private validatePayload(payload: LearningBackupPayload): void {
    const required = ['wordMemoryStates', 'reviewLogs', 'vocabularyCheckpoints', 'reviewActionKeys',
      'scenarioSessions', 'scenarioTurnProgress', 'studyTasks', 'itemMemoryStates', 'articleProgress'];
    const actual = Object.keys(payload).sort();
    if (JSON.stringify(actual) !== JSON.stringify(required.sort())) throw new Error('UNKNOWN_PAYLOAD_FIELD');
    if (!Array.isArray(payload.wordMemoryStates) || !Array.isArray(payload.reviewLogs) ||
      !Array.isArray(payload.vocabularyCheckpoints) || !Array.isArray(payload.reviewActionKeys) ||
      !Array.isArray(payload.scenarioSessions) || !Array.isArray(payload.scenarioTurnProgress) ||
      !Array.isArray(payload.studyTasks) || !Array.isArray(payload.itemMemoryStates) ||
      !Array.isArray(payload.articleProgress)) throw new Error('INVALID_PAYLOAD_ARRAY');
    const counts = this.counts(payload);
    const total = counts.wordMemoryStates + counts.reviewLogs + counts.vocabularyCheckpoints +
      counts.reviewActionKeys + counts.scenarioSessions + counts.scenarioTurnProgress +
      counts.studyTasks + counts.itemMemoryStates + counts.articleProgress;
    if (total > MAX_RECORDS) throw new Error('TOO_MANY_RECORDS');
    const validId = (value: string): boolean => value.length > 0 && value.length <= MAX_ID_LENGTH;
    if (!payload.wordMemoryStates.every(row => validId(row.wordId)) ||
      !payload.reviewLogs.every(row => validId(row.id) && validId(row.wordId)) ||
      !payload.vocabularyCheckpoints.every(row => validId(row.sessionId) &&
        row.queueWordIdsJson.length <= MAX_QUEUE_JSON_LENGTH) ||
      !payload.reviewActionKeys.every(row => validId(row.actionKey) && validId(row.sessionId)) ||
      !payload.scenarioSessions.every(row => validId(row.id) && validId(row.scenarioId) &&
        row.queuePairIdsJson.length <= MAX_QUEUE_JSON_LENGTH) ||
      !payload.scenarioTurnProgress.every(row => validId(row.sessionId) && validId(row.pairId)) ||
      !payload.itemMemoryStates.every(row => validId(row.itemId) && row.itemType.length <= 32) ||
      !payload.articleProgress.every(row => validId(row.articleId))) {
      throw new Error('INVALID_RECORD');
    }
    this.validateRowKeys(payload.wordMemoryStates, ['wordId','fsrsState','difficulty','stability','dueAtEpochMs',
      'lastReviewAtEpochMs','reps','lapses','masteredUi','lastQuestionMode','isFavorite','learnedContentHash',
      'legacyNormalizedTerm','updatedAtEpochMs']);
    this.validateRowKeys(payload.reviewLogs, ['id','wordId','rating','questionMode','usedHint','revealedAnswer',
      'reviewedAtEpochMs','responseTimeMs','scheduledDays','elapsedDays','stateBefore','stateAfter']);
    this.validateRowKeys(payload.vocabularyCheckpoints, ['sessionId','status','corpusVersion','queueWordIdsJson',
      'currentIndex','questionMode','answerRevealed','hintRevealed','assessmentSubmitted','selectedAssessment',
      'startedAtEpochMs','updatedAtEpochMs']);
    this.validateRowKeys(payload.reviewActionKeys, ['actionKey','sessionId','currentIndex','createdAtEpochMs']);
    this.validateRowKeys(payload.scenarioSessions, ['id','scenarioId','scenarioContentHash','status','currentPairId',
      'currentPairIndex','pairCount','practiceMode','queuePairIdsJson','startedAtEpochMs','completedAtEpochMs','updatedAtEpochMs']);
    this.validateRowKeys(payload.scenarioTurnProgress, ['sessionId','pairId','customerAudioCompleted','customerTextRevealed',
      'keywordsRevealed','answerRevealed','selfRating','updatedAtEpochMs']);
    this.validateRowKeys(payload.studyTasks, ['dateEpochDay','newWordTarget','newWordDone','reviewTarget','reviewDone',
      'recommendedScenarioId','studySeconds','completed','updatedAtEpochMs']);
    this.validateRowKeys(payload.itemMemoryStates, ['itemId','itemType','fsrsState','difficulty','stability','dueAtEpochMs',
      'lastReviewAtEpochMs','reps','lapses','masteredUi','learnedContentHash','updatedAtEpochMs']);
    this.validateRowKeys(payload.articleProgress, ['articleId','lastPositionMs','listenCount','completedAtEpochMs','updatedAtEpochMs']);
    const allRows: Object[] = ([] as Object[]).concat(payload.wordMemoryStates, payload.reviewLogs,
      payload.vocabularyCheckpoints, payload.reviewActionKeys, payload.scenarioSessions,
      payload.scenarioTurnProgress, payload.studyTasks, payload.itemMemoryStates, payload.articleProgress);
    if (allRows.some(row => JSON.stringify(row).length > 1024 * 1024 + 4096)) throw new Error('RECORD_TOO_LARGE');
  }

  private validatePassword(password: string): void {
    const length = Array.from(password.normalize('NFC')).length;
    if (length < 8 || length > 128) throw new Error('INVALID_PASSWORD_LENGTH');
  }

  private validateRowKeys(rows: Object[], expected: string[]): void {
    const signature = JSON.stringify(expected.slice().sort());
    for (const row of rows) {
      if (JSON.stringify(Object.keys(row).sort()) !== signature) throw new Error('UNKNOWN_OR_MISSING_RECORD_FIELD');
    }
  }

  private validateJsonDepth(bytes: Uint8Array, maxDepth: number): void {
    const text = utf8String(bytes);
    let depth = 0;
    let inString = false;
    let escaped = false;
    for (const char of text) {
      if (inString) {
        if (escaped) escaped = false;
        else if (char === '\\') escaped = true;
        else if (char === '"') inString = false;
      } else if (char === '"') inString = true;
      else if (char === '{' || char === '[') {
        depth++;
        if (depth > maxDepth) throw new Error('JSON_TOO_DEEP');
      } else if (char === '}' || char === ']') {
        depth--;
        if (depth < 0) throw new Error('INVALID_JSON');
      }
    }
    if (depth !== 0 || inString) throw new Error('INVALID_JSON');
  }

  private counts(payload: LearningBackupPayload): LearningBackupCounts {
    return {
      wordMemoryStates: payload.wordMemoryStates.length,
      reviewLogs: payload.reviewLogs.length,
      vocabularyCheckpoints: payload.vocabularyCheckpoints.length,
      reviewActionKeys: payload.reviewActionKeys.length,
      scenarioSessions: payload.scenarioSessions.length,
      scenarioTurnProgress: payload.scenarioTurnProgress.length,
      studyTasks: payload.studyTasks.length,
      itemMemoryStates: payload.itemMemoryStates.length,
      articleProgress: payload.articleProgress.length
    };
  }

  private sameCounts(left: LearningBackupCounts, right: LearningBackupCounts): boolean {
    return left.wordMemoryStates === right.wordMemoryStates && left.reviewLogs === right.reviewLogs &&
      left.vocabularyCheckpoints === right.vocabularyCheckpoints &&
      left.reviewActionKeys === right.reviewActionKeys && left.scenarioSessions === right.scenarioSessions &&
      left.scenarioTurnProgress === right.scenarioTurnProgress && left.studyTasks === right.studyTasks &&
      left.itemMemoryStates === right.itemMemoryStates && left.articleProgress === right.articleProgress;
  }
}

export const learningBackupCodec = new LearningBackupCodec();
