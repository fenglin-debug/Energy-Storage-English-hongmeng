import { promptAction } from '@kit.ArkUI';
import { appServices } from '../../ability/AppServices';
import {
  AppSettings, AppSupportInfo, CorpusPreview, DEFAULT_SETTINGS, DocumentRef, LearningBackupInspection
} from '../../domain/Models';
import { fileService } from '../../data/FileService';
import { InfoCard, SectionTitle, shortError } from '../../ui/Common';

@Component
export struct SettingsPage {
  @State settings: AppSettings = DEFAULT_SETTINGS;
  @State support: AppSupportInfo = {
    appVersionName: '0.4.1', appVersionCode: 5, databaseVersion: 1,
    corpusPackageKey: null, corpusContentVersion: null,
    recordCounts: { wordMemoryStates: 0, reviewLogs: 0, vocabularyCheckpoints: 0, reviewActionKeys: 0,
      scenarioSessions: 0, scenarioTurnProgress: 0, studyTasks: 0, itemMemoryStates: 0, articleProgress: 0 },
    lastBackupAtEpochMs: null, lastErrorCode: null, systemVersion: 'HarmonyOS', architecture: '-',
    signingFingerprint: '不可用'
  };
  @State password: string = '';
  @State passwordConfirm: string = '';
  @State encryptedExport: boolean = true;
  @State plainConfirmed: boolean = false;
  @State backupPreview: LearningBackupInspection = {
    previewId: '', createdAtEpochMs: 0, appVersionName: '', appVersionCode: 0, databaseVersion: 0,
    corpusPackageKey: null, corpusContentVersion: null, corpusMatches: false, encrypted: false,
    counts: { wordMemoryStates: 0, reviewLogs: 0, vocabularyCheckpoints: 0, reviewActionKeys: 0,
      scenarioSessions: 0, scenarioTurnProgress: 0, studyTasks: 0, itemMemoryStates: 0, articleProgress: 0 }
  };
  @State corpusPreview: CorpusPreview = {
    previewId: '', packageId: '', contentVersion: '', vocabularyCount: 0, phraseCount: 0,
    exampleCount: 0, scenarioCount: 0, audioCount: 0, addedCount: 0, updatedCount: 0,
    removedCount: 0, unchangedCount: 0
  };
  @State hasBackupPreview: boolean = false;
  @State hasCorpusPreview: boolean = false;
  @State hasPendingBackup: boolean = false;
  @State busy: boolean = false;
  private pendingBackup: DocumentRef | null = null;

  aboutToAppear(): void { this.refresh(); }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        SectionTitle({ text: '播放' });
        Text('播放速度').fontSize(16).fontWeight(FontWeight.Medium).width('100%');
        Row({ space: 8 }) {
          ForEach([0.85, 1.0, 1.15], (speed: number) => {
            Button(`${speed}×`).layoutWeight(1).height(48)
              .backgroundColor(this.settings.playbackSpeed === speed ? $r('app.color.brand_primary') : $r('app.color.surface_container'))
              .fontColor(this.settings.playbackSpeed === speed ? $r('app.color.on_brand') : $r('app.color.text_primary'))
              .onClick(() => { this.settings.playbackSpeed = speed; });
          });
        }.width('100%');
        this.settingSwitch('自动播放客户音频', this.settings.autoPlayCustomerAudio,
          value => { this.settings.autoPlayCustomerAudio = value; });
        this.settingSwitch('自动播放词汇音频', this.settings.autoPlayVocabularyAudio,
          value => { this.settings.autoPlayVocabularyAudio = value; });
        this.settingSwitch('自动播放下一篇文章', this.settings.autoPlayNextArticle,
          value => { this.settings.autoPlayNextArticle = value; });

        SectionTitle({ text: '学习记录备份' });
        InfoCard({ title: '三端通用 .bessbackup', body: '完整覆盖恢复九类学习记录，不包含语料正文、音频、导入文章、设置或审计内容。' });
        this.settingSwitch('使用密码加密（推荐）', this.encryptedExport,
          value => { this.encryptedExport = value; this.plainConfirmed = false; });
        if (this.encryptedExport) {
          TextInput({ placeholder: '密码（至少 8 个字符）', text: this.password }).type(InputType.Password)
            .height(48).onChange(value => { this.password = value; });
          TextInput({ placeholder: '再次输入密码', text: this.passwordConfirm }).type(InputType.Password)
            .height(48).onChange(value => { this.passwordConfirm = value; });
        } else {
          Row({ space: 10 }) {
            Toggle({ type: ToggleType.Checkbox, isOn: this.plainConfirmed })
              .onChange(value => { this.plainConfirmed = value; });
            Text('我确认：未加密备份会暴露全部学习记录').fontSize(14).layoutWeight(1);
          }.height(52).width('100%');
        }
        Row({ space: 10 }) {
          Button('导出备份').layoutWeight(1).height(52).enabled(!this.busy).onClick(() => this.exportBackup());
          Button('检查并恢复').layoutWeight(1).height(52).enabled(!this.busy).onClick(() => this.selectBackup());
        }
        if (this.hasPendingBackup && !this.hasBackupPreview) {
          Text('如果备份已加密，请输入密码后重试检查。').fontSize(14)
            .fontColor($r('app.color.text_secondary')).width('100%');
          TextInput({ placeholder: '备份密码', text: this.password }).type(InputType.Password)
            .height(48).onChange(value => { this.password = value; });
          Button('使用密码重试').height(52).width('100%').onClick(() => this.inspectPending());
        }
        if (this.hasBackupPreview) { this.backupPreviewCard(); }

        SectionTitle({ text: '版本与支持' });
        this.supportCard();
        Button('导出脱敏诊断报告').height(52).width('100%').onClick(() => this.exportDiagnostics());
        InfoCard({ title: '完全离线', body: '应用无联网、麦克风和 WebView 权限。卸载前请先导出 .bessbackup。' });

        SectionTitle({ text: '学习计划' });
        this.settingRow('每日新词', `${this.settings.dailyNewWordTarget}`);
        Slider({ value: this.settings.dailyNewWordTarget, min: 0, max: 50, step: 1 })
          .onChange(value => { this.settings.dailyNewWordTarget = Math.round(value); });

        SectionTitle({ text: '通知与提醒' });
        this.settingSwitch('每日本地提醒', this.settings.dailyReminderEnabled,
          value => { this.settings.dailyReminderEnabled = value; });
        Row({ space: 8 }) {
          Text('提醒时间').fontSize(16).layoutWeight(1);
          TextInput({ text: this.settings.dailyReminderHour.toString() }).width(64).height(48)
            .inputFilter('[0-9]').onChange(value => { this.settings.dailyReminderHour = Math.min(23, Number(value || 0)); });
          Text(':');
          TextInput({ text: this.settings.dailyReminderMinute.toString().padStart(2, '0') }).width(64).height(48)
            .inputFilter('[0-9]').onChange(value => { this.settings.dailyReminderMinute = Math.min(59, Number(value || 0)); });
        }.width('100%');
        Button('保存播放、计划与提醒').height(52).width('100%').onClick(() => this.saveSettings());

        SectionTitle({ text: '语料库' });
        Row({ space: 10 }) {
          Button('检查 .besspack').layoutWeight(1).height(52).onClick(() => this.inspectCorpus());
          Button('恢复内置语料').layoutWeight(1).height(52).onClick(() => this.restoreCorpus());
        }
        if (this.hasCorpusPreview) { this.corpusPreviewCard(); }
        Text('新语料只会在差异预览并确认后激活；切换不会删除长期学习记忆。')
          .fontSize(13).fontColor($r('app.color.text_secondary')).width('100%');
        Blank().height(24);
      }.padding({ left: 16, right: 16, bottom: 16 }).width('100%').alignItems(HorizontalAlign.Start);
    }.width('100%').height('100%').edgeEffect(EdgeEffect.Spring);
  }

  @Builder settingRow(label: string, value: string) {
    Row() { Text(label).fontSize(16).layoutWeight(1); Text(value).fontSize(16).fontColor($r('app.color.brand_primary')); }
      .height(48).width('100%');
  }

  @Builder settingSwitch(label: string, value: boolean, change: (value: boolean) => void) {
    Row() { Text(label).fontSize(16).layoutWeight(1); Toggle({ type: ToggleType.Switch, isOn: value }).onChange(change); }
      .height(52).width('100%');
  }

  @Builder backupPreviewCard() {
    Column({ space: 8 }) {
      Text('恢复预览').fontSize(18).fontWeight(FontWeight.Bold).width('100%');
      Text(`创建：${new Date(this.backupPreview.createdAtEpochMs).toLocaleString()}`).width('100%');
      Text(`来源：v${this.backupPreview.appVersionName} (${this.backupPreview.appVersionCode}) · DB ${this.backupPreview.databaseVersion}`).width('100%');
      Text(this.backupPreview.corpusMatches ? '语料一致：可精确恢复断点' : '语料不同：长期记忆保留，进行中断点将终止')
        .fontColor(this.backupPreview.corpusMatches ? $r('app.color.success') : $r('app.color.warning')).width('100%');
      Text(this.countText(this.backupPreview)).fontSize(13).fontColor($r('app.color.text_secondary')).width('100%');
      Text('继续会完整覆盖本机现有学习记录。').fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.danger')).width('100%');
      Row({ space: 10 }) {
        Button('取消').layoutWeight(1).height(52).onClick(() => this.discardBackupPreview());
        Button('确认完整覆盖恢复').layoutWeight(2).height(52).onClick(() => this.restoreBackup());
      }
    }.padding(16).backgroundColor($r('app.color.surface')).borderRadius(16)
      .border({ width: 1, color: $r('app.color.warning') }).width('100%');
  }

  @Builder corpusPreviewCard() {
    Column({ space: 8 }) {
      Text('语料差异预览').fontSize(18).fontWeight(FontWeight.Bold).width('100%');
      Text(`${this.corpusPreview.packageId} / ${this.corpusPreview.contentVersion}`).width('100%');
      Text(`词汇 ${this.corpusPreview.vocabularyCount} · 短语 ${this.corpusPreview.phraseCount} · 例句 ${this.corpusPreview.exampleCount}`)
        .width('100%');
      Text(`场景 ${this.corpusPreview.scenarioCount} · 音频 ${this.corpusPreview.audioCount}`).width('100%');
      Text(`新增 ${this.corpusPreview.addedCount} · 更新 ${this.corpusPreview.updatedCount} · 删除 ${this.corpusPreview.removedCount} · 不变 ${this.corpusPreview.unchangedCount}`)
        .fontColor($r('app.color.text_secondary')).width('100%');
      Row({ space: 10 }) {
        Button('取消').layoutWeight(1).height(52).onClick(() => this.discardCorpusPreview());
        Button('确认激活').layoutWeight(1).height(52).onClick(() => this.activateCorpus());
      }
    }.padding(16).backgroundColor($r('app.color.surface')).borderRadius(16)
      .border({ width: 1, color: $r('app.color.brand_primary') }).width('100%');
  }

  @Builder supportCard() {
    Column({ space: 7 }) {
      Text(`BESS HarmonyOS v${this.support.appVersionName} (${this.support.appVersionCode})`)
        .fontSize(17).fontWeight(FontWeight.Medium).width('100%');
      Text(`系统：${this.support.systemVersion}`).width('100%');
      Text(`设备架构：${this.support.architecture}`).width('100%');
      Text(`数据库版本：${this.support.databaseVersion}`).width('100%');
      Text(`语料：${this.support.corpusPackageKey ?? '未加载'} / ${this.support.corpusContentVersion ?? '-'}`).width('100%');
      Text(`记录：${this.support.recordCounts.wordMemoryStates} 词汇 · ${this.support.recordCounts.scenarioSessions} 场景 · ${this.support.recordCounts.articleProgress} 文章`).width('100%');
      Text(`签名指纹：${this.support.signingFingerprint}`).fontSize(12).maxLines(3)
        .fontColor($r('app.color.text_secondary')).width('100%');
      Text(`最近备份：${this.support.lastBackupAtEpochMs ? new Date(this.support.lastBackupAtEpochMs).toLocaleString() : '尚未备份'}`).width('100%');
      Text(`最近错误码：${this.support.lastErrorCode ?? '无'}`).fontSize(13)
        .fontColor($r('app.color.text_secondary')).width('100%');
    }.alignItems(HorizontalAlign.Start).padding(16).backgroundColor($r('app.color.surface'))
      .borderRadius(16).width('100%');
  }

  private async refresh(): Promise<void> {
    try { this.settings = await appServices.settings.get(); this.support = await appServices.backup.getSupportInfo(); }
    catch (error) { this.toast(error); }
  }

  private async saveSettings(): Promise<void> {
    try {
      await appServices.settings.save(this.settings);
      await appServices.reminders.apply(this.settings);
      promptAction.showToast({ message: '设置与本地提醒已保存' });
    } catch (error) { this.toast(error); }
  }

  private async exportBackup(): Promise<void> {
    if (this.encryptedExport && this.password.normalize('NFC').length < 8) {
      promptAction.showToast({ message: '密码至少 8 个字符' }); return;
    }
    if (this.encryptedExport && this.password !== this.passwordConfirm) {
      promptAction.showToast({ message: '两次输入的密码不一致' }); return;
    }
    if (!this.encryptedExport && !this.plainConfirmed) {
      promptAction.showToast({ message: '请先确认未加密风险' }); return;
    }
    const destination = await fileService.pickSave(`BESS-${new Date().toISOString().slice(0, 10)}.bessbackup`, ['.bessbackup']);
    if (!destination) return;
    try {
      this.busy = true;
      const result = await appServices.backup.export(destination, this.encryptedExport ? this.password : undefined);
      promptAction.showToast({ message: result.message }); await this.refresh();
    } catch (error) { this.toast(error); } finally { this.busy = false; }
  }

  private async selectBackup(): Promise<void> {
    this.pendingBackup = await fileService.pickOpen(['.bessbackup']);
    this.hasBackupPreview = false; this.hasPendingBackup = this.pendingBackup !== null;
    if (this.pendingBackup !== null) await this.inspectPending();
  }

  private async inspectPending(): Promise<void> {
    if (this.pendingBackup === null) return;
    try {
      this.busy = true;
      this.backupPreview = await appServices.backup.inspect(this.pendingBackup, this.password || undefined);
      this.hasBackupPreview = true;
    } catch (error) { this.toast(error); } finally { this.busy = false; }
  }

  private async restoreBackup(): Promise<void> {
    if (!this.hasBackupPreview) return;
    const result = await appServices.backup.restore(this.backupPreview.previewId);
    promptAction.showToast({ message: result.message });
    this.hasBackupPreview = false; this.hasPendingBackup = false; this.pendingBackup = null; await this.refresh();
  }

  private async discardBackupPreview(): Promise<void> {
    if (this.hasBackupPreview) await appServices.backup.discardPreview(this.backupPreview.previewId);
    this.hasBackupPreview = false; this.hasPendingBackup = false; this.pendingBackup = null;
  }

  private async inspectCorpus(): Promise<void> {
    const source = await fileService.pickOpen(['.besspack']); if (!source) return;
    try { this.corpusPreview = await appServices.corpus.inspectPackage(source); this.hasCorpusPreview = true; }
    catch (error) { this.toast(error); }
  }

  private async activateCorpus(): Promise<void> {
    const result = await appServices.corpus.activatePreview(this.corpusPreview.previewId);
    promptAction.showToast({ message: result.message });
    if (result.ok) { this.hasCorpusPreview = false; await this.refresh(); }
  }

  private async discardCorpusPreview(): Promise<void> {
    await appServices.corpus.discardPreview(this.corpusPreview.previewId); this.hasCorpusPreview = false;
  }

  private async restoreCorpus(): Promise<void> {
    const result = await appServices.corpus.restoreBundled(); promptAction.showToast({ message: result.message }); await this.refresh();
  }

  private async exportDiagnostics(): Promise<void> {
    const destination = await fileService.pickSave('BESS-diagnostics.json', ['.json']); if (!destination) return;
    const result = await appServices.backup.exportDiagnostics(destination); promptAction.showToast({ message: result.message });
  }

  private countText(value: LearningBackupInspection): string {
    const c = value.counts;
    return `词汇 ${c.wordMemoryStates} · 日志 ${c.reviewLogs} · 词汇断点 ${c.vocabularyCheckpoints} · 幂等键 ${c.reviewActionKeys} · 场景 ${c.scenarioSessions}/${c.scenarioTurnProgress} · 任务 ${c.studyTasks} · 其他记忆 ${c.itemMemoryStates} · 文章 ${c.articleProgress}`;
  }

  private toast(error: Object): void { promptAction.showToast({ message: shortError(error) }); }
}
