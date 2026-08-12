import { common } from '@kit.AbilityKit';
import {
  ArticleRepository, AudioPlaybackRepository, CorpusRepository, LearningBackupRepository,
  ScenarioRepository, SettingsRepository, VocabularyRepository
} from '../domain/Repositories';
import { databaseService } from '../data/DatabaseService';
import { fileService } from '../data/FileService';
import { settingsRepository } from '../data/SettingsRepositoryImpl';
import { CorpusRepositoryImpl } from '../data/CorpusRepositoryImpl';
import { ArticleRepositoryImpl } from '../data/ArticleRepositoryImpl';
import { VocabularyRepositoryImpl } from '../data/VocabularyRepositoryImpl';
import { ScenarioRepositoryImpl } from '../data/ScenarioRepositoryImpl';
import { AudioPlaybackRepositoryImpl } from '../data/AudioPlaybackRepositoryImpl';
import { LearningBackupRepositoryImpl } from '../data/LearningBackupRepositoryImpl';
import { cryptoService } from '../data/CryptoService';
import { learningBackupCodec } from '../data/LearningBackupCodec';
import { ReminderService } from '../data/ReminderService';

export class AppServices {
  vocabulary!: VocabularyRepository;
  scenarios!: ScenarioRepository;
  articles!: ArticleRepository;
  corpus!: CorpusRepository;
  audio!: AudioPlaybackRepository;
  settings!: SettingsRepository;
  backup!: LearningBackupRepository;
  reminders!: ReminderService;
  initialized: boolean = false;
  initializationError: string | null = null;

  async initialize(context: common.UIAbilityContext): Promise<void> {
    if (this.initialized) return;
    try {
      await databaseService.initialize(context); fileService.initialize(context); settingsRepository.initialize(context);
      const corpus = new CorpusRepositoryImpl(databaseService, fileService, cryptoService);
      const articles = new ArticleRepositoryImpl(databaseService, fileService, cryptoService);
      this.corpus = corpus; this.articles = articles;
      this.vocabulary = new VocabularyRepositoryImpl(databaseService, settingsRepository);
      this.scenarios = new ScenarioRepositoryImpl(databaseService);
      this.audio = new AudioPlaybackRepositoryImpl(databaseService, context);
      this.settings = settingsRepository;
      this.backup = new LearningBackupRepositoryImpl(databaseService, fileService, settingsRepository, learningBackupCodec);
      this.reminders = new ReminderService(databaseService, context);
      await corpus.ensureBundledActivated();
      await articles.ensureBundledArticles();
      this.initialized = true; this.initializationError = null;
    } catch (error) {
      this.initializationError = String(error); throw new Error(this.initializationError);
    }
  }
}

export const appServices = new AppServices();
