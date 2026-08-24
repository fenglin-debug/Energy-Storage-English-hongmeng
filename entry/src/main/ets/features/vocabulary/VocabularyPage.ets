import { promptAction } from '@kit.ArkUI';
import { appServices } from '../../ability/AppServices';
import {
  DEFAULT_VOCABULARY_FILTER, FsrsState, MasteryFilter, QuestionMode, Vocabulary, VocabularyAssessment,
  VocabularyExample, VocabularyFilter, VocabularyQueue, VocabularySessionView
} from '../../domain/Models';
import { shortError } from '../../ui/Common';
import { fadeTransition } from '../../ui/TransitionUtil';

const EMPTY_WORD: Vocabulary = {
  id: '', term: '', normalizedTerm: '', ipa: '', partOfSpeech: '', chineseGloss: '', englishDefinition: null,
  collocations: [], exampleSentenceEn: '', exampleSentenceZh: null, commonMistakes: '', topic: '', scenarioTags: [],
  cefrLevel: '', wordAudioAssetId: '', exampleAudioAssetId: '', contentHash: '', favorite: false, memoryState: null,
  itemKind: 'WORD', aliases: [], examples: []
};

@Component
export struct VocabularyPage {
  @StorageLink('detailMode') detailMode: boolean = false;
  @State queue: VocabularyQueue = { newCount: 0, reviewCount: 0, totalCount: 0 };
  @State words: Vocabulary[] = [];
  @State filter: VocabularyFilter = {
    query: DEFAULT_VOCABULARY_FILTER.query,
    mastery: DEFAULT_VOCABULARY_FILTER.mastery,
    dueOnly: DEFAULT_VOCABULARY_FILTER.dueOnly,
    favoritesOnly: DEFAULT_VOCABULARY_FILTER.favoritesOnly,
    topic: DEFAULT_VOCABULARY_FILTER.topic,
    cefrLevel: DEFAULT_VOCABULARY_FILTER.cefrLevel
  };
  @State selectedWord: Vocabulary = EMPTY_WORD;
  @State detailVisible: boolean = false;
  @State sessionView: VocabularySessionView = {
    sessionId: '', status: 'IDLE', currentIndex: 0, totalCount: 0,
    questionMode: QuestionMode.INTRODUCE, word: null, answerRevealed: false, hintRevealed: false,
    assessmentSubmitted: false, selectedAssessment: null
  };
  @State studying: boolean = false;
  @State completed: boolean = false;
  @State busy: boolean = false;
  @State loadingWords: boolean = true;
  @State errorMessage: string = '';

  aboutToAppear(): void { this.loadQueue(); this.loadWords(); }

  build() {
    if (this.errorMessage.length > 0) this.errorView();
    else if (this.completed) this.completionView();
    else if (this.studying && this.sessionView.status === 'IN_PROGRESS') this.studyView();
    else if (this.detailVisible) this.detailView();
    else this.homeView();
  }

  @Builder homeView() {
    Column({ space: 10 }) {
      Column({ space: 8 }) {
        Text('今日词汇').fontSize(24).fontWeight(FontWeight.Bold).width('100%');
        Text(`新内容 ${this.queue.newCount} 条 · 到期 ${this.queue.reviewCount} 条`)
          .fontSize(15).fontColor($r('app.color.text_secondary')).width('100%');
        Button(this.busy ? '正在准备' : '开始背单词').height(52).width('100%')
          .enabled(!this.busy && this.queue.totalCount > 0).onClick(() => this.start());
        if (!this.busy && this.queue.totalCount === 0) {
          Text('今天的自动学习任务已完成').fontSize(14).fontColor($r('app.color.success')).width('100%');
        }
      }.alignItems(HorizontalAlign.Start).width('100%');

      TextInput({ placeholder: '搜索单词 / 释义 / 别名', text: this.filter.query }).height(48).width('100%')
        .onChange(value => { this.filter.query = value; this.loadWords(); });

      Scroll() {
        Row({ space: 8 }) {
          this.filterButton('未学', this.filter.mastery === MasteryFilter.NOT_STARTED,
            () => this.toggleMastery(MasteryFilter.NOT_STARTED));
          this.filterButton('学习中', this.filter.mastery === MasteryFilter.LEARNING,
            () => this.toggleMastery(MasteryFilter.LEARNING));
          this.filterButton('已掌握', this.filter.mastery === MasteryFilter.MASTERED,
            () => this.toggleMastery(MasteryFilter.MASTERED));
          this.filterButton('到期', this.filter.dueOnly, () => { this.filter.dueOnly = !this.filter.dueOnly; this.loadWords(); });
          this.filterButton('收藏', this.filter.favoritesOnly,
            () => { this.filter.favoritesOnly = !this.filter.favoritesOnly; this.loadWords(); });
        }.height(48);
      }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%');

      if (this.loadingWords) {
        Column() { Blank(); Text('正在加载词库…').fontColor($r('app.color.text_secondary')); Blank(); }
          .layoutWeight(1).width('100%');
      } else if (this.words.length === 0) {
        Column({ space: 12 }) {
          Blank();
          Text(this.hasFilter() ? '没有符合条件的词' : '正在准备离线学习内容，请稍候')
            .fontColor($r('app.color.text_secondary')).textAlign(TextAlign.Center);
          if (this.hasFilter()) Button('清除筛选').height(48).onClick(() => this.clearFilter());
          Blank();
        }.layoutWeight(1).width('100%');
      } else {
        List({ space: 8 }) {
          ForEach(this.words, (word: Vocabulary) => {
            ListItem() {
              Row({ space: 8 }) {
                Column({ space: 4 }) {
                  Row() {
                    Text(word.term).fontSize(17).fontWeight(FontWeight.Medium);
                    if (word.ipa.length > 0) Text(`  ${word.ipa}`).fontSize(13).fontColor($r('app.color.text_secondary'));
                  }.width('100%');
                  Text(word.chineseGloss).fontSize(14).width('100%');
                  Text(this.wordMeta(word)).fontSize(12).fontColor($r('app.color.text_secondary')).width('100%');
                }.alignItems(HorizontalAlign.Start).layoutWeight(1).onClick(() => this.openDetail(word.id));
                Button(word.favorite ? '♥' : '♡').type(ButtonType.Normal).width(48).height(48)
                  .fontSize(24).fontColor($r('app.color.brand_primary')).backgroundColor(Color.Transparent)
                  .accessibilityText(word.favorite ? `取消收藏 ${word.term}` : `收藏 ${word.term}`)
                  .onClick(() => this.toggleFavorite(word));
              }.padding({ left: 14, right: 8, top: 10, bottom: 10 }).width('100%')
                .backgroundColor($r('app.color.surface_container')).borderRadius(14);
            }
          }, (word: Vocabulary) => word.id);
        }.layoutWeight(1).width('100%').edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true });
      }
    }.padding({ left: 16, right: 16, bottom: 10 }).width('100%').height('100%').transition(fadeTransition());
  }

  @Builder filterButton(label: string, selected: boolean, action: () => void) {
    Button(label).type(ButtonType.Normal).height(40).fontSize(14)
      .fontColor(selected ? $r('app.color.brand_primary') : $r('app.color.text_secondary'))
      .backgroundColor(selected ? $r('app.color.brand_primary_container') : $r('app.color.surface_container'))
      .border({ width: 1, color: selected ? $r('app.color.brand_primary') : $r('app.color.border') }).onClick(action);
  }

  @Builder detailView() {
    Column() {
      Row() {
        Button('返回').type(ButtonType.Normal).height(48).fontColor($r('app.color.brand_primary'))
          .backgroundColor(Color.Transparent).onClick(() => this.closeDetail());
        Text('词条详情').fontSize(22).fontWeight(FontWeight.Bold).layoutWeight(1).textAlign(TextAlign.Center);
        Button(this.selectedWord.favorite ? '♥' : '♡').type(ButtonType.Normal).width(48).height(48).fontSize(24)
          .fontColor($r('app.color.brand_primary')).backgroundColor(Color.Transparent)
          .onClick(() => this.toggleDetailFavorite());
      }.height(56).width('100%');
      Scroll() {
        Column({ space: 14 }) {
          Row({ space: 8 }) {
            Column({ space: 5 }) {
              Text(this.selectedWord.term).fontSize(30).fontWeight(FontWeight.Bold).width('100%');
              if (this.selectedWord.ipa.length > 0) {
                Text(this.selectedWord.ipa).fontSize(16).fontColor($r('app.color.text_secondary')).width('100%');
              }
              if (this.selectedWord.partOfSpeech.length > 0) {
                Text(this.selectedWord.partOfSpeech).fontSize(13).fontColor($r('app.color.text_secondary')).width('100%');
              }
            }.alignItems(HorizontalAlign.Start).layoutWeight(1);
            Button('朗读单词').type(ButtonType.Normal).height(48).onClick(() => this.playAsset(this.selectedWord.wordAudioAssetId));
          }.width('100%');
          this.detailSection('中文', this.selectedWord.chineseGloss);
          if ((this.selectedWord.englishDefinition ?? '').length > 0) {
            this.detailSection('英文释义', this.selectedWord.englishDefinition ?? '');
          }
          if (this.selectedWord.collocations.length > 0) this.detailSection('常用搭配', this.selectedWord.collocations.join(' · '));
          ForEach(this.selectedWord.examples, (example: VocabularyExample, index: number) => {
            Column({ space: 6 }) {
              if (index === 0) Text('例句').fontSize(15).fontWeight(FontWeight.Medium).width('100%');
              Text(example.textEn).fontSize(16).lineHeight(24).width('100%');
              if ((example.textZh ?? '').length > 0) {
                Text(example.textZh ?? '').fontSize(14).lineHeight(22).fontColor($r('app.color.text_secondary')).width('100%');
              }
              if (example.audioAssetId.length > 0) {
                Button('朗读例句').type(ButtonType.Normal).height(48).onClick(() => this.playAsset(example.audioAssetId));
              }
            }.alignItems(HorizontalAlign.Start).padding(14).width('100%')
              .backgroundColor($r('app.color.surface_container')).borderRadius(14);
          }, (example: VocabularyExample) => example.id);
          if (this.selectedWord.commonMistakes.length > 0) this.detailSection('易错点', this.selectedWord.commonMistakes);
          if (this.selectedWord.aliases.length > 0) this.detailSection('别名', this.selectedWord.aliases.join(' · '));
          Blank().height(20);
        }.padding({ left: 16, right: 16 }).width('100%').alignItems(HorizontalAlign.Start);
      }.layoutWeight(1).width('100%').edgeEffect(EdgeEffect.Spring);
    }.width('100%').height('100%').transition(fadeTransition());
  }

  @Builder detailSection(label: string, body: string) {
    Column({ space: 5 }) {
      Text(label).fontSize(15).fontWeight(FontWeight.Medium).width('100%');
      Text(body).fontSize(16).lineHeight(24).width('100%');
    }.alignItems(HorizontalAlign.Start).width('100%');
  }

  @Builder studyView() {
    Column() {
      Row() {
        Button('返回').type(ButtonType.Normal).height(48).fontColor($r('app.color.brand_primary'))
          .backgroundColor(Color.Transparent).onClick(() => this.leaveStudy());
        Blank();
        Text(`第 ${this.sessionView.currentIndex + 1} 条 · 剩余 ${Math.max(0, this.sessionView.totalCount - this.sessionView.currentIndex)} · ${this.modeLabel()}`)
          .fontSize(13).fontColor($r('app.color.text_secondary'));
      }.height(56).width('100%').padding({ left: 8, right: 16 });
      Scroll() {
        Column({ space: 14 }) {
          Column({ space: 10 }) {
            this.promptPanel();
            if (this.sessionView.answerRevealed) this.answerPanel();
          }.padding(20).width('100%').backgroundColor($r('app.color.surface_container')).borderRadius(16);
          Blank().height(8);
        }.padding({ left: 16, right: 16 }).width('100%');
      }.layoutWeight(1).width('100%').edgeEffect(EdgeEffect.Spring);
      Column({ space: 10 }) {
        if (!this.sessionView.answerRevealed) {
          Button('显示答案').height(52).width('100%').enabled(!this.busy).onClick(() => this.revealAnswer());
        } else {
          Row({ space: 8 }) {
            this.assessmentButton('陌生', VocabularyAssessment.UNFAMILIAR);
            this.assessmentButton('模糊', VocabularyAssessment.FUZZY);
            this.assessmentButton('掌握', VocabularyAssessment.MASTERED);
          }.width('100%');
          if (this.sessionView.assessmentSubmitted) {
            Button(this.sessionView.currentIndex + 1 >= this.sessionView.totalCount ? '完成本次学习' : '下一条')
              .height(52).width('100%').enabled(!this.busy).onClick(() => this.advance());
          }
        }
        Button('结束本次学习').type(ButtonType.Normal).height(48).width('100%')
          .fontColor($r('app.color.brand_primary')).backgroundColor(Color.Transparent)
          .border({ width: 1, color: $r('app.color.border') }).onClick(() => this.leaveStudy());
      }.padding({ left: 16, right: 16, top: 10, bottom: 12 }).width('100%')
        .backgroundColor($r('app.color.surface_container_high'));
    }.width('100%').height('100%').transition(fadeTransition());
  }

  @Builder promptPanel() {
    if (this.displayMode() === QuestionMode.ZH2EN) {
      Text(this.sessionView.word?.chineseGloss ?? '').fontSize(24).fontWeight(FontWeight.Medium).textAlign(TextAlign.Center);
      Text(this.sessionView.word?.topic ?? '').fontSize(14).fontColor($r('app.color.text_secondary'));
    } else if (this.displayMode() === QuestionMode.LISTENING) {
      Text('听音辨词').fontSize(24).fontWeight(FontWeight.Medium);
      Button('重播单词').type(ButtonType.Normal).height(48).onClick(() => this.playWord());
    } else {
      Text(this.sessionView.word?.term ?? '').fontSize(30).fontWeight(FontWeight.Bold).textAlign(TextAlign.Center);
      if ((this.sessionView.word?.ipa ?? '').length > 0) {
        Text(this.sessionView.word?.ipa ?? '').fontSize(16).fontColor($r('app.color.text_secondary'));
      }
      Button('朗读单词').type(ButtonType.Normal).height(48).onClick(() => this.playWord());
    }
  }

  @Builder answerPanel() {
    if (this.displayMode() === QuestionMode.ZH2EN || this.displayMode() === QuestionMode.LISTENING) {
      Row({ space: 8 }) {
        Column({ space: 4 }) {
          Text(this.sessionView.word?.term ?? '').fontSize(26).fontWeight(FontWeight.Bold).width('100%');
          if ((this.sessionView.word?.ipa ?? '').length > 0) {
            Text(this.sessionView.word?.ipa ?? '').fontSize(15).fontColor($r('app.color.text_secondary')).width('100%');
          }
        }.alignItems(HorizontalAlign.Start).layoutWeight(1);
        Button('朗读单词').type(ButtonType.Normal).height(48).onClick(() => this.playWord());
      }.width('100%');
    }
    if (this.displayMode() !== QuestionMode.ZH2EN) {
      Text(this.sessionView.word?.chineseGloss ?? '').fontSize(20).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.brand_primary')).width('100%');
    }
    if (this.displayMode() === QuestionMode.INTRODUCE && (this.sessionView.word?.collocations.length ?? 0) > 0) {
      Text(this.sessionView.word?.collocations.join(' · ') ?? '').fontSize(15).width('100%');
    }
    ForEach(this.sessionView.word?.examples ?? [], (example: VocabularyExample) => {
      Row({ space: 8 }) {
        Column({ space: 4 }) {
          Text(example.textEn).fontSize(16).lineHeight(24).width('100%');
          if ((example.textZh ?? '').length > 0) {
            Text(example.textZh ?? '').fontSize(14).lineHeight(22).fontColor($r('app.color.text_secondary')).width('100%');
          }
        }.alignItems(HorizontalAlign.Start).layoutWeight(1);
        if (example.audioAssetId.length > 0) {
          Button('朗读例句').type(ButtonType.Normal).height(48).onClick(() => this.playExample(example));
        }
      }.padding(12).width('100%').backgroundColor($r('app.color.surface_muted')).borderRadius(12);
    }, (example: VocabularyExample) => example.id);
    if ((this.sessionView.word?.commonMistakes ?? '').length > 0) {
      Text(this.sessionView.word?.commonMistakes ?? '').fontSize(13).fontColor($r('app.color.text_secondary')).width('100%');
    }
  }

  @Builder assessmentButton(label: string, value: VocabularyAssessment) {
    Button(this.sessionView.assessmentSubmitted ? `改成：${label}` : label).layoutWeight(1).height(52).enabled(!this.busy)
      .fontColor(this.sessionView.selectedAssessment === value ? $r('app.color.brand_primary') : $r('app.color.text_primary'))
      .backgroundColor(this.sessionView.selectedAssessment === value ? $r('app.color.brand_primary_container') : $r('app.color.surface_container'))
      .border({ width: this.sessionView.selectedAssessment === value ? 2 : 1,
        color: this.sessionView.selectedAssessment === value ? $r('app.color.brand_primary') : $r('app.color.border') })
      .onClick(() => this.assess(value));
  }

  @Builder completionView() {
    Column({ space: 16 }) {
      Blank(); Text('本次学习已完成').fontSize(28).fontWeight(FontWeight.Bold);
      Text('学习进度已保存在本机').fontSize(16).fontColor($r('app.color.text_secondary'));
      Button('返回今日词汇').height(52).width(220).onClick(() => {
        this.completed = false; this.studying = false; this.detailMode = false; this.loadQueue(); this.loadWords();
      }); Blank();
    }.padding(24).width('100%').height('100%').transition(fadeTransition());
  }

  @Builder errorView() {
    Column({ space: 16 }) {
      Blank(); Text('词汇学习暂时无法继续').fontSize(24).fontWeight(FontWeight.Bold).fontColor($r('app.color.danger'));
      Text(this.errorMessage).fontSize(14).fontColor($r('app.color.text_secondary')).textAlign(TextAlign.Center);
      Row({ space: 12 }) {
        Button('返回').height(52).onClick(() => { this.errorMessage = ''; this.leaveStudy(); });
        Button('重试').height(52).onClick(() => { this.errorMessage = ''; this.reloadSession(); });
      }
      Blank();
    }.padding(24).width('100%').height('100%').transition(fadeTransition());
  }

  private async loadQueue(): Promise<void> {
    try { this.queue = await appServices.vocabulary.todayQueue(); } catch (error) { this.errorMessage = shortError(error); }
  }

  private async loadWords(): Promise<void> {
    try { this.loadingWords = true; this.words = await appServices.vocabulary.list(this.filter); }
    catch (error) { this.toast(error); } finally { this.loadingWords = false; }
  }

  private async openDetail(id: string): Promise<void> {
    const word = await appServices.vocabulary.get(id);
    if (word === null) { this.toast('找不到这个词'); return; }
    this.selectedWord = word; this.detailVisible = true; this.detailMode = true;
  }

  private closeDetail(): void { appServices.audio.stop(); this.detailVisible = false; this.detailMode = false; this.loadWords(); }

  private async toggleFavorite(word: Vocabulary): Promise<void> {
    await appServices.vocabulary.setFavorite(word.id, !word.favorite); await this.loadWords();
  }

  private async toggleDetailFavorite(): Promise<void> {
    await appServices.vocabulary.setFavorite(this.selectedWord.id, !this.selectedWord.favorite);
    const word = await appServices.vocabulary.get(this.selectedWord.id); if (word !== null) this.selectedWord = word;
  }

  private toggleMastery(value: MasteryFilter): void {
    this.filter.mastery = this.filter.mastery === value ? MasteryFilter.ALL : value; this.loadWords();
  }

  private clearFilter(): void {
    this.filter = {
      query: DEFAULT_VOCABULARY_FILTER.query,
      mastery: DEFAULT_VOCABULARY_FILTER.mastery,
      dueOnly: DEFAULT_VOCABULARY_FILTER.dueOnly,
      favoritesOnly: DEFAULT_VOCABULARY_FILTER.favoritesOnly,
      topic: DEFAULT_VOCABULARY_FILTER.topic,
      cefrLevel: DEFAULT_VOCABULARY_FILTER.cefrLevel
    };
    this.loadWords();
  }

  private hasFilter(): boolean {
    return this.filter.query.trim().length > 0 || this.filter.mastery !== MasteryFilter.ALL ||
      this.filter.dueOnly || this.filter.favoritesOnly || this.filter.topic.length > 0 || this.filter.cefrLevel.length > 0;
  }

  private wordMeta(word: Vocabulary): string {
    const reviews = word.memoryState === null || word.memoryState.reps === 0 ? '未开始' : `复习 ${word.memoryState.reps} 次`;
    return `${word.cefrLevel} · ${word.topic} · ${reviews}`;
  }

  private async start(): Promise<void> {
    try {
      this.busy = true; this.errorMessage = '';
      const id = await appServices.vocabulary.startOrResumeSession(); this.sessionView = await appServices.vocabulary.session(id);
      this.studying = true; this.completed = false; this.detailMode = true; await this.autoPlayListening();
    } catch (error) { this.errorMessage = shortError(error); this.detailMode = true; }
    finally { this.busy = false; }
  }

  private leaveStudy(): void {
    appServices.audio.stop(); this.studying = false; this.completed = false; this.detailMode = false;
    this.loadQueue(); this.loadWords();
  }

  private async revealAnswer(): Promise<void> {
    try { this.busy = true; await appServices.vocabulary.revealAnswer(this.sessionView.sessionId); await this.reloadSession(); }
    catch (error) { this.toast(error); } finally { this.busy = false; }
  }

  private async assess(value: VocabularyAssessment): Promise<void> {
    try { this.busy = true; await appServices.vocabulary.submitAssessment(this.sessionView.sessionId, value); await this.reloadSession(); }
    catch (error) { this.toast(error); } finally { this.busy = false; }
  }

  private async advance(): Promise<void> {
    try {
      this.busy = true; await appServices.vocabulary.advanceToNext(this.sessionView.sessionId); await this.reloadSession();
      if (!this.completed) await this.autoPlayListening();
    } catch (error) { this.errorMessage = shortError(error); } finally { this.busy = false; }
  }

  private async reloadSession(): Promise<void> {
    const view = await appServices.vocabulary.session(this.sessionView.sessionId); this.sessionView = view;
    if (view.status === 'COMPLETED') { this.completed = true; this.studying = false; }
  }

  private displayMode(): QuestionMode {
    return this.sessionView.questionMode === QuestionMode.TRANSFER ? QuestionMode.EN2ZH : this.sessionView.questionMode;
  }

  private modeLabel(): string {
    const mode = this.displayMode();
    if (mode === QuestionMode.INTRODUCE) return '新词学习';
    if (mode === QuestionMode.ZH2EN) return '中译英';
    if (mode === QuestionMode.LISTENING) return '听音辨词';
    return '英译中';
  }

  private async autoPlayListening(): Promise<void> {
    if (this.displayMode() === QuestionMode.LISTENING) await this.playWord();
  }

  private async playWord(): Promise<void> {
    const word = this.sessionView.word; if (word === null || word.wordAudioAssetId.length === 0) return;
    await this.playAsset(word.wordAudioAssetId);
  }

  private async playExample(example: VocabularyExample): Promise<void> { await this.playAsset(example.audioAssetId); }

  private async playAsset(assetId: string): Promise<void> {
    if (assetId.length === 0) return; const settings = await appServices.settings.get();
    await appServices.audio.play(assetId, settings.playbackSpeed);
  }

  private toast(error: Object): void { promptAction.showToast({ message: shortError(error) }); }
}
