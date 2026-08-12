import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { AppSettings } from '../domain/Models';
import { DatabaseService } from './DatabaseService';

const REMINDER_ID_KEY = 'daily_reminder_id';

export class ReminderService {
  private readonly database: DatabaseService;
  private readonly context: common.UIAbilityContext;

  constructor(database: DatabaseService, context: common.UIAbilityContext) {
    this.database = database; this.context = context;
  }

  async apply(settings: AppSettings): Promise<void> {
    await this.cancelCurrent();
    if (!settings.dailyReminderEnabled) return;
    const permission: Permissions = 'ohos.permission.PUBLISH_AGENT_REMINDER';
    const result = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(this.context, [permission]);
    if (result.authResults.length === 0 || result.authResults[0] !== 0) throw new Error('REMINDER_PERMISSION_DENIED');
    const request: reminderAgentManager.ReminderRequestAlarm = {
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_ALARM,
      hour: settings.dailyReminderHour,
      minute: settings.dailyReminderMinute,
      daysOfWeek: [1, 2, 3, 4, 5, 6, 7],
      title: 'BESS 储能英语实战',
      content: '今天的词汇和场景训练在等你。',
      expiredContent: '今日学习提醒已过期',
      actionButton: [{ title: '知道了', type: reminderAgentManager.ActionButtonType.ACTION_BUTTON_TYPE_CLOSE }],
      ringDuration: 3,
      snoozeTimes: 0,
      notificationId: 20020
    };
    const id = await reminderAgentManager.publishReminder(request);
    await this.database.putMetadata(REMINDER_ID_KEY, id.toString());
  }

  private async cancelCurrent(): Promise<void> {
    const raw = await this.database.metadata(REMINDER_ID_KEY);
    if (raw === null) return;
    try { await reminderAgentManager.cancelReminder(Number(raw)); } catch (_) {}
    await this.database.get().executeSql('DELETE FROM app_metadata WHERE key=?', [REMINDER_ID_KEY]);
  }
}
