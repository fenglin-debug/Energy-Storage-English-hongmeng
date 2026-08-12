import { relationalStore } from '@kit.ArkData';
import {
  ArticleProgressRow,
  ItemMemoryStateRow,
  LearningBackupCounts,
  LearningBackupPayload,
  ReviewActionKeyRow,
  ReviewLogRow,
  ScenarioSessionRow,
  ScenarioTurnProgressRow,
  StudyTaskRow,
  VocabularyCheckpointRow,
  WordMemoryStateRow
} from '../domain/Models';
import { DatabaseService } from './DatabaseService';
import {
  booleanValue, integerValue, nullableInteger, nullableString, numberValue,
  queryRows, scalarNumber, stringValue
} from './RdbHelpers';

const LEARNING_TABLES: string[] = [
  'word_memory_states', 'review_logs', 'vocabulary_session_checkpoints', 'review_action_keys',
  'scenario_sessions', 'scenario_turn_progress', 'study_tasks', 'item_memory_states', 'article_progress'
];

export class LearningDataStore {
  private readonly database: DatabaseService;
  constructor(database: DatabaseService) { this.database = database; }

  async snapshot(): Promise<LearningBackupPayload> {
    const store = this.database.get();
    return {
      wordMemoryStates: await queryRows(store, 'SELECT * FROM word_memory_states ORDER BY wordId', mapWordMemory),
      reviewLogs: await queryRows(store, 'SELECT * FROM review_logs ORDER BY reviewedAtEpochMs, id', mapReviewLog),
      vocabularyCheckpoints: await queryRows(store, 'SELECT * FROM vocabulary_session_checkpoints ORDER BY sessionId', mapCheckpoint),
      reviewActionKeys: await queryRows(store, 'SELECT * FROM review_action_keys ORDER BY createdAtEpochMs, actionKey', mapActionKey),
      scenarioSessions: await queryRows(store, 'SELECT * FROM scenario_sessions ORDER BY startedAtEpochMs, id', mapScenarioSession),
      scenarioTurnProgress: await queryRows(store, 'SELECT * FROM scenario_turn_progress ORDER BY sessionId, pairId', mapScenarioTurn),
      studyTasks: await queryRows(store, 'SELECT * FROM study_tasks ORDER BY dateEpochDay', mapStudyTask),
      itemMemoryStates: await queryRows(store, 'SELECT * FROM item_memory_states ORDER BY itemType, itemId', mapItemMemory),
      articleProgress: await queryRows(store, 'SELECT * FROM article_progress ORDER BY articleId', mapArticleProgress)
    };
  }

  counts(payload: LearningBackupPayload): LearningBackupCounts {
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

  async databaseCounts(): Promise<LearningBackupCounts> {
    const store = this.database.get();
    return {
      wordMemoryStates: await scalarNumber(store, 'SELECT COUNT(*) FROM word_memory_states'),
      reviewLogs: await scalarNumber(store, 'SELECT COUNT(*) FROM review_logs'),
      vocabularyCheckpoints: await scalarNumber(store, 'SELECT COUNT(*) FROM vocabulary_session_checkpoints'),
      reviewActionKeys: await scalarNumber(store, 'SELECT COUNT(*) FROM review_action_keys'),
      scenarioSessions: await scalarNumber(store, 'SELECT COUNT(*) FROM scenario_sessions'),
      scenarioTurnProgress: await scalarNumber(store, 'SELECT COUNT(*) FROM scenario_turn_progress'),
      studyTasks: await scalarNumber(store, 'SELECT COUNT(*) FROM study_tasks'),
      itemMemoryStates: await scalarNumber(store, 'SELECT COUNT(*) FROM item_memory_states'),
      articleProgress: await scalarNumber(store, 'SELECT COUNT(*) FROM article_progress')
    };
  }

  async replaceAll(payload: LearningBackupPayload, sameCorpus: boolean): Promise<void> {
    await this.database.transaction(async (store: relationalStore.RdbStore) => {
      for (const table of LEARNING_TABLES) await store.executeSql(`DELETE FROM ${table}`);

      for (const row of payload.wordMemoryStates) {
        await store.executeSql(
          `INSERT INTO word_memory_states VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          [row.wordId, row.fsrsState, row.difficulty, row.stability, row.dueAtEpochMs,
            row.lastReviewAtEpochMs, row.reps, row.lapses, b(row.masteredUi), row.lastQuestionMode,
            b(row.isFavorite), row.learnedContentHash, row.legacyNormalizedTerm, row.updatedAtEpochMs]);
      }
      for (const row of payload.reviewLogs) {
        await store.executeSql(`INSERT INTO review_logs VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          [row.id, row.wordId, row.rating, row.questionMode, b(row.usedHint), b(row.revealedAnswer),
            row.reviewedAtEpochMs, row.responseTimeMs, row.scheduledDays, row.elapsedDays,
            row.stateBefore, row.stateAfter]);
      }
      for (const row of payload.vocabularyCheckpoints) {
        await store.executeSql(`INSERT INTO vocabulary_session_checkpoints VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          [row.sessionId, sameCorpus || row.status !== 'IN_PROGRESS' ? row.status : 'EXPIRED',
            row.corpusVersion, row.queueWordIdsJson, row.currentIndex, row.questionMode,
            b(row.answerRevealed), b(row.hintRevealed), b(row.assessmentSubmitted), row.selectedAssessment,
            row.startedAtEpochMs, row.updatedAtEpochMs]);
      }
      for (const row of payload.reviewActionKeys) {
        await store.executeSql('INSERT INTO review_action_keys VALUES (?, ?, ?, ?)',
          [row.actionKey, row.sessionId, row.currentIndex, row.createdAtEpochMs]);
      }
      for (const row of payload.scenarioSessions) {
        await store.executeSql(`INSERT INTO scenario_sessions VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          [row.id, row.scenarioId, row.scenarioContentHash,
            sameCorpus || row.status !== 'IN_PROGRESS' ? row.status : 'ABORTED_CORPUS_CHANGED',
            row.currentPairId, row.currentPairIndex, row.pairCount, row.practiceMode, row.queuePairIdsJson,
            row.startedAtEpochMs, row.completedAtEpochMs, row.updatedAtEpochMs]);
      }
      for (const row of payload.scenarioTurnProgress) {
        await store.executeSql('INSERT INTO scenario_turn_progress VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
          [row.sessionId, row.pairId, b(row.customerAudioCompleted), b(row.customerTextRevealed),
            b(row.keywordsRevealed), b(row.answerRevealed), row.selfRating, row.updatedAtEpochMs]);
      }
      for (const row of payload.studyTasks) {
        await store.executeSql('INSERT INTO study_tasks VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [row.dateEpochDay, row.newWordTarget, row.newWordDone, row.reviewTarget, row.reviewDone,
            row.recommendedScenarioId, row.studySeconds, b(row.completed), row.updatedAtEpochMs]);
      }
      for (const row of payload.itemMemoryStates) {
        await store.executeSql('INSERT INTO item_memory_states VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [row.itemId, row.itemType, row.fsrsState, row.difficulty, row.stability, row.dueAtEpochMs,
            row.lastReviewAtEpochMs, row.reps, row.lapses, b(row.masteredUi), row.learnedContentHash,
            row.updatedAtEpochMs]);
      }
      for (const row of payload.articleProgress) {
        await store.executeSql('INSERT INTO article_progress VALUES (?, ?, ?, ?, ?)',
          [row.articleId, row.lastPositionMs, row.listenCount, row.completedAtEpochMs, row.updatedAtEpochMs]);
      }
    });
  }
}

function b(value: boolean): number { return value ? 1 : 0; }

function mapWordMemory(r: relationalStore.ResultSet): WordMemoryStateRow {
  return { wordId: stringValue(r, 'wordId'), fsrsState: stringValue(r, 'fsrsState'),
    difficulty: numberValue(r, 'difficulty'), stability: numberValue(r, 'stability'),
    dueAtEpochMs: integerValue(r, 'dueAtEpochMs'), lastReviewAtEpochMs: nullableInteger(r, 'lastReviewAtEpochMs'),
    reps: integerValue(r, 'reps'), lapses: integerValue(r, 'lapses'), masteredUi: booleanValue(r, 'masteredUi'),
    lastQuestionMode: nullableString(r, 'lastQuestionMode'), isFavorite: booleanValue(r, 'isFavorite'),
    learnedContentHash: nullableString(r, 'learnedContentHash'), legacyNormalizedTerm: nullableString(r, 'legacyNormalizedTerm'),
    updatedAtEpochMs: integerValue(r, 'updatedAtEpochMs') };
}

function mapReviewLog(r: relationalStore.ResultSet): ReviewLogRow {
  return { id: stringValue(r, 'id'), wordId: stringValue(r, 'wordId'), rating: stringValue(r, 'rating'),
    questionMode: stringValue(r, 'questionMode'), usedHint: booleanValue(r, 'usedHint'),
    revealedAnswer: booleanValue(r, 'revealedAnswer'), reviewedAtEpochMs: integerValue(r, 'reviewedAtEpochMs'),
    responseTimeMs: nullableInteger(r, 'responseTimeMs'), scheduledDays: integerValue(r, 'scheduledDays'),
    elapsedDays: integerValue(r, 'elapsedDays'), stateBefore: stringValue(r, 'stateBefore'),
    stateAfter: stringValue(r, 'stateAfter') };
}

function mapCheckpoint(r: relationalStore.ResultSet): VocabularyCheckpointRow {
  return { sessionId: stringValue(r, 'sessionId'), status: stringValue(r, 'status'),
    corpusVersion: stringValue(r, 'corpusVersion'), queueWordIdsJson: stringValue(r, 'queueWordIdsJson'),
    currentIndex: integerValue(r, 'currentIndex'), questionMode: stringValue(r, 'questionMode'),
    answerRevealed: booleanValue(r, 'answerRevealed'), hintRevealed: booleanValue(r, 'hintRevealed'),
    assessmentSubmitted: booleanValue(r, 'assessmentSubmitted'), selectedAssessment: nullableString(r, 'selectedAssessment'),
    startedAtEpochMs: integerValue(r, 'startedAtEpochMs'), updatedAtEpochMs: integerValue(r, 'updatedAtEpochMs') };
}

function mapActionKey(r: relationalStore.ResultSet): ReviewActionKeyRow {
  return { actionKey: stringValue(r, 'actionKey'), sessionId: stringValue(r, 'sessionId'),
    currentIndex: integerValue(r, 'currentIndex'), createdAtEpochMs: integerValue(r, 'createdAtEpochMs') };
}

function mapScenarioSession(r: relationalStore.ResultSet): ScenarioSessionRow {
  return { id: stringValue(r, 'id'), scenarioId: stringValue(r, 'scenarioId'),
    scenarioContentHash: stringValue(r, 'scenarioContentHash'), status: stringValue(r, 'status'),
    currentPairId: nullableString(r, 'currentPairId'), currentPairIndex: integerValue(r, 'currentPairIndex'),
    pairCount: integerValue(r, 'pairCount'), practiceMode: stringValue(r, 'practiceMode'),
    queuePairIdsJson: stringValue(r, 'queuePairIdsJson'), startedAtEpochMs: integerValue(r, 'startedAtEpochMs'),
    completedAtEpochMs: nullableInteger(r, 'completedAtEpochMs'), updatedAtEpochMs: integerValue(r, 'updatedAtEpochMs') };
}

function mapScenarioTurn(r: relationalStore.ResultSet): ScenarioTurnProgressRow {
  return { sessionId: stringValue(r, 'sessionId'), pairId: stringValue(r, 'pairId'),
    customerAudioCompleted: booleanValue(r, 'customerAudioCompleted'), customerTextRevealed: booleanValue(r, 'customerTextRevealed'),
    keywordsRevealed: booleanValue(r, 'keywordsRevealed'), answerRevealed: booleanValue(r, 'answerRevealed'),
    selfRating: nullableString(r, 'selfRating'), updatedAtEpochMs: integerValue(r, 'updatedAtEpochMs') };
}

function mapStudyTask(r: relationalStore.ResultSet): StudyTaskRow {
  return { dateEpochDay: integerValue(r, 'dateEpochDay'), newWordTarget: integerValue(r, 'newWordTarget'),
    newWordDone: integerValue(r, 'newWordDone'), reviewTarget: integerValue(r, 'reviewTarget'),
    reviewDone: integerValue(r, 'reviewDone'), recommendedScenarioId: nullableString(r, 'recommendedScenarioId'),
    studySeconds: integerValue(r, 'studySeconds'), completed: booleanValue(r, 'completed'),
    updatedAtEpochMs: integerValue(r, 'updatedAtEpochMs') };
}

function mapItemMemory(r: relationalStore.ResultSet): ItemMemoryStateRow {
  return { itemId: stringValue(r, 'itemId'), itemType: stringValue(r, 'itemType'), fsrsState: stringValue(r, 'fsrsState'),
    difficulty: numberValue(r, 'difficulty'), stability: numberValue(r, 'stability'), dueAtEpochMs: integerValue(r, 'dueAtEpochMs'),
    lastReviewAtEpochMs: nullableInteger(r, 'lastReviewAtEpochMs'), reps: integerValue(r, 'reps'), lapses: integerValue(r, 'lapses'),
    masteredUi: booleanValue(r, 'masteredUi'), learnedContentHash: nullableString(r, 'learnedContentHash'),
    updatedAtEpochMs: integerValue(r, 'updatedAtEpochMs') };
}

function mapArticleProgress(r: relationalStore.ResultSet): ArticleProgressRow {
  return { articleId: stringValue(r, 'articleId'), lastPositionMs: integerValue(r, 'lastPositionMs'),
    listenCount: integerValue(r, 'listenCount'), completedAtEpochMs: nullableInteger(r, 'completedAtEpochMs'),
    updatedAtEpochMs: integerValue(r, 'updatedAtEpochMs') };
}
