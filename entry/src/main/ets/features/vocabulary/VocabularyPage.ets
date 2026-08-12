import { promptAction } from '@kit.ArkUI';
import { appServices } from '../../ability/AppServices';
import { QuestionMode, VocabularyAssessment, VocabularyExample, VocabularyQueue, VocabularySessionView } from '../../domain/Models';
import { shortError } from '../../ui/Common';
import { fadeTransition } from '../../ui/TransitionUtil';

@Component
export struct VocabularyPage {
  @StorageLink('detailMode') detailMode: boolean = false;
  @State queue: VocabularyQueue = { newCount: 0, reviewCount: 0, totalCount: 0 };
  @State sessionView: VocabularySessionView = {
    sessionId: '', status: 'IDLE', currentIndex: 0, totalCount: 0,
    questionMode: QuestionMode.INTRODUCE, word: null, answerRevealed: false, hintRevealed: false,
    assessmentSubmitted: false, selectedAssessment: null
  };
  @State studying: boolean = false;
  @State completed: boolean = false;
  @State busy: boolean = false;
  @State errorMessage: string = '';

  aboutToAppear(): void { this.loadQueue(); }

  build() {
    if (this.errorMessage.length > 0) { this.errorView(); }
    else if (this.completed) { this.completionView(); }
    else if (this.studying && this.sessionView.status === 'IN_PROGRESS') { this.studyView(); }
    else { this.homeView(); }
  }

  @Builder homeView() {
    Column() {
      Blank();
      Column({ space: 16 }) {
        Text('今日词汇').fontSize(30).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'));
        Text(`新内容 ${this.queue.newCount} 条 · 到期 ${this.queue.reviewCount} 条`)
          .fontSize(16).fontColor($r('app.color.text_secondary'));
        if (this.queue.totalCount > 0) {
          Button(this.busy ? '正在准备' : '开始背单词').height(52).width(220).enabled(!this.busy)
            .onClick(() => this.start());
        } else {
          Text('今天的自动学习任务已完成').fontSize(16).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.success')).padding(16);
        }
      }.padding(24).width('100%');
      Blank();
    }.width('100%').height('100%').backgroundColor($r('app.color.surface_muted')).transition(fadeTransition());
  }

  @Builder studyView() {
    Column() {
      Row() {
        Button('返回').type(ButtonType.Normal).height(48).fontColor($r('app.color.brand_primary'))
          .backgroundColor(Color.Transparent).onClick(() => this.leaveStudy());
        Blank();
        Text(`${this.sessionView.currentIndex + 1} / ${this.sessionView.totalCount}`)
          .fontSize(14).fontColor($r('app.color.text_secondary'));
      }.height(56).width('100%').padding({ left: 8, right: 16 });
      Scroll() {
        Column({ space: 16 }) {
          Row() {
            Column({ space: 6 }) {
              Text(this.sessionView.word?.term ?? '').fontSize(30).fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary')).width('100%');
              if ((this.sessionView.word?.ipa ?? '').length > 0) {
                Text(this.sessionView.word?.ipa ?? '').fontSize(16).fontColor($r('app.color.text_secondary')).width('100%');
              }
            }.alignItems(HorizontalAlign.Start).layoutWeight(1);
            Button('朗读').type(ButtonType.Normal).height(48).fontColor($r('app.color.brand_primary'))
              .backgroundColor($r('app.color.brand_primary_container')).onClick(() => this.playWord());
          }.width('100%');

          Text(this.sessionView.word?.chineseGloss ?? '').fontSize(20).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.brand_primary')).width('100%');

          Column({ space: 12 }) {
            ForEach(this.sessionView.word?.examples ?? [], (example: VocabularyExample) => {
              Row({ space: 8 }) {
                Column({ space: 4 }) {
                  Text(example.textEn).fontSize(16).lineHeight(24).fontColor($r('app.color.text_primary')).width('100%');
                  if ((example.textZh ?? '').length > 0) {
                    Text(example.textZh ?? '').fontSize(14).lineHeight(22)
                      .fontColor($r('app.color.text_secondary')).width('100%');
                  }
                }.alignItems(HorizontalAlign.Start).layoutWeight(1);
                Button('朗读').type(ButtonType.Normal).height(48).fontColor($r('app.color.brand_primary'))
                  .backgroundColor(Color.Transparent).onClick(() => this.playExample(example));
              }.padding(14).width('100%').backgroundColor($r('app.color.surface_container')).borderRadius(16);
            }, (example: VocabularyExample) => example.id);
          }.width('100%');

          if (!this.sessionView.assessmentSubmitted) {
            Text('你对这一条的熟悉程度？').fontSize(16).fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary')).width('100%').margin({ top: 8 });
            Row({ space: 8 }) {
              Button('陌生').layoutWeight(1).height(52).enabled(!this.busy)
                .onClick(() => this.assess(VocabularyAssessment.UNFAMILIAR));
              Button('模糊').layoutWeight(1).height(52).enabled(!this.busy)
                .onClick(() => this.assess(VocabularyAssessment.FUZZY));
              Button('掌握').layoutWeight(1).height(52).enabled(!this.busy)
                .onClick(() => this.assess(VocabularyAssessment.MASTERED));
            }.width('100%');
          } else {
            Text(`已选择：${this.assessmentLabel(this.sessionView.selectedAssessment)}`)
              .fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.brand_primary')).width('100%');
            Button(this.sessionView.currentIndex + 1 >= this.sessionView.totalCount ? '完成本次学习' : '下一条')
              .height(52).width('100%').enabled(!this.busy).onClick(() => this.advance());
          }
          Blank().height(24);
        }.padding({ left: 16, right: 16 }).width('100%').alignItems(HorizontalAlign.Start);
      }.layoutWeight(1).width('100%').edgeEffect(EdgeEffect.Spring);
    }.width('100%').height('100%').backgroundColor($r('app.color.surface_muted')).transition(fadeTransition());
  }

  @Builder completionView() {
    Column({ space: 16 }) {
      Blank();
      Text('本次学习已完成').fontSize(28).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'));
      Text('学习进度已保存在本机').fontSize(16).fontColor($r('app.color.text_secondary'));
      Button('返回今日词汇').height(52).width(220).onClick(() => {
        this.completed = false; this.studying = false; this.detailMode = false; this.loadQueue();
      });
      Blank();
    }.padding(24).width('100%').height('100%').transition(fadeTransition());
  }

  @Builder errorView() {
    Column({ space: 16 }) {
      Blank();
      Text('词汇学习暂时无法继续').fontSize(24).fontWeight(FontWeight.Bold).fontColor($r('app.color.danger'));
      Text(this.errorMessage).fontSize(14).fontColor($r('app.color.text_secondary')).textAlign(TextAlign.Center);
      Row({ space: 12 }) {
        Button('返回').height(52).onClick(() => { this.errorMessage = ''; this.leaveStudy(); });
        Button('重试').height(52).onClick(() => { this.errorMessage = ''; this.reloadSession(); });
      }
      Blank();
    }.padding(24).width('100%').height('100%').transition(fadeTransition());
  }

  private async loadQueue(): Promise<void> {
    try { this.queue = await appServices.vocabulary.todayQueue(); }
    catch (error) { this.errorMessage = shortError(error); }
  }

  private async start(): Promise<void> {
    try {
      this.busy = true; this.errorMessage = '';
      const id = await appServices.vocabulary.startOrResumeSession();
      this.sessionView = await appServices.vocabulary.session(id);
      this.studying = true; this.completed = false; this.detailMode = true;
      await this.autoPlayWord();
    } catch (error) { this.errorMessage = shortError(error); this.detailMode = true; }
    finally { this.busy = false; }
  }

  private leaveStudy(): void {
    appServices.audio.stop(); this.studying = false; this.completed = false; this.detailMode = false; this.loadQueue();
  }

  private async assess(value: VocabularyAssessment): Promise<void> {
    try {
      this.busy = true;
      await appServices.vocabulary.submitAssessment(this.sessionView.sessionId, value);
      await this.reloadSession();
    } catch (error) { this.toast(error); }
    finally { this.busy = false; }
  }

  private async advance(): Promise<void> {
    try {
      this.busy = true;
      await appServices.vocabulary.advanceToNext(this.sessionView.sessionId);
      await this.reloadSession();
      if (!this.completed) await this.autoPlayWord();
    } catch (error) { this.errorMessage = shortError(error); }
    finally { this.busy = false; }
  }

  private async reloadSession(): Promise<void> {
    const view = await appServices.vocabulary.session(this.sessionView.sessionId);
    this.sessionView = view;
    if (view.status === 'COMPLETED') { this.completed = true; this.studying = false; }
  }

  private async autoPlayWord(): Promise<void> {
    const word = this.sessionView.word; if (word === null) return;
    const settings = await appServices.settings.get();
    if (settings.autoPlayVocabularyAudio) await appServices.audio.play(word.wordAudioAssetId, settings.playbackSpeed);
  }

  private async playWord(): Promise<void> {
    const word = this.sessionView.word; if (word === null) return;
    const settings = await appServices.settings.get();
    await appServices.audio.play(word.wordAudioAssetId, settings.playbackSpeed);
  }

  private async playExample(example: VocabularyExample): Promise<void> {
    const settings = await appServices.settings.get();
    await appServices.audio.play(example.audioAssetId, settings.playbackSpeed);
  }

  private assessmentLabel(value: string | null): string {
    if (value === VocabularyAssessment.UNFAMILIAR) return '陌生';
    if (value === VocabularyAssessment.FUZZY) return '模糊';
    if (value === VocabularyAssessment.MASTERED) return '掌握';
    return '';
  }

  private toast(error: Object): void { promptAction.showToast({ message: shortError(error) }); }
}
