import {
  AppSettings,
  AppSupportInfo,
  Article,
  DialogueSelfRating,
  DocumentRef,
  LearningBackupInspection,
  OperationResult,
  CorpusPreview,
  PlaybackSnapshot,
  QuestionMode,
  Rating,
  ScenarioAdvance,
  ScenarioSummary,
  ScenarioUnitView,
  Vocabulary,
  VocabularyAssessment,
  VocabularyQueue,
  VocabularySessionView
} from './Models';

export type Unsubscribe = () => void;

export interface VocabularyRepository {
  list(query: string, favoritesOnly: boolean): Promise<Vocabulary[]>;
  todayQueue(): Promise<VocabularyQueue>;
  startOrResumeSession(): Promise<string>;
  session(sessionId: string): Promise<VocabularySessionView>;
  revealAnswer(sessionId: string): Promise<void>;
  revealHint(sessionId: string): Promise<void>;
  submitAssessment(sessionId: string, assessment: VocabularyAssessment): Promise<void>;
  advanceToNext(sessionId: string): Promise<void>;
  submitRating(sessionId: string, rating: Rating): Promise<void>;
  setFavorite(wordId: string, favorite: boolean): Promise<void>;
  questionPrompt(mode: QuestionMode, word: Vocabulary): string;
}

export interface ScenarioRepository {
  list(query: string, onlyIncomplete?: boolean, difficulty?: string): Promise<ScenarioSummary[]>;
  startOrResume(scenarioId: string): Promise<string>;
  startOrResumeRandom(): Promise<string>;
  currentUnit(sessionId: string): Promise<ScenarioUnitView | null>;
  markCustomerAudioCompleted(sessionId: string, pairId: string): Promise<void>;
  revealCustomerText(sessionId: string, pairId: string): Promise<void>;
  revealKeywords(sessionId: string, pairId: string): Promise<void>;
  revealReferenceAnswer(sessionId: string, pairId: string): Promise<void>;
  rateAndAdvance(sessionId: string, pairId: string, rating: DialogueSelfRating): Promise<ScenarioAdvance>;
  endRandomSession(sessionId: string): Promise<void>;
}

export interface ArticleRepository {
  list(): Promise<Article[]>;
  get(articleId: string): Promise<Article | null>;
  randomId(): Promise<string | null>;
  randomIds(): Promise<string[]>;
  saveProgress(articleId: string, positionMs: number, completed: boolean): Promise<void>;
  importPackage(source: DocumentRef): Promise<OperationResult>;
  importAudio(audio: DocumentRef, subtitle: DocumentRef | null, audioDisplayName: string,
    subtitleDisplayName: string, title: string, topic: string, includeInRandomPractice: boolean): Promise<OperationResult>;
  deleteImported(articleId: string): Promise<OperationResult>;
}

export interface CorpusRepository {
  activeVersion(): Promise<string | null>;
  inspectPackage(source: DocumentRef): Promise<CorpusPreview>;
  activatePreview(previewId: string): Promise<OperationResult>;
  discardPreview(previewId: string): Promise<void>;
  importPackage(source: DocumentRef): Promise<OperationResult>;
  restoreBundled(): Promise<OperationResult>;
  ensureBundledActivated(): Promise<void>;
}

export interface AudioPlaybackRepository {
  snapshot(): PlaybackSnapshot;
  play(assetId: string, speed: number): Promise<void>;
  pause(): Promise<void>;
  resume(): Promise<void>;
  seekTo(positionMs: number): Promise<void>;
  stop(): Promise<void>;
  subscribe(listener: (snapshot: PlaybackSnapshot) => void): Unsubscribe;
}

export interface SettingsRepository {
  get(): Promise<AppSettings>;
  save(settings: AppSettings): Promise<void>;
}

export interface LearningBackupRepository {
  export(destination: DocumentRef, password?: string): Promise<OperationResult>;
  inspect(source: DocumentRef, password?: string): Promise<LearningBackupInspection>;
  restore(previewId: string): Promise<OperationResult>;
  discardPreview(previewId: string): Promise<void>;
  getSupportInfo(): Promise<AppSupportInfo>;
  exportDiagnostics(destination: DocumentRef): Promise<OperationResult>;
}
