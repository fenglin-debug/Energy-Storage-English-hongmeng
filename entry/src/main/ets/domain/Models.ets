export enum Rating {
  AGAIN = 'AGAIN',
  HARD = 'HARD',
  GOOD = 'GOOD',
  EASY = 'EASY'
}

export enum FsrsState {
  NEW = 'NEW',
  LEARNING = 'LEARNING',
  REVIEW = 'REVIEW',
  RELEARNING = 'RELEARNING'
}

export enum QuestionMode {
  INTRODUCE = 'INTRODUCE',
  EN2ZH = 'EN2ZH',
  ZH2EN = 'ZH2EN',
  LISTENING = 'LISTENING',
  TRANSFER = 'TRANSFER'
}

export enum VocabularyAssessment {
  UNFAMILIAR = 'UNFAMILIAR',
  FUZZY = 'FUZZY',
  MASTERED = 'MASTERED'
}

export enum DialogueSelfRating {
  CANNOT_ANSWER = 'CANNOT_ANSWER',
  BASIC = 'BASIC',
  FLUENT = 'FLUENT'
}

export interface VocabularyExample {
  id: string;
  textEn: string;
  textZh: string | null;
  audioAssetId: string;
}

export interface Vocabulary {
  id: string;
  term: string;
  normalizedTerm: string;
  ipa: string;
  partOfSpeech: string;
  chineseGloss: string;
  englishDefinition: string | null;
  collocations: string[];
  exampleSentenceEn: string;
  exampleSentenceZh: string | null;
  commonMistakes: string;
  topic: string;
  scenarioTags: string[];
  cefrLevel: string;
  wordAudioAssetId: string;
  exampleAudioAssetId: string;
  contentHash: string;
  favorite: boolean;
  itemKind: string;
  aliases: string[];
  examples: VocabularyExample[];
}

export interface VocabularyQueue {
  newCount: number;
  reviewCount: number;
  totalCount: number;
}

export interface VocabularySessionView {
  sessionId: string;
  status: string;
  currentIndex: number;
  totalCount: number;
  questionMode: QuestionMode;
  word: Vocabulary | null;
  answerRevealed: boolean;
  hintRevealed: boolean;
  assessmentSubmitted: boolean;
  selectedAssessment: string | null;
}

export interface ScenarioSummary {
  id: string;
  title: string;
  topic: string;
  salesStage: string;
  customerRole: string;
  difficulty: string;
  projectType: string;
  estimatedMinutes: number;
  description: string | null;
  pairCount: number;
  status: string | null;
  duePairCount: number;
}

export interface ScenarioKeyword {
  vocabularyId: string;
  english: string;
  ipa: string;
  chineseGloss: string;
}

export interface ScenarioScoringPoint {
  id: string;
  type: string;
  descriptionZh: string;
  keywordsEn: string;
  required: boolean;
  weight: number;
}

export interface ScenarioAdvance {
  completed: boolean;
  ratingDistribution: number[];
}

export interface ScenarioUnitView {
  sessionId: string;
  scenarioTitle: string;
  pairId: string;
  pairIndex: number;
  pairCount: number;
  customerTextEn: string;
  customerTextZh: string | null;
  customerAudioAssetId: string | null;
  keywords: ScenarioKeyword[];
  referenceCoreEn: string;
  referenceChineseHint: string;
  formalAlternatives: string[];
  scoringPoints: ScenarioScoringPoint[];
  riskNote: string | null;
  customerAudioCompleted: boolean;
  customerTextRevealed: boolean;
  keywordsRevealed: boolean;
  answerRevealed: boolean;
  selfRating: string | null;
  practiceMode: string;
}

export interface ArticleParagraph {
  textEn: string;
  textZh: string;
  startMs: number | null;
  endMs: number | null;
}

export interface Article {
  id: string;
  title: string;
  titleZh: string;
  topic: string;
  paragraphs: ArticleParagraph[];
  audioAssetId: string;
  durationMs: number;
  source: string;
  contentScope: string;
  contentHash: string;
  lastPositionMs: number;
  includeInRandomPractice: boolean;
}

export interface AppSettings {
  playbackSpeed: number;
  dailyNewWordTarget: number;
  autoPlayCustomerAudio: boolean;
  autoPlayVocabularyAudio: boolean;
  dailyReminderEnabled: boolean;
  dailyReminderHour: number;
  dailyReminderMinute: number;
  lastBackupAtEpochMs: number | null;
}

export const DEFAULT_SETTINGS: AppSettings = {
  playbackSpeed: 1.0,
  dailyNewWordTarget: 15,
  autoPlayCustomerAudio: true,
  autoPlayVocabularyAudio: true,
  dailyReminderEnabled: false,
  dailyReminderHour: 20,
  dailyReminderMinute: 0,
  lastBackupAtEpochMs: null
};

export interface PlaybackSnapshot {
  assetId: string | null;
  state: string;
  positionMs: number;
  durationMs: number;
  speed: number;
  errorCode: string | null;
}

export class DocumentRef {
  readonly uri: string;

  constructor(uri: string) {
    if (uri.trim().length === 0) {
      throw new Error('DocumentRef uri must not be blank');
    }
    this.uri = uri;
  }
}

export interface LearningBackupCounts {
  wordMemoryStates: number;
  reviewLogs: number;
  vocabularyCheckpoints: number;
  reviewActionKeys: number;
  scenarioSessions: number;
  scenarioTurnProgress: number;
  studyTasks: number;
  itemMemoryStates: number;
  articleProgress: number;
}

export interface LearningBackupInspection {
  previewId: string;
  createdAtEpochMs: number;
  appVersionName: string;
  appVersionCode: number;
  databaseVersion: number;
  corpusPackageKey: string | null;
  corpusContentVersion: string | null;
  corpusMatches: boolean;
  encrypted: boolean;
  counts: LearningBackupCounts;
}

export interface OperationResult {
  ok: boolean;
  errorCode: string | null;
  message: string;
}

export interface CorpusPreview {
  previewId: string;
  packageId: string;
  contentVersion: string;
  vocabularyCount: number;
  phraseCount: number;
  exampleCount: number;
  scenarioCount: number;
  audioCount: number;
  addedCount: number;
  updatedCount: number;
  removedCount: number;
  unchangedCount: number;
}

export interface AppSupportInfo {
  appVersionName: string;
  appVersionCode: number;
  databaseVersion: number;
  corpusPackageKey: string | null;
  corpusContentVersion: string | null;
  recordCounts: LearningBackupCounts;
  lastBackupAtEpochMs: number | null;
  lastErrorCode: string | null;
  systemVersion: string;
  architecture: string;
  signingFingerprint: string;
}

export interface WordMemoryStateRow {
  wordId: string;
  fsrsState: string;
  difficulty: number;
  stability: number;
  dueAtEpochMs: number;
  lastReviewAtEpochMs: number | null;
  reps: number;
  lapses: number;
  masteredUi: boolean;
  lastQuestionMode: string | null;
  isFavorite: boolean;
  learnedContentHash: string | null;
  legacyNormalizedTerm: string | null;
  updatedAtEpochMs: number;
}

export interface ReviewLogRow {
  id: string;
  wordId: string;
  rating: string;
  questionMode: string;
  usedHint: boolean;
  revealedAnswer: boolean;
  reviewedAtEpochMs: number;
  responseTimeMs: number | null;
  scheduledDays: number;
  elapsedDays: number;
  stateBefore: string;
  stateAfter: string;
}

export interface VocabularyCheckpointRow {
  sessionId: string;
  status: string;
  corpusVersion: string;
  queueWordIdsJson: string;
  currentIndex: number;
  questionMode: string;
  answerRevealed: boolean;
  hintRevealed: boolean;
  assessmentSubmitted: boolean;
  selectedAssessment: string | null;
  startedAtEpochMs: number;
  updatedAtEpochMs: number;
}

export interface ReviewActionKeyRow {
  actionKey: string;
  sessionId: string;
  currentIndex: number;
  createdAtEpochMs: number;
}

export interface ScenarioSessionRow {
  id: string;
  scenarioId: string;
  scenarioContentHash: string;
  status: string;
  currentPairId: string | null;
  currentPairIndex: number;
  pairCount: number;
  practiceMode: string;
  queuePairIdsJson: string;
  startedAtEpochMs: number;
  completedAtEpochMs: number | null;
  updatedAtEpochMs: number;
}

export interface ScenarioTurnProgressRow {
  sessionId: string;
  pairId: string;
  customerAudioCompleted: boolean;
  customerTextRevealed: boolean;
  keywordsRevealed: boolean;
  answerRevealed: boolean;
  selfRating: string | null;
  updatedAtEpochMs: number;
}

export interface StudyTaskRow {
  dateEpochDay: number;
  newWordTarget: number;
  newWordDone: number;
  reviewTarget: number;
  reviewDone: number;
  recommendedScenarioId: string | null;
  studySeconds: number;
  completed: boolean;
  updatedAtEpochMs: number;
}

export interface ItemMemoryStateRow {
  itemId: string;
  itemType: string;
  fsrsState: string;
  difficulty: number;
  stability: number;
  dueAtEpochMs: number;
  lastReviewAtEpochMs: number | null;
  reps: number;
  lapses: number;
  masteredUi: boolean;
  learnedContentHash: string | null;
  updatedAtEpochMs: number;
}

export interface ArticleProgressRow {
  articleId: string;
  lastPositionMs: number;
  listenCount: number;
  completedAtEpochMs: number | null;
  updatedAtEpochMs: number;
}

export interface LearningBackupPayload {
  wordMemoryStates: WordMemoryStateRow[];
  reviewLogs: ReviewLogRow[];
  vocabularyCheckpoints: VocabularyCheckpointRow[];
  reviewActionKeys: ReviewActionKeyRow[];
  scenarioSessions: ScenarioSessionRow[];
  scenarioTurnProgress: ScenarioTurnProgressRow[];
  studyTasks: StudyTaskRow[];
  itemMemoryStates: ItemMemoryStateRow[];
  articleProgress: ArticleProgressRow[];
}
