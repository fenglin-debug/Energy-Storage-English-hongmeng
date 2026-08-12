import { describe, expect, it } from '@ohos/hypium';
import { LearningBackupPayload } from '../../../main/ets/domain/Models';
import { learningBackupCodec } from '../../../main/ets/data/LearningBackupCodec';
import { ArchiveEntry, safeArchive } from '../../../main/ets/data/SafeArchive';

function emptyPayload(): LearningBackupPayload {
  return { wordMemoryStates: [], reviewLogs: [], vocabularyCheckpoints: [], reviewActionKeys: [],
    scenarioSessions: [], scenarioTurnProgress: [], studyTasks: [], itemMemoryStates: [], articleProgress: [] };
}

export default function backupCodecTests(): void {
  describe('bessbackup v1', () => {
    it('writes exactly two deterministic entries', 0, async () => {
      const bytes = await learningBackupCodec.encode(emptyPayload(), {
        createdAtEpochMs: 1800000000000, appVersionName: '0.2.0', appVersionCode: 2,
        databaseVersion: 1, corpusPackageKey: null, corpusContentVersion: null
      });
      const names = safeArchive.inspect(bytes, { maxContainerBytes: 40 * 1024 * 1024,
        maxEntryBytes: 32 * 1024 * 1024, maxTotalBytes: 34 * 1024 * 1024, maxEntries: 2 })
        .map(item => item.name).sort();
      expect(names.join('|')).assertEqual('learning-data.bin|manifest.json');
    });

    it('round trips Unicode password and rejects a wrong password', 0, async () => {
      const bytes = await learningBackupCodec.encode(emptyPayload(), {
        createdAtEpochMs: 1800000000000, appVersionName: '0.2.0', appVersionCode: 2,
        databaseVersion: 1, corpusPackageKey: 'bess:3', corpusContentVersion: '3'
      }, '储能-pass-2026');
      const entries = safeArchive.inspect(bytes, { maxContainerBytes: 40 * 1024 * 1024,
        maxEntryBytes: 32 * 1024 * 1024, maxTotalBytes: 34 * 1024 * 1024, maxEntries: 2 });
      const manifest = entries.find(item => item.name === 'manifest.json');
      const data = entries.find(item => item.name === 'learning-data.bin');
      expect(manifest !== undefined && data !== undefined).assertTrue();
      const manifestEntry = manifest as ArchiveEntry; const dataEntry = data as ArchiveEntry;
      const decoded = await learningBackupCodec.decode(safeArchive.readStoredEntry(bytes, manifestEntry),
        safeArchive.readStoredEntry(bytes, dataEntry), '储能-pass-2026');
      expect(decoded.header.encrypted).assertTrue();
      let rejected = false;
      try {
        await learningBackupCodec.decode(safeArchive.readStoredEntry(bytes, manifestEntry),
          safeArchive.readStoredEntry(bytes, dataEntry), '错误-password');
      } catch (_) { rejected = true; }
      expect(rejected).assertTrue();
    });

    it('rejects traversal before extraction', 0, () => {
      const bad = new Map<string, Uint8Array>(); bad.set('../escape', new Uint8Array([1]));
      let rejected = false;
      try { safeArchive.createStored(bad); } catch (_) { rejected = true; }
      expect(rejected).assertTrue();
    });
  });
}
