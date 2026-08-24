import { relationalStore } from '@kit.ArkData';
import {
  FsrsState, MasteryFilter, QuestionMode, Rating, Vocabulary, VocabularyAssessment,
  VocabularyExample, VocabularyFilter, VocabularyQueue, VocabularySessionView, WordMemoryState
} from '../domain/Models';
import { VocabularyRepository } from '../domain/Repositories';
import { FsrsCard, FsrsScheduler } from '../domain/Fsrs';
import { DatabaseService } from './DatabaseService';
import { SettingsRepositoryImpl } from './SettingsRepositoryImpl';
import { booleanValue, integerValue, nullableInteger, nullableNumber, nullableString, numberValue, queryRows, stringValue } from './RdbHelpers';

interface MemoryRow {
  wordId: string; state: string; difficulty: number; stability: number; due: number;
  lastReview: number | null; reps: number; lapses: number; mastered: boolean; favorite: boolean;
}

interface CheckpointRow {
  sessionId: string; status: string; corpusVersion: string; queue: string[]; index: number;
  mode: QuestionMode; answer: boolean; hint: boolean; assessed: boolean; assessment: string | null;
  started: number; updated: number;
}

export class VocabularyRepositoryImpl implements VocabularyRepository {
  private readonly scheduler = new FsrsScheduler();
  private readonly database: DatabaseService;
  private readonly settings: SettingsRepositoryImpl;
  constructor(database: DatabaseService, settings: SettingsRepositoryImpl) {
    this.database = database; this.settings = settings;
  }

  async list(filter: VocabularyFilter): Promise<Vocabulary[]> {
    await this.repairInfiniteDue();
    const query = filter.query.trim();
    const escaped = `%${query.toLowerCase().replace(new RegExp('[%_]', 'g'), '\\$&')}%`;
    const now = Date.now();
    return await queryRows(this.database.get(),
      `SELECT v.*, m.fsrsState,m.difficulty,m.stability,m.dueAtEpochMs,m.reps,m.lapses,m.masteredUi,
       m.lastQuestionMode,m.isFavorite,COALESCE(m.isFavorite,0) favorite,m.wordId memoryWordId
       FROM vocabulary_entries v
       LEFT JOIN word_memory_states m ON m.wordId=v.id WHERE v.active=1
       AND (?='' OR lower(v.term) LIKE ? ESCAPE '\\' OR lower(v.chineseGloss) LIKE ? ESCAPE '\\'
         OR lower(COALESCE(v.englishDefinition,'')) LIKE ? ESCAPE '\\'
         OR EXISTS(SELECT 1 FROM vocabulary_aliases a WHERE a.wordId=v.id AND lower(a.alias) LIKE ? ESCAPE '\\'))
       AND (?='' OR v.topic=?) AND (?='' OR v.cefrLevel=?)
       AND (?=0 OR COALESCE(m.isFavorite,0)=1)
       AND (?=0 OR (m.reps>0 AND m.dueAtEpochMs<=?))
       AND (?='ALL' OR (?='NOT_STARTED' AND (m.wordId IS NULL OR m.reps=0))
         OR (?='LEARNING' AND m.reps>0 AND m.masteredUi=0)
         OR (?='MASTERED' AND m.masteredUi=1))
       ORDER BY v.id`, mapVocabulary,
      [query, escaped, escaped, escaped, escaped, filter.topic, filter.topic, filter.cefrLevel, filter.cefrLevel,
        filter.favoritesOnly ? 1 : 0, filter.dueOnly ? 1 : 0, now,
        filter.mastery, filter.mastery, filter.mastery, filter.mastery]);
  }

  async get(wordId: string): Promise<Vocabulary | null> { return await this.word(wordId); }

  async todayQueue(): Promise<VocabularyQueue> {
    await this.repairInfiniteDue();
    const target = (await this.settings.get()).dailyNewWordTarget; const now = Date.now();
    const due = await this.count(`SELECT COUNT(*) FROM word_memory_states m JOIN vocabulary_entries v ON v.id=m.wordId
      WHERE v.active=1 AND m.reps>0 AND m.dueAtEpochMs<=?`, [now]);
    const fresh = await this.count(`SELECT COUNT(*) FROM vocabulary_entries v LEFT JOIN word_memory_states m ON m.wordId=v.id
      WHERE v.active=1 AND (m.wordId IS NULL OR (m.reps=0 AND m.masteredUi=0))`);
    const duePhrases = await this.count(`SELECT COUNT(*) FROM item_memory_states m JOIN phrases p ON p.id=m.itemId
      WHERE p.active=1 AND m.itemType='PHRASE' AND m.reps>0 AND m.dueAtEpochMs<=?`, [now]);
    const freshPhrases = await this.count(`SELECT COUNT(*) FROM phrases p LEFT JOIN item_memory_states m
      ON m.itemId=p.id AND m.itemType='PHRASE' WHERE p.active=1 AND m.itemId IS NULL`);
    const newCount = Math.min(target, fresh + freshPhrases);
    return { newCount: newCount, reviewCount: due + duePhrases, totalCount: newCount + due + duePhrases };
  }

  async startOrResumeSession(): Promise<string> {
    const existing = await this.checkpointQuery("WHERE status='IN_PROGRESS' ORDER BY updatedAtEpochMs DESC LIMIT 1");
    if (existing.length > 0) return existing[0].sessionId;
    await this.repairInfiniteDue();
    const now = Date.now(); const target = (await this.settings.get()).dailyNewWordTarget;
    const due = await this.ids(`SELECT v.id FROM vocabulary_entries v JOIN word_memory_states m ON m.wordId=v.id
      WHERE v.active=1 AND m.reps>0 AND m.dueAtEpochMs<=? ORDER BY m.dueAtEpochMs,v.id`, [now]);
    const duePhrases = await this.ids(`SELECT p.id FROM phrases p JOIN item_memory_states m ON m.itemId=p.id AND m.itemType='PHRASE'
      WHERE p.active=1 AND m.reps>0 AND m.dueAtEpochMs<=? ORDER BY m.dueAtEpochMs,p.id`, [now]);
    const freshWords = await this.ids(`SELECT v.id FROM vocabulary_entries v LEFT JOIN word_memory_states m ON m.wordId=v.id
      WHERE v.active=1 AND (m.wordId IS NULL OR (m.reps=0 AND m.masteredUi=0)) ORDER BY v.id`);
    const freshPhrases = await this.ids(`SELECT p.id FROM phrases p LEFT JOIN item_memory_states m
      ON m.itemId=p.id AND m.itemType='PHRASE' WHERE p.active=1 AND m.itemId IS NULL ORDER BY p.id`);
    const fresh = freshWords.concat(freshPhrases).sort().slice(0, target);
    const queue = due.concat(duePhrases).concat(fresh.filter(id => !due.includes(id) && !duePhrases.includes(id)));
    if (queue.length === 0) throw new Error('NO_VOCABULARY_DUE');
    const firstMemory = await this.memory(queue[0]); const sessionId = this.id('vocab');
    const corpusVersion = await this.database.metadata('active_corpus_content_version') ?? 'none';
    const firstMode = this.modeFor(firstMemory);
    await this.database.get().executeSql('INSERT INTO vocabulary_session_checkpoints VALUES (?, ?, ?, ?, ?, ?, ?, 0, 0, NULL, ?, ?)',
      [sessionId, 'IN_PROGRESS', corpusVersion, JSON.stringify(queue), 0, firstMode,
        firstMode === QuestionMode.INTRODUCE ? 1 : 0, now, now]);
    return sessionId;
  }

  async session(sessionId: string): Promise<VocabularySessionView> {
    const checkpoints = await this.checkpointQuery('WHERE sessionId=?', [sessionId]);
    if (checkpoints.length === 0) throw new Error('SESSION_NOT_FOUND');
    const checkpoint = checkpoints[0]; const wordId = checkpoint.queue[checkpoint.index];
    return { sessionId: checkpoint.sessionId, status: checkpoint.status, currentIndex: checkpoint.index,
      totalCount: checkpoint.queue.length, questionMode: checkpoint.mode,
      word: wordId === undefined ? null : await this.word(wordId), answerRevealed: checkpoint.answer,
      hintRevealed: checkpoint.hint, assessmentSubmitted: checkpoint.assessed,
      selectedAssessment: checkpoint.assessment };
  }

  async revealAnswer(sessionId: string): Promise<void> {
    await this.database.get().executeSql(`UPDATE vocabulary_session_checkpoints SET answerRevealed=1,updatedAtEpochMs=?
      WHERE sessionId=? AND status='IN_PROGRESS'`, [Date.now(), sessionId]);
  }

  async revealHint(sessionId: string): Promise<void> {
    await this.database.get().executeSql(`UPDATE vocabulary_session_checkpoints SET hintRevealed=1,updatedAtEpochMs=?
      WHERE sessionId=? AND status='IN_PROGRESS'`, [Date.now(), sessionId]);
  }

  async submitAssessment(sessionId: string, assessment: VocabularyAssessment): Promise<void> {
    await this.database.transaction(async store => {
      const checkpoints = await this.checkpointQuery('WHERE sessionId=?', [sessionId], store);
      if (checkpoints.length === 0 || checkpoints[0].status !== 'IN_PROGRESS') throw new Error('SESSION_NOT_ACTIVE');
      const cp = checkpoints[0];
      if (cp.mode !== QuestionMode.INTRODUCE && !cp.answer) throw new Error('ANSWER_NOT_REVEALED');
      await store.executeSql(`UPDATE vocabulary_session_checkpoints SET answerRevealed=1,
        assessmentSubmitted=1,selectedAssessment=?,updatedAtEpochMs=? WHERE sessionId=?`,
        [assessment, Date.now(), sessionId]);
    });
  }

  async advanceToNext(sessionId: string): Promise<void> {
    await this.database.transaction(async store => {
      const checkpoints = await this.checkpointQuery('WHERE sessionId=?', [sessionId], store);
      if (checkpoints.length === 0 || checkpoints[0].status !== 'IN_PROGRESS') throw new Error('SESSION_NOT_ACTIVE');
      const cp = checkpoints[0];
      if (!cp.assessed) throw new Error('ASSESSMENT_REQUIRED');
      const wordId = cp.queue[cp.index];
      if (wordId === undefined || cp.assessment === null) throw new Error('STALE_SESSION');
      const key = `${sessionId}:${cp.index}`;
      if (!await this.exists(store, 'SELECT 1 FROM review_action_keys WHERE actionKey=?', [key])) {
        await store.executeSql('INSERT INTO review_action_keys VALUES (?, ?, ?, ?)', [key, sessionId, cp.index, Date.now()]);
        await this.persistAssessment(store, wordId, cp.mode, cp.hint, cp.assessment as VocabularyAssessment);
      }
      const nextIndex = cp.index + 1; const completed = nextIndex >= cp.queue.length;
      const nextMemory = completed ? null : await this.memory(cp.queue[nextIndex], store);
      const nextMode = completed ? cp.mode : this.modeFor(nextMemory);
      await store.executeSql(`UPDATE vocabulary_session_checkpoints SET status=?,currentIndex=?,questionMode=?,
        answerRevealed=?,hintRevealed=0,assessmentSubmitted=0,selectedAssessment=NULL,updatedAtEpochMs=? WHERE sessionId=?`,
        [completed ? 'COMPLETED' : 'IN_PROGRESS', nextIndex, nextMode,
          !completed && nextMode === QuestionMode.INTRODUCE ? 1 : 0, Date.now(), sessionId]);
    });
  }

  async setFavorite(wordId: string, favorite: boolean): Promise<void> {
    if (this.isPhrase(wordId)) throw new Error('PHRASES_CANNOT_BE_FAVORITED');
    const now = Date.now(); const contentHash = await this.contentHash(wordId);
    await this.database.get().executeSql(`INSERT INTO word_memory_states VALUES (?, 'NEW', 0, 0, ?, NULL, 0, 0, 0, NULL, ?, ?, NULL, ?)
      ON CONFLICT(wordId) DO UPDATE SET isFavorite=excluded.isFavorite,updatedAtEpochMs=excluded.updatedAtEpochMs`,
      [wordId, Number.MAX_SAFE_INTEGER, favorite ? 1 : 0, contentHash, now]);
  }

  questionPrompt(mode: QuestionMode, word: Vocabulary): string {
    if (mode === QuestionMode.ZH2EN) return word.chineseGloss;
    if (mode === QuestionMode.LISTENING) return '听音频，说出词义与用法';
    if (mode === QuestionMode.TRANSFER) return word.term;
    if (mode === QuestionMode.EN2ZH) return word.term;
    return `${word.term}  ${word.ipa}`;
  }

  private async persistAssessment(store: relationalStore.RdbStore, wordId: string, mode: QuestionMode,
    usedHint: boolean, assessment: VocabularyAssessment): Promise<void> {
    const rating = assessment === VocabularyAssessment.UNFAMILIAR ? Rating.AGAIN :
      assessment === VocabularyAssessment.FUZZY ? Rating.HARD : Rating.GOOD;
    const now = Date.now(); const old = await this.memory(wordId, store);
    const stateBefore = old === null || old.state === 'NEW' ? FsrsState.NEW : old.state as FsrsState;
    const card: FsrsCard = old === null || old.state === 'NEW' ?
      { state: FsrsState.NEW, step: null, stability: null, difficulty: null, dueAtEpochMs: now, lastReviewAtEpochMs: null } :
      { state: old.state as FsrsState,
        step: old.state === FsrsState.LEARNING || old.state === FsrsState.RELEARNING ? 0 : null,
        stability: old.stability, difficulty: old.difficulty, dueAtEpochMs: old.due, lastReviewAtEpochMs: old.lastReview };
    const reviewed = this.scheduler.review(card, rating, now);
    const mastered = assessment === VocabularyAssessment.MASTERED;
    const due = reviewed.dueAtEpochMs;
    const reps = (old?.reps ?? 0) + 1;
    const lapses = (old?.lapses ?? 0) + (rating === Rating.AGAIN ? 1 : 0);
    await store.executeSql(`INSERT OR REPLACE INTO review_logs VALUES (?, ?, ?, ?, ?, 1, ?, NULL, ?, ?, ?, ?)`,
      [this.id('review'), wordId, rating, mode, usedHint ? 1 : 0, now,
        Math.max(0, Math.floor((due - now) / 86400000)),
        old?.lastReview === null || old?.lastReview === undefined ? 0 :
          Math.max(0, Math.floor((now - old.lastReview) / 86400000)), stateBefore, reviewed.state]);
    if (this.isPhrase(wordId)) {
      await store.executeSql(`INSERT OR REPLACE INTO item_memory_states VALUES (?, 'PHRASE', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [wordId, reviewed.state, reviewed.difficulty ?? 0, reviewed.stability ?? 0, due, now, reps, lapses,
          mastered ? 1 : 0, await this.contentHash(wordId, store), now]);
    } else {
      await store.executeSql(`INSERT OR REPLACE INTO word_memory_states VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?)`,
        [wordId, reviewed.state, reviewed.difficulty ?? 0, reviewed.stability ?? 0, due, now, reps, lapses,
          mastered ? 1 : 0, mode, old?.favorite ? 1 : 0, await this.contentHash(wordId, store), now]);
    }
    await this.incrementDaily(store, old === null || old.reps === 0, now);
  }

  private async incrementDaily(store: relationalStore.RdbStore, isNew: boolean, now: number): Promise<void> {
    const date = new Date(now); const epochDay = Math.floor(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()) / 86400000);
    const target = (await this.settings.get()).dailyNewWordTarget;
    await store.executeSql(`INSERT INTO study_tasks VALUES (?, ?, ?, 0, ?, NULL, 0, 0, ?)
      ON CONFLICT(dateEpochDay) DO UPDATE SET newWordDone=study_tasks.newWordDone+?,
      reviewDone=study_tasks.reviewDone+?,updatedAtEpochMs=?`,
      [epochDay, target, isNew ? 1 : 0, isNew ? 0 : 1, now, isNew ? 1 : 0, isNew ? 0 : 1, now]);
  }

  private modeFor(memory: MemoryRow | null): QuestionMode {
    if (memory === null || memory.state === FsrsState.NEW) return QuestionMode.INTRODUCE;
    if (memory.state === FsrsState.LEARNING || memory.state === FsrsState.RELEARNING) return memory.reps % 2 === 0 ? QuestionMode.EN2ZH : QuestionMode.ZH2EN;
    return memory.reps % 2 === 0 ? QuestionMode.LISTENING : QuestionMode.EN2ZH;
  }

  private async word(id: string): Promise<Vocabulary | null> {
    if (this.isPhrase(id)) {
      const phrases = await queryRows(this.database.get(), 'SELECT * FROM phrases WHERE id=? AND active=1', mapPhrase, [id]);
      return phrases.length === 0 ? null : phrases[0];
    }
    const rows = await queryRows(this.database.get(), `SELECT v.*,m.fsrsState,m.difficulty,m.stability,m.dueAtEpochMs,
      m.reps,m.lapses,m.masteredUi,m.lastQuestionMode,m.isFavorite,COALESCE(m.isFavorite,0) favorite,m.wordId memoryWordId
      FROM vocabulary_entries v
      LEFT JOIN word_memory_states m ON m.wordId=v.id WHERE v.id=? AND v.active=1`, mapVocabulary, [id]);
    if (rows.length === 0) return null;
    const word = rows[0];
    word.examples = await this.examplesFor(word);
    word.aliases = await this.aliasesFor(word.id);
    return word;
  }

  private async examplesFor(word: Vocabulary): Promise<VocabularyExample[]> {
    const output: VocabularyExample[] = [{ id: `${word.id}:primary`, textEn: word.exampleSentenceEn,
      textZh: word.exampleSentenceZh, audioAssetId: word.exampleAudioAssetId }];
    const rows = await queryRows(this.database.get(), 'SELECT * FROM examples WHERE active=1 ORDER BY id', mapExample);
    rows.forEach(example => {
      if (example.linkedTermIds.includes(word.id) && !output.some(item => item.textEn === example.textEn)) {
        output.push({ id: example.id, textEn: example.textEn, textZh: example.textZh, audioAssetId: example.audioAssetId });
      }
    });
    return output;
  }

  private async aliasesFor(wordId: string): Promise<string[]> {
    const result = await this.database.get().querySql('SELECT alias FROM vocabulary_aliases WHERE wordId=? ORDER BY alias', [wordId]);
    const output: string[] = [];
    try { if (result.goToFirstRow()) do { output.push(result.getString(0)); } while (result.goToNextRow()); } finally { result.close(); }
    return output;
  }

  private async memory(id: string, store: relationalStore.RdbStore = this.database.get()): Promise<MemoryRow | null> {
    const rows = this.isPhrase(id) ?
      await queryRows(store, `SELECT itemId wordId,fsrsState,difficulty,stability,dueAtEpochMs,lastReviewAtEpochMs,
        reps,lapses,masteredUi,0 isFavorite FROM item_memory_states WHERE itemId=? AND itemType='PHRASE'`, mapMemory, [id]) :
      await queryRows(store, 'SELECT * FROM word_memory_states WHERE wordId=?', mapMemory, [id]);
    return rows.length === 0 ? null : rows[0];
  }

  private async checkpointQuery(where: string, args: relationalStore.ValueType[] = [],
    store: relationalStore.RdbStore = this.database.get()): Promise<CheckpointRow[]> {
    return await queryRows(store, `SELECT * FROM vocabulary_session_checkpoints ${where}`, mapCheckpoint, args);
  }

  private async ids(sql: string, args: relationalStore.ValueType[] = []): Promise<string[]> {
    const result = await this.database.get().querySql(sql, args); const output: string[] = [];
    try { if (result.goToFirstRow()) do { output.push(result.getString(0)); } while (result.goToNextRow()); } finally { result.close(); }
    return output;
  }

  private async count(sql: string, args: relationalStore.ValueType[] = []): Promise<number> {
    const result = await this.database.get().querySql(sql, args); try { return result.goToFirstRow() ? result.getLong(0) : 0; } finally { result.close(); }
  }

  private async repairInfiniteDue(): Promise<void> {
    if (await this.database.metadata('infinite_due_repair_0_4_1') === 'done') return;
    const now = Date.now();
    await this.database.transaction(async store => {
      await store.executeSql(`UPDATE word_memory_states SET dueAtEpochMs=?,updatedAtEpochMs=?
        WHERE reps>0 AND dueAtEpochMs>=?`, [now, now, Number.MAX_SAFE_INTEGER]);
      await store.executeSql(`UPDATE item_memory_states SET dueAtEpochMs=?,updatedAtEpochMs=?
        WHERE reps>0 AND dueAtEpochMs>=?`, [now, now, Number.MAX_SAFE_INTEGER]);
    });
    await this.database.putMetadata('infinite_due_repair_0_4_1', 'done');
  }

  private async exists(store: relationalStore.RdbStore, sql: string, args: relationalStore.ValueType[]): Promise<boolean> {
    const result = await store.querySql(sql, args); try { return result.goToFirstRow(); } finally { result.close(); }
  }

  private async contentHash(wordId: string, store: relationalStore.RdbStore = this.database.get()): Promise<string | null> {
    const table = this.isPhrase(wordId) ? 'phrases' : 'vocabulary_entries';
    const result = await store.querySql(`SELECT contentHash FROM ${table} WHERE id=?`, [wordId]);
    try { return result.goToFirstRow() ? result.getString(0) : null; } finally { result.close(); }
  }

  private id(prefix: string): string { return `${prefix}-${Date.now()}-${Math.floor(Math.random() * 1_000_000_000)}`; }
  private isPhrase(id: string): boolean { return id.startsWith('PHR-'); }
}

function mapVocabulary(r: relationalStore.ResultSet): Vocabulary {
  const memoryWordId = nullableString(r, 'memoryWordId');
  const memoryState: WordMemoryState | null = memoryWordId === null ? null : {
    fsrsState: stringValue(r, 'fsrsState') as FsrsState,
    difficulty: numberValue(r, 'difficulty'), stability: numberValue(r, 'stability'),
    dueAtEpochMs: integerValue(r, 'dueAtEpochMs'), reps: integerValue(r, 'reps'), lapses: integerValue(r, 'lapses'),
    masteredUi: booleanValue(r, 'masteredUi'),
    lastQuestionMode: nullableString(r, 'lastQuestionMode') as QuestionMode | null,
    isFavorite: booleanValue(r, 'isFavorite')
  };
  return { id: stringValue(r, 'id'), term: stringValue(r, 'term'), normalizedTerm: stringValue(r, 'normalizedTerm'),
    ipa: stringValue(r, 'ipa'), partOfSpeech: stringValue(r, 'partOfSpeech'), chineseGloss: stringValue(r, 'chineseGloss'),
    englishDefinition: nullableString(r, 'englishDefinition'), collocations: JSON.parse(stringValue(r, 'collocationsJson')) as string[],
    exampleSentenceEn: stringValue(r, 'exampleSentenceEn'), exampleSentenceZh: nullableString(r, 'exampleSentenceZh'),
    commonMistakes: stringValue(r, 'commonMistakes'), topic: stringValue(r, 'topic'),
    scenarioTags: JSON.parse(stringValue(r, 'scenarioTagsJson')) as string[], cefrLevel: stringValue(r, 'cefrLevel'),
    wordAudioAssetId: stringValue(r, 'wordAudioAssetId'), exampleAudioAssetId: stringValue(r, 'exampleAudioAssetId'),
    contentHash: stringValue(r, 'contentHash'), favorite: booleanValue(r, 'favorite'), memoryState: memoryState,
    itemKind: 'WORD', aliases: [],
    examples: [{ id: `${stringValue(r, 'id')}:primary`, textEn: stringValue(r, 'exampleSentenceEn'),
      textZh: nullableString(r, 'exampleSentenceZh'), audioAssetId: stringValue(r, 'exampleAudioAssetId') }] };
}

function mapMemory(r: relationalStore.ResultSet): MemoryRow {
  return { wordId: stringValue(r, 'wordId'), state: stringValue(r, 'fsrsState'), difficulty: numberValue(r, 'difficulty'),
    stability: numberValue(r, 'stability'), due: integerValue(r, 'dueAtEpochMs'), lastReview: nullableInteger(r, 'lastReviewAtEpochMs'),
    reps: integerValue(r, 'reps'), lapses: integerValue(r, 'lapses'), mastered: booleanValue(r, 'masteredUi'),
    favorite: booleanValue(r, 'isFavorite') };
}

function mapPhrase(r: relationalStore.ResultSet): Vocabulary {
  const textEn = stringValue(r, 'textEn'); const textZh = stringValue(r, 'textZh'); const audio = stringValue(r, 'audioAssetId');
  return { id: stringValue(r, 'id'), term: textEn, normalizedTerm: textEn.trim().toLowerCase(), ipa: '',
    partOfSpeech: 'phrase', chineseGloss: textZh, englishDefinition: null, collocations: [],
    exampleSentenceEn: textEn, exampleSentenceZh: textZh, commonMistakes: '', topic: stringValue(r, 'scene'),
    scenarioTags: [stringValue(r, 'category')], cefrLevel: '', wordAudioAssetId: audio,
    exampleAudioAssetId: audio, contentHash: stringValue(r, 'contentHash'), favorite: false, memoryState: null,
    itemKind: 'PHRASE', aliases: [],
    examples: [{ id: `${stringValue(r, 'id')}:primary`, textEn: textEn, textZh: textZh, audioAssetId: audio }] };
}

interface ExampleMapRow extends VocabularyExample { linkedTermIds: string[]; }

function mapExample(r: relationalStore.ResultSet): ExampleMapRow {
  return { id: stringValue(r, 'id'), textEn: stringValue(r, 'textEn'), textZh: nullableString(r, 'textZh'),
    audioAssetId: stringValue(r, 'audioAssetId'), linkedTermIds: JSON.parse(stringValue(r, 'linkedTermIdsJson')) as string[] };
}

function mapCheckpoint(r: relationalStore.ResultSet): CheckpointRow {
  return { sessionId: stringValue(r, 'sessionId'), status: stringValue(r, 'status'), corpusVersion: stringValue(r, 'corpusVersion'),
    queue: JSON.parse(stringValue(r, 'queueWordIdsJson')) as string[], index: integerValue(r, 'currentIndex'),
    mode: stringValue(r, 'questionMode') as QuestionMode, answer: booleanValue(r, 'answerRevealed'),
    hint: booleanValue(r, 'hintRevealed'), assessed: booleanValue(r, 'assessmentSubmitted'),
    assessment: nullableString(r, 'selectedAssessment'), started: integerValue(r, 'startedAtEpochMs'), updated: integerValue(r, 'updatedAtEpochMs') };
}
