import { promptAction } from '@kit.ArkUI';
import { appServices } from '../../ability/AppServices';
import {
  DialogueSelfRating, ScenarioKeyword, ScenarioScoringPoint, ScenarioSummary, ScenarioUnitView
} from '../../domain/Models';
import { shortError } from '../../ui/Common';
import { fadeTransition } from '../../ui/TransitionUtil';

@Component
export struct ScenarioPage {
  @StorageLink('detailMode') detailMode: boolean = false;
  @State scenarios: ScenarioSummary[] = [];
  @State onlyIncomplete: boolean = false;
  @State difficulty: string = '';
  @State unit: ScenarioUnitView = {
    sessionId: '', scenarioTitle: '', pairId: '', pairIndex: 0, pairCount: 0, customerTextEn: '',
    customerTextZh: null, customerAudioAssetId: null, keywords: [], referenceCoreEn: '',
    referenceChineseHint: '', formalAlternatives: [], scoringPoints: [], riskNote: null,
    customerAudioCompleted: false, customerTextRevealed: false, keywordsRevealed: false,
    answerRevealed: false, selfRating: null, practiceMode: 'SCENARIO'
  };
  @State practicing: boolean = false;
  @State completed: boolean = false;
  @State playing: boolean = false;
  @State busy: boolean = false;
  @State ratingDistribution: number[] = [0, 0, 0];
  private unsubscribe: (() => void) | null = null;

  aboutToAppear(): void {
    this.load();
    this.unsubscribe = appServices.audio.subscribe(snapshot => {
      if (snapshot.state === 'completed' && this.practicing) {
        this.playing = false;
        appServices.scenarios.markCustomerAudioCompleted(this.unit.sessionId, this.unit.pairId)
          .then(() => this.refreshUnit()).catch((error: Object) => this.toast(error));
      } else if (snapshot.state === 'playing') this.playing = true;
      else if (snapshot.state === 'paused' || snapshot.state === 'idle' || snapshot.state === 'error') this.playing = false;
    });
  }

  aboutToDisappear(): void { this.unsubscribe?.(); this.unsubscribe = null; }

  build() {
    if (this.completed) { this.completionView(); }
    else if (this.practicing) { this.practiceView(); }
    else { this.listView(); }
  }

  @Builder listView() {
    Column({ space: 12 }) {
      Text('情景模拟').fontSize(24).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%');
      Column({ space: 8 }) {
        Text('随机练习').fontSize(20).fontWeight(FontWeight.Medium).width('100%');
        Text('从全部储能对话中持续抽取，薄弱内容会按间隔再次出现。')
          .fontSize(14).lineHeight(22).fontColor($r('app.color.text_secondary')).width('100%');
        Button('开始随机练习').type(ButtonType.Normal).height(48).width('100%')
          .fontColor($r('app.color.brand_primary')).backgroundColor(Color.Transparent)
          .border({ width: 1, color: $r('app.color.border') }).onClick(() => this.startRandom());
      }.alignItems(HorizontalAlign.Start).padding(16).width('100%')
        .backgroundColor($r('app.color.surface_container')).borderRadius(16);
      Row({ space: 8 }) {
        Toggle({ type: ToggleType.Button, isOn: this.onlyIncomplete }) { Text('未完成').fontSize(14); }
          .height(48).onChange(value => { this.onlyIncomplete = value; this.load(); });
        Toggle({ type: ToggleType.Button, isOn: this.difficulty === 'B1-B2' }) { Text('B1-B2').fontSize(14); }
          .height(48).onChange(value => { this.difficulty = value ? 'B1-B2' : ''; this.load(); });
      }.width('100%');
      List({ space: 8 }) {
        ForEach(this.scenarios, (item: ScenarioSummary) => {
          ListItem() {
            Column({ space: 6 }) {
              Row({ space: 8 }) {
                Text(item.title).fontSize(16).fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary')).layoutWeight(1);
                if (item.duePairCount > 0) {
                  Text(`复习 ${item.duePairCount}`).fontSize(12).fontColor($r('app.color.danger'));
                }
                if (item.status !== null) {
                  Text(item.status === 'IN_PROGRESS' ? '进行中' : '已完成').fontSize(12)
                    .fontColor(item.status === 'IN_PROGRESS' ? $r('app.color.brand_tertiary') : $r('app.color.brand_primary'));
                }
              }.width('100%');
              Text(`${item.topic} · ${item.salesStage} · ${item.customerRole}`).fontSize(13)
                .fontColor($r('app.color.text_secondary')).width('100%');
              Row() {
                Text(`${item.difficulty} · 约 ${item.estimatedMinutes} 分钟`).fontSize(13)
                  .fontColor($r('app.color.text_secondary')).layoutWeight(1);
                Button(item.status === 'IN_PROGRESS' ? '继续' : item.status === 'COMPLETED' ? '再练一次' : '开始')
                  .type(ButtonType.Normal).height(48).fontColor($r('app.color.brand_primary'))
                  .backgroundColor(Color.Transparent).border({ width: 1, color: $r('app.color.border') })
                  .onClick(() => this.start(item.id));
              }.width('100%');
            }.alignItems(HorizontalAlign.Start).padding(16).width('100%')
              .backgroundColor($r('app.color.surface_container')).borderRadius(16);
          }
        }, (item: ScenarioSummary) => item.id);
      }.layoutWeight(1).width('100%').edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true });
    }.padding({ left: 16, right: 16, bottom: 12 }).width('100%').height('100%').transition(fadeTransition());
  }

  @Builder practiceView() {
    Scroll() {
      Column({ space: 14 }) {
        Row() {
          Button('返回').type(ButtonType.Normal).height(48).fontColor($r('app.color.brand_primary'))
            .backgroundColor(Color.Transparent).onClick(() => this.leavePractice());
          Blank();
          Text(`第 ${this.unit.pairIndex + 1} / ${this.unit.pairCount} 轮`)
            .fontSize(14).fontColor($r('app.color.text_secondary'));
        }.width('100%');

        Column({ space: 10 }) {
          Text('客户').fontSize(16).fontWeight(FontWeight.Medium).width('100%');
          if (this.unit.customerTextRevealed) {
            Text(this.unit.customerTextEn).fontSize(17).lineHeight(26).width('100%');
            if ((this.unit.customerTextZh ?? '').length > 0) {
              Text(this.unit.customerTextZh ?? '').fontSize(15).lineHeight(23)
                .fontColor($r('app.color.text_secondary')).width('100%');
            }
          } else {
            Text('▓▓▓▓▓▓▓▓▓▓（先听音频）').fontSize(17)
              .fontColor($r('app.color.text_secondary')).width('100%').accessibilityText('客户原文尚未显示');
          }
          Row({ space: 8 }) {
            Button(this.playing ? '暂停客户音频' : '播放客户音频').type(ButtonType.Normal).height(48)
              .fontColor($r('app.color.brand_primary')).backgroundColor(Color.Transparent)
              .border({ width: 1, color: $r('app.color.border') }).onClick(() => this.playAudio());
            if (!this.unit.customerTextRevealed) {
              Button('显示原文').type(ButtonType.Normal).height(48)
                .enabled(this.unit.customerAudioCompleted || this.unit.customerAudioAssetId === null || this.unit.customerAudioAssetId === '')
                .fontColor($r('app.color.brand_primary')).backgroundColor(Color.Transparent)
                .border({ width: 1, color: $r('app.color.border') }).onClick(() => this.revealText());
            }
          }.width('100%');
        }.alignItems(HorizontalAlign.Start).padding(16).width('100%')
          .backgroundColor($r('app.color.surface_container')).borderRadius(16);

        Column({ space: 8 }) {
          Text('关键词汇').fontSize(16).fontWeight(FontWeight.Medium).width('100%');
          if (this.unit.keywordsRevealed) {
            ForEach(this.unit.keywords, (keyword: ScenarioKeyword) => {
              Text(`${keyword.english}  ${keyword.ipa}  ${keyword.chineseGloss}`)
                .fontSize(15).lineHeight(23).width('100%');
            }, (keyword: ScenarioKeyword) => keyword.vocabularyId);
          } else {
            Button('查看关键词').type(ButtonType.Normal).height(48).fontColor($r('app.color.brand_primary'))
              .backgroundColor(Color.Transparent).border({ width: 1, color: $r('app.color.border') })
              .onClick(() => this.revealKeywords());
          }
        }.alignItems(HorizontalAlign.Start).padding(16).width('100%')
          .backgroundColor($r('app.color.surface_container')).borderRadius(16);

        Column({ space: 8 }) {
          Text('参考回答').fontSize(16).fontWeight(FontWeight.Medium).width('100%');
          if (this.unit.answerRevealed) {
            Text(this.unit.referenceCoreEn).fontSize(17).lineHeight(26).width('100%');
            Text(this.unit.referenceChineseHint).fontSize(15).lineHeight(23)
              .fontColor($r('app.color.text_secondary')).width('100%');
            ForEach(this.unit.formalAlternatives, (answer: string, index: number) => {
              Text(`备选 ${index + 1}：${answer}`).fontSize(15).lineHeight(23).width('100%');
            });
            if (this.unit.scoringPoints.length > 0) {
              Text('评分要点').fontSize(16).fontWeight(FontWeight.Medium).width('100%').margin({ top: 6 });
              ForEach(this.unit.scoringPoints, (point: ScenarioScoringPoint) => {
                Row({ space: 8 }) {
                  Text(point.required ? '【必答】' : '【加分】').fontSize(13)
                    .fontColor(point.required ? $r('app.color.danger') : $r('app.color.brand_tertiary'));
                  Column({ space: 2 }) {
                    Text(point.descriptionZh).fontSize(15).width('100%');
                    if (point.keywordsEn.length > 0) {
                      Text(`关键词：${point.keywordsEn}`).fontSize(13)
                        .fontColor($r('app.color.text_secondary')).width('100%');
                    }
                  }.alignItems(HorizontalAlign.Start).layoutWeight(1);
                }.width('100%');
              }, (point: ScenarioScoringPoint) => point.id);
            }
          } else {
            Button('查看参考回答').type(ButtonType.Normal).height(48).fontColor($r('app.color.brand_primary'))
              .backgroundColor(Color.Transparent).border({ width: 1, color: $r('app.color.border') })
              .onClick(() => this.revealAnswer());
          }
        }.alignItems(HorizontalAlign.Start).padding(16).width('100%')
          .backgroundColor($r('app.color.surface_container')).borderRadius(16);

        if (this.unit.answerRevealed) {
          Text('自评并进入下一轮').fontSize(16).fontWeight(FontWeight.Medium).width('100%');
          Row({ space: 8 }) {
            Button('答不出').layoutWeight(1).height(52).enabled(!this.busy)
              .onClick(() => this.rate(DialogueSelfRating.CANNOT_ANSWER));
            Button('基本完成').layoutWeight(1).height(52).enabled(!this.busy)
              .onClick(() => this.rate(DialogueSelfRating.BASIC));
            Button('流利').layoutWeight(1).height(52).enabled(!this.busy)
              .onClick(() => this.rate(DialogueSelfRating.FLUENT));
          }.width('100%');
        }
        Button('退出本次练习').type(ButtonType.Normal).height(52).width('100%')
          .fontColor($r('app.color.brand_primary')).backgroundColor(Color.Transparent)
          .border({ width: 1, color: $r('app.color.border') }).onClick(() => this.leavePractice());
        Blank().height(20);
      }.padding({ left: 20, right: 20 }).width('100%').alignItems(HorizontalAlign.Start);
    }.width('100%').height('100%').edgeEffect(EdgeEffect.Spring).transition(fadeTransition());
  }

  @Builder completionView() {
    Column({ space: 12 }) {
      Blank();
      Text('情景练习完成').fontSize(24).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'));
      Text(`流利 ${this.ratingDistribution[2]} · 基本 ${this.ratingDistribution[1]} · 待加强 ${this.ratingDistribution[0]}`)
        .fontSize(16).fontColor($r('app.color.text_secondary'));
      Button('返回列表').height(52).onClick(() => {
        this.completed = false; this.practicing = false; this.detailMode = false; this.load();
      });
      Blank();
    }.padding(24).width('100%').height('100%').transition(fadeTransition());
  }

  private async load(): Promise<void> {
    try { this.scenarios = await appServices.scenarios.list('', this.onlyIncomplete, this.difficulty); }
    catch (error) { this.toast(error); }
  }

  private async start(id: string): Promise<void> {
    try {
      const session = await appServices.scenarios.startOrResume(id);
      const unit = await appServices.scenarios.currentUnit(session);
      if (unit !== null) { this.unit = unit; this.practicing = true; this.detailMode = true; await this.autoPlay(); }
    } catch (error) { this.toast(error); }
  }

  private async startRandom(): Promise<void> {
    try {
      const session = await appServices.scenarios.startOrResumeRandom();
      const unit = await appServices.scenarios.currentUnit(session);
      if (unit !== null) { this.unit = unit; this.practicing = true; this.detailMode = true; await this.autoPlay(); }
    } catch (error) { this.toast(error); }
  }

  private async refreshUnit(): Promise<void> {
    const unit = await appServices.scenarios.currentUnit(this.unit.sessionId); if (unit !== null) this.unit = unit;
  }

  private async autoPlay(): Promise<void> {
    const settings = await appServices.settings.get();
    if (settings.autoPlayCustomerAudio && !this.unit.customerAudioCompleted) await this.playAudio();
  }

  private async playAudio(): Promise<void> {
    try {
      if (this.playing) { await appServices.audio.pause(); this.playing = false; return; }
      const asset = this.unit.customerAudioAssetId; if (asset === null || asset.length === 0) throw new Error('AUDIO_NOT_AVAILABLE');
      const settings = await appServices.settings.get(); await appServices.audio.play(asset, settings.playbackSpeed);
    } catch (error) { this.toast(error); }
  }

  private async revealText(): Promise<void> {
    try { await appServices.scenarios.revealCustomerText(this.unit.sessionId, this.unit.pairId); await this.refreshUnit(); }
    catch (error) { this.toast(error); }
  }
  private async revealKeywords(): Promise<void> {
    try { await appServices.scenarios.revealKeywords(this.unit.sessionId, this.unit.pairId); await this.refreshUnit(); }
    catch (error) { this.toast(error); }
  }
  private async revealAnswer(): Promise<void> {
    try { await appServices.scenarios.revealReferenceAnswer(this.unit.sessionId, this.unit.pairId); await this.refreshUnit(); }
    catch (error) { this.toast(error); }
  }

  private async rate(value: DialogueSelfRating): Promise<void> {
    try {
      this.busy = true; const session = this.unit.sessionId;
      const advance = await appServices.scenarios.rateAndAdvance(session, this.unit.pairId, value);
      if (advance.completed) {
        this.ratingDistribution = advance.ratingDistribution; this.completed = true; this.practicing = false;
      } else {
        const unit = await appServices.scenarios.currentUnit(session);
        if (unit !== null) { this.unit = unit; await this.autoPlay(); }
      }
    } catch (error) { this.toast(error); }
    finally { this.busy = false; }
  }

  private async leavePractice(): Promise<void> {
    await appServices.audio.stop();
    if (this.unit.practiceMode === 'RANDOM') await appServices.scenarios.endRandomSession(this.unit.sessionId);
    this.practicing = false; this.completed = false; this.detailMode = false; await this.load();
  }

  private toast(error: Object): void { promptAction.showToast({ message: shortError(error) }); }
}
