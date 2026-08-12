import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { AppSettings, DEFAULT_SETTINGS } from '../domain/Models';
import { SettingsRepository } from '../domain/Repositories';

const STORE_NAME = 'bess-settings';

export class SettingsRepositoryImpl implements SettingsRepository {
  private context: common.UIAbilityContext | null = null;

  initialize(context: common.UIAbilityContext): void { this.context = context; }

  async get(): Promise<AppSettings> {
    const store = await preferences.getPreferences(this.requireContext(), STORE_NAME);
    return {
      playbackSpeed: await store.get('playbackSpeed', DEFAULT_SETTINGS.playbackSpeed) as number,
      dailyNewWordTarget: await store.get('dailyNewWordTarget', DEFAULT_SETTINGS.dailyNewWordTarget) as number,
      autoPlayCustomerAudio: await store.get('autoPlayCustomerAudio', DEFAULT_SETTINGS.autoPlayCustomerAudio) as boolean,
      autoPlayVocabularyAudio: await store.get('autoPlayVocabularyAudio', DEFAULT_SETTINGS.autoPlayVocabularyAudio) as boolean,
      dailyReminderEnabled: await store.get('dailyReminderEnabled', DEFAULT_SETTINGS.dailyReminderEnabled) as boolean,
      dailyReminderHour: await store.get('dailyReminderHour', DEFAULT_SETTINGS.dailyReminderHour) as number,
      dailyReminderMinute: await store.get('dailyReminderMinute', DEFAULT_SETTINGS.dailyReminderMinute) as number,
      lastBackupAtEpochMs: await this.nullableNumber(store, 'lastBackupAtEpochMs')
    };
  }

  async save(value: AppSettings): Promise<void> {
    if (![0.85, 1.0, 1.15].includes(value.playbackSpeed)) throw new Error('INVALID_PLAYBACK_SPEED');
    if (value.dailyNewWordTarget < 0 || value.dailyNewWordTarget > 50) throw new Error('INVALID_DAILY_TARGET');
    if (value.dailyReminderHour < 0 || value.dailyReminderHour > 23 ||
      value.dailyReminderMinute < 0 || value.dailyReminderMinute > 59) throw new Error('INVALID_REMINDER_TIME');
    const store = await preferences.getPreferences(this.requireContext(), STORE_NAME);
    await store.put('playbackSpeed', value.playbackSpeed);
    await store.put('dailyNewWordTarget', value.dailyNewWordTarget);
    await store.put('autoPlayCustomerAudio', value.autoPlayCustomerAudio);
    await store.put('autoPlayVocabularyAudio', value.autoPlayVocabularyAudio);
    await store.put('dailyReminderEnabled', value.dailyReminderEnabled);
    await store.put('dailyReminderHour', value.dailyReminderHour);
    await store.put('dailyReminderMinute', value.dailyReminderMinute);
    if (value.lastBackupAtEpochMs === null) await store.delete('lastBackupAtEpochMs');
    else await store.put('lastBackupAtEpochMs', value.lastBackupAtEpochMs);
    await store.flush();
  }

  private async nullableNumber(store: preferences.Preferences, key: string): Promise<number | null> {
    if (!await store.has(key)) return null;
    return await store.get(key, 0) as number;
  }

  private requireContext(): common.UIAbilityContext {
    if (this.context === null) throw new Error('SETTINGS_NOT_INITIALIZED');
    return this.context;
  }
}

export const settingsRepository = new SettingsRepositoryImpl();
