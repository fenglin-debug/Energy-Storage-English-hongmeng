import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const DATABASE_NAME = 'bess.db';
export const DATABASE_VERSION = 1;

const SCHEMA_SQL: string[] = [
  'CREATE TABLE IF NOT EXISTS corpus_versions (packageKey TEXT NOT NULL PRIMARY KEY, packageId TEXT NOT NULL, schemaVersion INTEGER NOT NULL, contentVersion TEXT NOT NULL, vocabularyCount INTEGER NOT NULL, scenarioCount INTEGER NOT NULL, dialogueTurnCount INTEGER NOT NULL, dialoguePairCount INTEGER NOT NULL, audioAssetCount INTEGER NOT NULL, manifestSha256 TEXT NOT NULL, isBundled INTEGER NOT NULL, importedAtEpochMs INTEGER NOT NULL)',
  'CREATE TABLE IF NOT EXISTS active_corpus (id INTEGER NOT NULL PRIMARY KEY, packageKey TEXT NOT NULL)',
  'CREATE TABLE IF NOT EXISTS vocabulary_entries (id TEXT NOT NULL PRIMARY KEY, term TEXT NOT NULL, normalizedTerm TEXT NOT NULL, ipa TEXT NOT NULL, partOfSpeech TEXT NOT NULL, chineseGloss TEXT NOT NULL, englishDefinition TEXT, collocationsJson TEXT NOT NULL, exampleSentenceEn TEXT NOT NULL, exampleSentenceZh TEXT, commonMistakes TEXT NOT NULL, topic TEXT NOT NULL, scenarioTagsJson TEXT NOT NULL, cefrLevel TEXT NOT NULL, wordAudioAssetId TEXT NOT NULL, exampleAudioAssetId TEXT NOT NULL, contentSource TEXT NOT NULL, contentHash TEXT NOT NULL, active INTEGER NOT NULL)',
  'CREATE UNIQUE INDEX IF NOT EXISTS index_vocabulary_entries_normalizedTerm ON vocabulary_entries(normalizedTerm)',
  'CREATE INDEX IF NOT EXISTS index_vocabulary_entries_topic ON vocabulary_entries(topic)',
  'CREATE INDEX IF NOT EXISTS index_vocabulary_entries_cefrLevel ON vocabulary_entries(cefrLevel)',
  'CREATE INDEX IF NOT EXISTS index_vocabulary_entries_active ON vocabulary_entries(active)',
  'CREATE TABLE IF NOT EXISTS vocabulary_aliases (wordId TEXT NOT NULL, alias TEXT NOT NULL, aliasNormalized TEXT NOT NULL, PRIMARY KEY(wordId, aliasNormalized))',
  'CREATE INDEX IF NOT EXISTS index_vocabulary_aliases_aliasNormalized ON vocabulary_aliases(aliasNormalized)',
  'CREATE TABLE IF NOT EXISTS scenarios (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, topic TEXT NOT NULL, salesStage TEXT NOT NULL, customerRole TEXT NOT NULL, difficulty TEXT NOT NULL, projectType TEXT NOT NULL, estimatedMinutes INTEGER NOT NULL, description TEXT, contentHash TEXT NOT NULL, active INTEGER NOT NULL)',
  'CREATE INDEX IF NOT EXISTS index_scenarios_topic ON scenarios(topic)',
  'CREATE INDEX IF NOT EXISTS index_scenarios_salesStage ON scenarios(salesStage)',
  'CREATE INDEX IF NOT EXISTS index_scenarios_difficulty ON scenarios(difficulty)',
  'CREATE INDEX IF NOT EXISTS index_scenarios_active ON scenarios(active)',
  'CREATE TABLE IF NOT EXISTS dialogue_turns (id TEXT NOT NULL PRIMARY KEY, scenarioId TEXT NOT NULL, turnNo INTEGER NOT NULL, speaker TEXT NOT NULL, textEn TEXT NOT NULL, textZh TEXT, hint TEXT, audioAssetId TEXT, contentHash TEXT NOT NULL)',
  'CREATE UNIQUE INDEX IF NOT EXISTS index_dialogue_turns_scenarioId_turnNo ON dialogue_turns(scenarioId, turnNo)',
  'CREATE TABLE IF NOT EXISTS dialogue_pairs (id TEXT NOT NULL PRIMARY KEY, scenarioId TEXT NOT NULL, pairIndex INTEGER NOT NULL, customerTurnId TEXT NOT NULL, salesTurnId TEXT NOT NULL, referenceCoreEn TEXT NOT NULL, referenceChineseHint TEXT NOT NULL, formalAlternativesJson TEXT NOT NULL, scoringPointsJson TEXT NOT NULL, riskNote TEXT, contentHash TEXT NOT NULL)',
  'CREATE UNIQUE INDEX IF NOT EXISTS index_dialogue_pairs_scenarioId_pairIndex ON dialogue_pairs(scenarioId, pairIndex)',
  'CREATE TABLE IF NOT EXISTS dialogue_pair_words (pairId TEXT NOT NULL, wordId TEXT NOT NULL, sortOrder INTEGER NOT NULL, PRIMARY KEY(pairId, wordId))',
  'CREATE INDEX IF NOT EXISTS index_dialogue_pair_words_wordId ON dialogue_pair_words(wordId)',
  'CREATE TABLE IF NOT EXISTS audio_assets (id TEXT NOT NULL PRIMARY KEY, kind TEXT NOT NULL, relativePath TEXT NOT NULL, sha256 TEXT NOT NULL, mimeType TEXT NOT NULL, codec TEXT NOT NULL, durationMs INTEGER NOT NULL, sizeBytes INTEGER NOT NULL)',
  'CREATE TABLE IF NOT EXISTS phrases (id TEXT NOT NULL PRIMARY KEY, industry TEXT NOT NULL, scene TEXT NOT NULL, category TEXT NOT NULL, textEn TEXT NOT NULL, textZh TEXT NOT NULL, linkedTermIdsJson TEXT NOT NULL, sourceType TEXT NOT NULL, audioAssetId TEXT NOT NULL, contentHash TEXT NOT NULL, active INTEGER NOT NULL)',
  'CREATE INDEX IF NOT EXISTS index_phrases_scene ON phrases(scene)',
  'CREATE INDEX IF NOT EXISTS index_phrases_category ON phrases(category)',
  'CREATE INDEX IF NOT EXISTS index_phrases_active ON phrases(active)',
  'CREATE TABLE IF NOT EXISTS examples (id TEXT NOT NULL PRIMARY KEY, industry TEXT NOT NULL, scene TEXT NOT NULL, speaker TEXT NOT NULL, textEn TEXT NOT NULL, textZh TEXT NOT NULL, linkedTermIdsJson TEXT NOT NULL, dialogueGroupId TEXT, sourceType TEXT NOT NULL, audioAssetId TEXT NOT NULL, contentHash TEXT NOT NULL, active INTEGER NOT NULL)',
  'CREATE INDEX IF NOT EXISTS index_examples_scene ON examples(scene)',
  'CREATE INDEX IF NOT EXISTS index_examples_speaker ON examples(speaker)',
  'CREATE INDEX IF NOT EXISTS index_examples_active ON examples(active)',
  'CREATE TABLE IF NOT EXISTS dialogue_pair_phrases (pairId TEXT NOT NULL, phraseId TEXT NOT NULL, sortOrder INTEGER NOT NULL, PRIMARY KEY(pairId, phraseId))',
  'CREATE INDEX IF NOT EXISTS index_dialogue_pair_phrases_phraseId ON dialogue_pair_phrases(phraseId)',
  'CREATE TABLE IF NOT EXISTS articles (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, titleZh TEXT NOT NULL, topic TEXT NOT NULL, paragraphsJson TEXT NOT NULL, audioAssetId TEXT NOT NULL, durationMs INTEGER NOT NULL, source TEXT NOT NULL, contentScope TEXT NOT NULL, contentHash TEXT NOT NULL, createdAtEpochMs INTEGER NOT NULL)',
  'CREATE INDEX IF NOT EXISTS index_articles_topic ON articles(topic)',
  'CREATE INDEX IF NOT EXISTS index_articles_source ON articles(source)',
  'CREATE TABLE IF NOT EXISTS word_memory_states (wordId TEXT NOT NULL PRIMARY KEY, fsrsState TEXT NOT NULL, difficulty REAL NOT NULL, stability REAL NOT NULL, dueAtEpochMs INTEGER NOT NULL, lastReviewAtEpochMs INTEGER, reps INTEGER NOT NULL, lapses INTEGER NOT NULL, masteredUi INTEGER NOT NULL, lastQuestionMode TEXT, isFavorite INTEGER NOT NULL, learnedContentHash TEXT, legacyNormalizedTerm TEXT, updatedAtEpochMs INTEGER NOT NULL)',
  'CREATE INDEX IF NOT EXISTS index_word_memory_states_dueAtEpochMs ON word_memory_states(dueAtEpochMs)',
  'CREATE TABLE IF NOT EXISTS review_logs (id TEXT NOT NULL PRIMARY KEY, wordId TEXT NOT NULL, rating TEXT NOT NULL, questionMode TEXT NOT NULL, usedHint INTEGER NOT NULL, revealedAnswer INTEGER NOT NULL, reviewedAtEpochMs INTEGER NOT NULL, responseTimeMs INTEGER, scheduledDays INTEGER NOT NULL, elapsedDays INTEGER NOT NULL, stateBefore TEXT NOT NULL, stateAfter TEXT NOT NULL)',
  'CREATE INDEX IF NOT EXISTS index_review_logs_wordId ON review_logs(wordId)',
  'CREATE INDEX IF NOT EXISTS index_review_logs_reviewedAtEpochMs ON review_logs(reviewedAtEpochMs)',
  'CREATE TABLE IF NOT EXISTS vocabulary_session_checkpoints (sessionId TEXT NOT NULL PRIMARY KEY, status TEXT NOT NULL, corpusVersion TEXT NOT NULL, queueWordIdsJson TEXT NOT NULL, currentIndex INTEGER NOT NULL, questionMode TEXT NOT NULL, answerRevealed INTEGER NOT NULL, hintRevealed INTEGER NOT NULL, assessmentSubmitted INTEGER NOT NULL, selectedAssessment TEXT, startedAtEpochMs INTEGER NOT NULL, updatedAtEpochMs INTEGER NOT NULL)',
  'CREATE INDEX IF NOT EXISTS index_vocabulary_session_checkpoints_status ON vocabulary_session_checkpoints(status)',
  'CREATE INDEX IF NOT EXISTS index_vocabulary_session_checkpoints_updatedAtEpochMs ON vocabulary_session_checkpoints(updatedAtEpochMs)',
  'CREATE TABLE IF NOT EXISTS review_action_keys (actionKey TEXT NOT NULL PRIMARY KEY, sessionId TEXT NOT NULL, currentIndex INTEGER NOT NULL, createdAtEpochMs INTEGER NOT NULL)',
  'CREATE TABLE IF NOT EXISTS scenario_sessions (id TEXT NOT NULL PRIMARY KEY, scenarioId TEXT NOT NULL, scenarioContentHash TEXT NOT NULL, status TEXT NOT NULL, currentPairId TEXT, currentPairIndex INTEGER NOT NULL, pairCount INTEGER NOT NULL, practiceMode TEXT NOT NULL, queuePairIdsJson TEXT NOT NULL, startedAtEpochMs INTEGER NOT NULL, completedAtEpochMs INTEGER, updatedAtEpochMs INTEGER NOT NULL)',
  'CREATE INDEX IF NOT EXISTS index_scenario_sessions_scenarioId ON scenario_sessions(scenarioId)',
  'CREATE INDEX IF NOT EXISTS index_scenario_sessions_status ON scenario_sessions(status)',
  'CREATE INDEX IF NOT EXISTS index_scenario_sessions_updatedAtEpochMs ON scenario_sessions(updatedAtEpochMs)',
  'CREATE TABLE IF NOT EXISTS scenario_turn_progress (sessionId TEXT NOT NULL, pairId TEXT NOT NULL, customerAudioCompleted INTEGER NOT NULL, customerTextRevealed INTEGER NOT NULL, keywordsRevealed INTEGER NOT NULL, answerRevealed INTEGER NOT NULL, selfRating TEXT, updatedAtEpochMs INTEGER NOT NULL, PRIMARY KEY(sessionId, pairId))',
  'CREATE TABLE IF NOT EXISTS study_tasks (dateEpochDay INTEGER NOT NULL PRIMARY KEY, newWordTarget INTEGER NOT NULL, newWordDone INTEGER NOT NULL, reviewTarget INTEGER NOT NULL, reviewDone INTEGER NOT NULL, recommendedScenarioId TEXT, studySeconds INTEGER NOT NULL, completed INTEGER NOT NULL, updatedAtEpochMs INTEGER NOT NULL)',
  'CREATE TABLE IF NOT EXISTS corpus_import_events (id TEXT NOT NULL PRIMARY KEY, previewId TEXT, packageKey TEXT, resultCode TEXT NOT NULL, addedCount INTEGER NOT NULL, updatedCount INTEGER NOT NULL, removedCount INTEGER NOT NULL, unchangedCount INTEGER NOT NULL, createdAtEpochMs INTEGER NOT NULL)',
  'CREATE TABLE IF NOT EXISTS item_memory_states (itemId TEXT NOT NULL, itemType TEXT NOT NULL, fsrsState TEXT NOT NULL, difficulty REAL NOT NULL, stability REAL NOT NULL, dueAtEpochMs INTEGER NOT NULL, lastReviewAtEpochMs INTEGER, reps INTEGER NOT NULL, lapses INTEGER NOT NULL, masteredUi INTEGER NOT NULL, learnedContentHash TEXT, updatedAtEpochMs INTEGER NOT NULL, PRIMARY KEY(itemId, itemType))',
  'CREATE INDEX IF NOT EXISTS index_item_memory_states_dueAtEpochMs ON item_memory_states(dueAtEpochMs)',
  'CREATE INDEX IF NOT EXISTS index_item_memory_states_itemType ON item_memory_states(itemType)',
  'CREATE TABLE IF NOT EXISTS article_progress (articleId TEXT NOT NULL PRIMARY KEY, lastPositionMs INTEGER NOT NULL, listenCount INTEGER NOT NULL, completedAtEpochMs INTEGER, updatedAtEpochMs INTEGER NOT NULL)',
  'CREATE TABLE IF NOT EXISTS app_metadata (key TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL)',
  'CREATE TABLE IF NOT EXISTS audio_file_index (assetId TEXT NOT NULL PRIMARY KEY, localPath TEXT NOT NULL, source TEXT NOT NULL)'
];

// Add every future migration explicitly. The key is the source version and
// each SQL list must move exactly one version forward inside one transaction.
const MIGRATIONS = new Map<number, string[]>();

export class DatabaseService {
  private store: relationalStore.RdbStore | null = null;

  async initialize(context: common.UIAbilityContext): Promise<void> {
    if (this.store !== null) return;
    const config: relationalStore.StoreConfig = {
      name: DATABASE_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    const store = await relationalStore.getRdbStore(context, config);
    if (store.version > DATABASE_VERSION) {
      throw new Error(`DB_VERSION_TOO_NEW:${store.version}`);
    }
    if (store.version === 0) {
      await store.beginTransaction();
      try {
        for (const sql of SCHEMA_SQL) {
          await store.executeSql(sql);
        }
        store.version = DATABASE_VERSION;
        await store.commit();
      } catch (error) {
        await store.rollBack();
        throw new Error(String(error));
      }
    } else if (store.version < DATABASE_VERSION) {
      await store.beginTransaction();
      try {
        let version = store.version;
        while (version < DATABASE_VERSION) {
          const statements = MIGRATIONS.get(version);
          if (statements === undefined) throw new Error(`MIGRATION_MISSING:${version}:${version + 1}`);
          for (const sql of statements) await store.executeSql(sql);
          version++;
          store.version = version;
        }
        await store.commit();
      } catch (error) {
        await store.rollBack();
        throw new Error(String(error));
      }
    }
    this.store = store;
  }

  get(): relationalStore.RdbStore {
    if (this.store === null) {
      throw new Error('DATABASE_NOT_INITIALIZED');
    }
    return this.store;
  }

  async transaction<T>(work: (store: relationalStore.RdbStore) => Promise<T>): Promise<T> {
    const store = this.get();
    await store.beginTransaction();
    try {
      const result = await work(store);
      await store.commit();
      return result;
    } catch (error) {
      await store.rollBack();
      throw new Error(String(error));
    }
  }

  async metadata(key: string): Promise<string | null> {
    const result = await this.get().querySql('SELECT value FROM app_metadata WHERE key = ?', [key]);
    try {
      if (!result.goToFirstRow()) return null;
      return result.getString(result.getColumnIndex('value'));
    } finally {
      result.close();
    }
  }

  async putMetadata(key: string, value: string): Promise<void> {
    await this.get().executeSql(
      'INSERT OR REPLACE INTO app_metadata(key, value) VALUES(?, ?)', [key, value]);
  }
}

export const databaseService = new DatabaseService();
