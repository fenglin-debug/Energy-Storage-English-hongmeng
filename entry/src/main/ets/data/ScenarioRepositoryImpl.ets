import { relationalStore } from '@kit.ArkData';
import { DialogueSelfRating, ScenarioAdvance, ScenarioKeyword, ScenarioScoringPoint, ScenarioSummary, ScenarioUnitView } from '../domain/Models';
import { ScenarioRepository } from '../domain/Repositories';
import { DatabaseService } from './DatabaseService';
import { booleanValue, integerValue, nullableString, queryRows, stringValue } from './RdbHelpers';

interface SessionState {
  id: string; scenarioId: string; status: string; currentPairId: string | null; currentPairIndex: number;
  pairCount: number; practiceMode: string; queue: string[];
}

interface ProgressGate { revealed: boolean; rating: string | null; }
interface PairMemoryCount { reps: number; lapses: number; }

export class ScenarioRepositoryImpl implements ScenarioRepository {
  private readonly database: DatabaseService;
  constructor(database: DatabaseService) { this.database = database; }

  async list(query: string, onlyIncomplete: boolean = false, difficulty: string = ''): Promise<ScenarioSummary[]> {
    const like = `%${query.trim().toLowerCase().replace(new RegExp('[%_]', 'g'), '\\$&')}%`;
    return await queryRows(this.database.get(),
      `SELECT s.*,COUNT(p.id) pairCount,
       CASE WHEN EXISTS(SELECT 1 FROM scenario_sessions x WHERE x.scenarioId=s.id AND x.status='IN_PROGRESS') THEN 'IN_PROGRESS'
         WHEN EXISTS(SELECT 1 FROM scenario_sessions x WHERE x.scenarioId=s.id AND x.status='COMPLETED') THEN 'COMPLETED' ELSE NULL END sessionStatus,
       (SELECT COUNT(*) FROM dialogue_pairs dp JOIN item_memory_states m ON m.itemId=dp.id AND m.itemType='PAIR'
         WHERE dp.scenarioId=s.id AND m.masteredUi=0 AND m.dueAtEpochMs<=?) duePairCount
       FROM scenarios s LEFT JOIN dialogue_pairs p ON p.scenarioId=s.id
       WHERE s.active=1 AND (?='' OR lower(s.title) LIKE ? ESCAPE '\\' OR lower(s.topic) LIKE ? ESCAPE '\\')
       AND (?='' OR s.difficulty=?)
       AND (?=0 OR NOT EXISTS(SELECT 1 FROM scenario_sessions x WHERE x.scenarioId=s.id AND x.status='COMPLETED'))
       GROUP BY s.id ORDER BY s.id`, mapSummary,
      [Date.now(), query.trim(), like, like, difficulty, difficulty, onlyIncomplete ? 1 : 0]);
  }

  async startOrResume(scenarioId: string): Promise<string> {
    const existing = await this.sessions("WHERE scenarioId=? AND status='IN_PROGRESS' ORDER BY updatedAtEpochMs DESC LIMIT 1", [scenarioId]);
    if (existing.length > 0) return existing[0].id;
    const pairs = await this.ids('SELECT id FROM dialogue_pairs WHERE scenarioId=? ORDER BY pairIndex', [scenarioId]);
    if (pairs.length === 0) throw new Error('SCENARIO_EMPTY');
    return await this.createSession(scenarioId, pairs, 'SCENARIO');
  }

  async startOrResumeRandom(): Promise<string> {
    const existing = await this.sessions("WHERE practiceMode='RANDOM' AND status='IN_PROGRESS' ORDER BY updatedAtEpochMs DESC LIMIT 1");
    if (existing.length > 0) return existing[0].id;
    const pairs = await this.ids(`SELECT p.id FROM dialogue_pairs p JOIN scenarios s ON s.id=p.scenarioId
      WHERE s.active=1 ORDER BY RANDOM() LIMIT 20`);
    if (pairs.length === 0) throw new Error('SCENARIO_EMPTY');
    return await this.createSession('RANDOM', pairs, 'RANDOM');
  }

  async currentUnit(sessionId: string): Promise<ScenarioUnitView | null> {
    const sessions = await this.sessions('WHERE id=?', [sessionId]);
    if (sessions.length === 0 || sessions[0].status !== 'IN_PROGRESS') return null;
    const session = sessions[0]; const pairId = session.queue[session.currentPairIndex];
    if (pairId === undefined) return null;
    const rows = await queryRows(this.database.get(),
      `SELECT p.*,s.title scenarioTitle,t.textEn customerTextEn,t.textZh customerTextZh,
       t.audioAssetId customerAudioAssetId,
       COALESCE(g.customerAudioCompleted,0) customerAudioCompleted,
       COALESCE(g.customerTextRevealed,0) customerTextRevealed,
       COALESCE(g.keywordsRevealed,0) keywordsRevealed,
       COALESCE(g.answerRevealed,0) answerRevealed,g.selfRating
       FROM dialogue_pairs p JOIN dialogue_turns t ON t.id=p.customerTurnId
       JOIN scenarios s ON s.id=p.scenarioId
      LEFT JOIN scenario_turn_progress g ON g.sessionId=? AND g.pairId=p.id WHERE p.id=?`,
      result => this.mapUnit(result, session), [sessionId, pairId]);
    if (rows.length === 0) return null;
    if (rows[0].keywordsRevealed) rows[0].keywords = await this.mapKeywords(pairId);
    return rows[0];
  }

  async markCustomerAudioCompleted(sessionId: string, pairId: string): Promise<void> {
    await this.mutateProgress(sessionId, pairId, 'customerAudioCompleted');
  }
  async revealCustomerText(sessionId: string, pairId: string): Promise<void> {
    const hasAudio = await this.pairHasCustomerAudio(pairId);
    if (hasAudio) {
      const progress = await queryRows(this.database.get(),
        'SELECT customerAudioCompleted FROM scenario_turn_progress WHERE sessionId=? AND pairId=?',
        r => booleanValue(r, 'customerAudioCompleted'), [sessionId, pairId]);
      if (progress.length === 0 || !progress[0]) throw new Error('CUSTOMER_AUDIO_NOT_COMPLETED');
    }
    await this.mutateProgress(sessionId, pairId, 'customerTextRevealed');
  }
  async revealKeywords(sessionId: string, pairId: string): Promise<void> {
    await this.mutateProgress(sessionId, pairId, 'keywordsRevealed');
  }
  async revealReferenceAnswer(sessionId: string, pairId: string): Promise<void> {
    await this.mutateProgress(sessionId, pairId, 'answerRevealed');
  }

  async rateAndAdvance(sessionId: string, pairId: string, rating: DialogueSelfRating): Promise<ScenarioAdvance> {
    return await this.database.transaction(async store => {
      const sessions = await this.sessions('WHERE id=?', [sessionId], store);
      if (sessions.length === 0 || sessions[0].status !== 'IN_PROGRESS') throw new Error('SESSION_NOT_ACTIVE');
      const session = sessions[0];
      if (session.queue[session.currentPairIndex] !== pairId) throw new Error('STALE_SCENARIO_ACTION');
      const progress = await queryRows(store, 'SELECT answerRevealed,selfRating FROM scenario_turn_progress WHERE sessionId=? AND pairId=?',
        mapProgressGate, [sessionId, pairId]);
      if (progress.length === 0 || !progress[0].revealed) throw new Error('ANSWER_NOT_REVEALED');
      if (progress[0].rating !== null) throw new Error('PAIR_ALREADY_RATED');
      const now = Date.now();
      await store.executeSql('UPDATE scenario_turn_progress SET selfRating=?,updatedAtEpochMs=? WHERE sessionId=? AND pairId=?',
        [rating, now, sessionId, pairId]);
      await this.savePairMemory(store, pairId, rating, now);
      let queue = session.queue; const next = session.currentPairIndex + 1;
      const completed = session.practiceMode !== 'RANDOM' && next >= queue.length;
      if (session.practiceMode === 'RANDOM') queue = await this.nextRandomQueue(queue, session.currentPairIndex, pairId, rating);
      await store.executeSql(`UPDATE scenario_sessions SET status=?,currentPairIndex=?,currentPairId=?,
        pairCount=?,queuePairIdsJson=?,completedAtEpochMs=?,updatedAtEpochMs=? WHERE id=?`,
        [completed ? 'COMPLETED' : 'IN_PROGRESS', next, completed ? null : queue[next], queue.length,
          JSON.stringify(queue), completed ? now : null, now, sessionId]);
      if (!completed) {
        await store.executeSql('INSERT OR IGNORE INTO scenario_turn_progress VALUES (?, ?, 0, 0, 0, 0, NULL, ?)',
          [sessionId, queue[next], now]);
      }
      const distribution = await this.ratingDistribution(store, sessionId);
      const advance: ScenarioAdvance = { completed: completed, ratingDistribution: distribution };
      return advance;
    });
  }

  async endRandomSession(sessionId: string): Promise<void> {
    const sessions = await this.sessions('WHERE id=?', [sessionId]);
    if (sessions.length === 0 || sessions[0].practiceMode !== 'RANDOM' || sessions[0].status !== 'IN_PROGRESS') return;
    const now = Date.now();
    await this.database.get().executeSql(`UPDATE scenario_sessions SET status='COMPLETED',completedAtEpochMs=?,updatedAtEpochMs=? WHERE id=?`,
      [now, now, sessionId]);
  }

  private async createSession(scenarioId: string, pairIds: string[], practiceMode: string): Promise<string> {
    const now = Date.now(); const id = `scenario-${now}-${Math.floor(Math.random() * 1_000_000_000)}`;
    let contentHash = 'RANDOM';
    if (scenarioId !== 'RANDOM') {
      const result = await this.database.get().querySql('SELECT contentHash FROM scenarios WHERE id=? AND active=1', [scenarioId]);
      try { if (!result.goToFirstRow()) throw new Error('SCENARIO_NOT_FOUND'); contentHash = result.getString(0); } finally { result.close(); }
    }
    await this.database.get().executeSql('INSERT INTO scenario_sessions VALUES (?, ?, ?, ?, ?, 0, ?, ?, ?, ?, NULL, ?)',
      [id, scenarioId, contentHash, 'IN_PROGRESS', pairIds[0], pairIds.length, practiceMode, JSON.stringify(pairIds), now, now]);
    return id;
  }

  private async pairHasCustomerAudio(pairId: string): Promise<boolean> {
    const rows = await queryRows(this.database.get(),
      `SELECT t.audioAssetId FROM dialogue_pairs p JOIN dialogue_turns t ON t.id=p.customerTurnId WHERE p.id=?`,
      r => nullableString(r, 'audioAssetId'), [pairId]);
    const assetId = rows.length > 0 ? rows[0] : null;
    return assetId !== null && assetId.length > 0;
  }

  private async mutateProgress(sessionId: string, pairId: string, field: string): Promise<void> {    if (!['customerAudioCompleted', 'customerTextRevealed', 'keywordsRevealed', 'answerRevealed'].includes(field)) throw new Error('INVALID_PROGRESS_FIELD');
    await this.database.transaction(async store => {
      const sessions = await this.sessions('WHERE id=?', [sessionId], store);
      if (sessions.length === 0 || sessions[0].queue[sessions[0].currentPairIndex] !== pairId) throw new Error('STALE_SCENARIO_ACTION');
      const now = Date.now();
      await store.executeSql(`INSERT OR IGNORE INTO scenario_turn_progress VALUES (?, ?, 0, 0, 0, 0, NULL, ?)`, [sessionId, pairId, now]);
      await store.executeSql(`UPDATE scenario_turn_progress SET ${field}=1,updatedAtEpochMs=? WHERE sessionId=? AND pairId=?`, [now, sessionId, pairId]);
      await store.executeSql('UPDATE scenario_sessions SET updatedAtEpochMs=? WHERE id=?', [now, sessionId]);
    });
  }

  private async mapKeywords(pairId: string): Promise<ScenarioKeyword[]> {
    return await queryRows(this.database.get(), `SELECT v.id,v.term,v.ipa,v.chineseGloss FROM dialogue_pair_words x
      JOIN vocabulary_entries v ON v.id=x.wordId WHERE x.pairId=? ORDER BY x.sortOrder`,
      mapKeyword, [pairId]);
  }

  private mapUnit(r: relationalStore.ResultSet, session: SessionState): ScenarioUnitView {
    const pairId = stringValue(r, 'id'); const points = JSON.parse(stringValue(r, 'scoringPointsJson')) as ScenarioScoringPoint[];
    const textRevealed = booleanValue(r, 'customerTextRevealed');
    const keywordsRevealed = booleanValue(r, 'keywordsRevealed');
    const answerRevealed = booleanValue(r, 'answerRevealed');
    return { sessionId: session.id, scenarioTitle: stringValue(r, 'scenarioTitle'), pairId: pairId,
      pairIndex: session.currentPairIndex, pairCount: session.pairCount,
      customerTextEn: textRevealed ? stringValue(r, 'customerTextEn') : '',
      customerTextZh: textRevealed ? nullableString(r, 'customerTextZh') : null,
      customerAudioAssetId: nullableString(r, 'customerAudioAssetId'), keywords: [],
      referenceCoreEn: answerRevealed ? stringValue(r, 'referenceCoreEn') : '',
      referenceChineseHint: answerRevealed ? stringValue(r, 'referenceChineseHint') : '',
      formalAlternatives: answerRevealed ? JSON.parse(stringValue(r, 'formalAlternativesJson')) as string[] : [],
      scoringPoints: answerRevealed ? points : [], riskNote: answerRevealed ? nullableString(r, 'riskNote') : null,
      customerAudioCompleted: booleanValue(r, 'customerAudioCompleted'), customerTextRevealed: booleanValue(r, 'customerTextRevealed'),
      keywordsRevealed: keywordsRevealed, answerRevealed: answerRevealed,
      selfRating: nullableString(r, 'selfRating'), practiceMode: session.practiceMode };
  }

  private async savePairMemory(store: relationalStore.RdbStore, pairId: string,
    rating: DialogueSelfRating, now: number): Promise<void> {
    const old = await queryRows(store, `SELECT reps,lapses FROM item_memory_states WHERE itemId=? AND itemType='PAIR'`,
      mapPairMemoryCount, [pairId]);
    const again = rating === DialogueSelfRating.CANNOT_ANSWER;
    const due = now + (again ? 10 * 60 * 1000 : rating === DialogueSelfRating.BASIC ? 86400000 : 4 * 86400000);
    const hashResult = await store.querySql('SELECT contentHash FROM dialogue_pairs WHERE id=?', [pairId]);
    let hash: string | null = null; try { if (hashResult.goToFirstRow()) hash = hashResult.getString(0); } finally { hashResult.close(); }
    await store.executeSql(`INSERT OR REPLACE INTO item_memory_states VALUES (?, 'PAIR', ?, ?, ?, ?, ?, ?, ?, 0, ?, ?)`,
      [pairId, again ? 'RELEARNING' : 'REVIEW', rating === DialogueSelfRating.FLUENT ? 4 : 6,
        rating === DialogueSelfRating.FLUENT ? 4 : 1, due, now, (old[0]?.reps ?? 0) + 1,
        (old[0]?.lapses ?? 0) + (again ? 1 : 0), hash, now]);
  }

  private async nextRandomQueue(original: string[], currentIndex: number, pairId: string,
    rating: DialogueSelfRating): Promise<string[]> {
    const queue = original.slice();
    const gap = rating === DialogueSelfRating.CANNOT_ANSWER ? 2 : rating === DialogueSelfRating.BASIC ? 5 : 0;
    if (gap > 0) {
      const target = currentIndex + gap + 1;
      while (queue.length <= target) queue.push(...await this.ids(`SELECT p.id FROM dialogue_pairs p JOIN scenarios s ON s.id=p.scenarioId WHERE s.active=1 ORDER BY RANDOM()`));
      const existing = queue.indexOf(pairId, currentIndex + 1); if (existing >= 0) queue.splice(existing, 1);
      queue.splice(target, 0, pairId);
    }
    if (currentIndex + 1 >= queue.length) {
      const bag = await this.ids(`SELECT p.id FROM dialogue_pairs p JOIN scenarios s ON s.id=p.scenarioId WHERE s.active=1 ORDER BY RANDOM()`);
      queue.push(...bag.filter((id, index) => index > 0 || id !== pairId));
    }
    return queue;
  }

  private async ratingDistribution(store: relationalStore.RdbStore, sessionId: string): Promise<number[]> {
    const values = [0, 0, 0];
    const result = await store.querySql(`SELECT selfRating,COUNT(*) FROM scenario_turn_progress WHERE sessionId=? AND selfRating IS NOT NULL GROUP BY selfRating`, [sessionId]);
    try {
      if (result.goToFirstRow()) do {
        const rating = result.getString(0); const count = result.getLong(1);
        if (rating === DialogueSelfRating.CANNOT_ANSWER) values[0] = count;
        else if (rating === DialogueSelfRating.BASIC) values[1] = count;
        else if (rating === DialogueSelfRating.FLUENT) values[2] = count;
      } while (result.goToNextRow());
    } finally { result.close(); }
    return values;
  }

  private async sessions(where: string, args: relationalStore.ValueType[] = [],
    store: relationalStore.RdbStore = this.database.get()): Promise<SessionState[]> {
    return await queryRows(store, `SELECT * FROM scenario_sessions ${where}`, mapSession, args);
  }
  private async ids(sql: string, args: relationalStore.ValueType[] = []): Promise<string[]> {
    const result = await this.database.get().querySql(sql, args); const output: string[] = [];
    try { if (result.goToFirstRow()) do { output.push(result.getString(0)); } while (result.goToNextRow()); } finally { result.close(); }
    return output;
  }
}

function mapSummary(r: relationalStore.ResultSet): ScenarioSummary {
  return { id: stringValue(r, 'id'), title: stringValue(r, 'title'), topic: stringValue(r, 'topic'),
    salesStage: stringValue(r, 'salesStage'), customerRole: stringValue(r, 'customerRole'), difficulty: stringValue(r, 'difficulty'),
    projectType: stringValue(r, 'projectType'), estimatedMinutes: integerValue(r, 'estimatedMinutes'),
    description: nullableString(r, 'description'), pairCount: integerValue(r, 'pairCount'),
    status: nullableString(r, 'sessionStatus'), duePairCount: integerValue(r, 'duePairCount') };
}

function mapProgressGate(r: relationalStore.ResultSet): ProgressGate {
  return { revealed: booleanValue(r, 'answerRevealed'), rating: nullableString(r, 'selfRating') };
}

function mapKeyword(r: relationalStore.ResultSet): ScenarioKeyword {
  return { vocabularyId: stringValue(r, 'id'), english: stringValue(r, 'term'), ipa: stringValue(r, 'ipa'),
    chineseGloss: stringValue(r, 'chineseGloss') };
}

function mapPairMemoryCount(r: relationalStore.ResultSet): PairMemoryCount {
  return { reps: integerValue(r, 'reps'), lapses: integerValue(r, 'lapses') };
}

function mapSession(r: relationalStore.ResultSet): SessionState {
  return { id: stringValue(r, 'id'), scenarioId: stringValue(r, 'scenarioId'), status: stringValue(r, 'status'),
    currentPairId: nullableString(r, 'currentPairId'), currentPairIndex: integerValue(r, 'currentPairIndex'),
    pairCount: integerValue(r, 'pairCount'), practiceMode: stringValue(r, 'practiceMode'),
    queue: JSON.parse(stringValue(r, 'queuePairIdsJson')) as string[] };
}
