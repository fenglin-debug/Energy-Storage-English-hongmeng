import { promptAction } from '@kit.ArkUI';
import { appServices } from '../../ability/AppServices';
import { Article, ArticleParagraph, DocumentRef, PlaybackSnapshot } from '../../domain/Models';
import { fileService } from '../../data/FileService';
import { shortError } from '../../ui/Common';
import { fadeTransition } from '../../ui/TransitionUtil';

@Component
export struct ArticlePage {
  @StorageLink('detailMode') detailMode: boolean = false;
  @State articles: Article[] = [];
  @State current: Article = { id: '', title: '', titleZh: '', topic: '', paragraphs: [], audioAssetId: '',
    durationMs: 0, source: '', contentScope: '', contentHash: '', lastPositionMs: 0, includeInRandomPractice: true };
  @State reading: boolean = false;
  @State menuVisible: boolean = false;
  @State importFormVisible: boolean = false;
  @State importMessage: string = '';
  @State importing: boolean = false;
  @State audioName: string = '';
  @State subtitleName: string = '';
  @State importTitle: string = '';
  @State importTopic: string = '本地导入';
  @State includeInRandom: boolean = true;
  @State expandedTranslations: number[] = [];
  @State playback: PlaybackSnapshot = { assetId: null, state: 'idle', positionMs: 0, durationMs: 0, speed: 1, errorCode: null };
  @State playing: boolean = false;
  @State randomMode: boolean = false;
  @State randomQueue: string[] = [];
  @State randomIndex: number = 0;
  @State activeIndex: number = -1;
  private audioRef: DocumentRef | null = null;
  private subtitleRef: DocumentRef | null = null;
  private unsubscribe: (() => void) | null = null;
  private paragraphScroller: Scroller = new Scroller();
  private lastSavedPosition: number = 0;

  aboutToAppear(): void {
    this.load();
    this.unsubscribe = appServices.audio.subscribe(value => {
      this.playback = value;
      if (value.assetId === this.current.audioAssetId) {
        if (value.durationMs > 0 && value.positionMs >= value.durationMs) this.playing = false;
        else if (value.state === 'playing') this.playing = true;
        else if (value.state === 'paused' || value.state === 'completed' || value.state === 'idle' || value.state === 'error') {
          this.playing = false;
        }
      }
      if (!this.reading || value.assetId !== this.current.audioAssetId) return;
      const index = this.findActiveParagraph(value.positionMs);
      if (index !== this.activeIndex) {
        this.activeIndex = index;
        if (index >= 0) this.paragraphScroller.scrollToIndex(index, true, ScrollAlign.CENTER);
      }
      if (Math.abs(value.positionMs - this.lastSavedPosition) >= 5000) {
        this.lastSavedPosition = value.positionMs;
        appServices.articles.saveProgress(this.current.id, value.positionMs, false);
      }
      if (value.state === 'completed') {
        appServices.articles.saveProgress(this.current.id, value.durationMs, true);
      }
    });
  }

  aboutToDisappear(): void { this.unsubscribe?.(); this.unsubscribe = null; }

  build() {
    if (this.reading) { this.playerView(); }
    else if (this.importFormVisible) { this.importForm(); }
    else { this.listView(); }
  }

  @Builder listView() {
    Column({ space: 12 }) {
      Row() {
        Text('文章 · 磨耳朵').fontSize(24).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary')).layoutWeight(1);
        Button({ type: ButtonType.Normal }) {
          Image($r('app.media.add')).width(24).height(24).objectFit(ImageFit.Contain);
        }.width(48).height(48).borderRadius(24).backgroundColor(Color.Transparent)
          .accessibilityText('导入文章').enabled(!this.importing).onClick(() => { this.menuVisible = !this.menuVisible; });
      }.width('100%');
      if (this.menuVisible) {
        Column() {
          Button('从音频导入').type(ButtonType.Normal).height(48).width('100%')
            .fontColor($r('app.color.text_primary')).backgroundColor(Color.Transparent).onClick(() => this.chooseAudio());
          Button('导入 .bessarticle 文章包').type(ButtonType.Normal).height(48).width('100%')
            .fontColor($r('app.color.text_primary')).backgroundColor(Color.Transparent).onClick(() => this.importPack());
          Divider().color($r('app.color.border'));
          Button('查看格式说明').type(ButtonType.Normal).height(48).width('100%')
            .fontColor($r('app.color.text_primary')).backgroundColor(Color.Transparent).onClick(() => this.showFormatHelp());
        }.padding(8).width('100%').backgroundColor($r('app.color.surface_container_high')).borderRadius(16);
      }

      Column({ space: 6 }) {
        Text('随机练习').fontSize(20).fontWeight(FontWeight.Medium).width('100%');
        Text('随机播放储能文章，整袋播放完前不会重复。').fontSize(14)
          .fontColor($r('app.color.text_secondary')).width('100%');
      }.alignItems(HorizontalAlign.Start).padding(16).width('100%')
        .backgroundColor($r('app.color.surface_container')).borderRadius(16).onClick(() => this.random());

      if (this.importMessage.length > 0) {
        Row({ space: 8 }) {
          Text(this.importMessage).fontSize(14).fontColor($r('app.color.text_primary')).layoutWeight(1);
          Button('关闭').type(ButtonType.Normal).height(48).fontColor($r('app.color.brand_primary'))
            .backgroundColor(Color.Transparent).onClick(() => { this.importMessage = ''; });
        }.padding(12).width('100%').backgroundColor($r('app.color.brand_primary_container')).borderRadius(16);
      }

      if (this.articles.length === 0) {
        Column({ space: 12 }) {
          Blank();
          Text('文章库为空。点击右上角 +，可直接导入音频。').fontSize(15)
            .fontColor($r('app.color.text_secondary')).textAlign(TextAlign.Center);
          Button('从音频导入').type(ButtonType.Normal).height(48)
            .fontColor($r('app.color.brand_primary')).backgroundColor(Color.Transparent)
            .border({ width: 1, color: $r('app.color.border') }).onClick(() => this.chooseAudio());
          Blank();
        }.layoutWeight(1).width('100%');
      } else {
        List({ space: 8 }) {
          ForEach(this.articles, (item: Article) => {
            ListItem() {
              Row({ space: 8 }) {
                Column({ space: 6 }) {
                  Text(item.title).fontSize(16).fontWeight(FontWeight.Medium).width('100%');
                  Text(`${item.topic} · ${this.duration(item.durationMs)}`).fontSize(13)
                    .fontColor($r('app.color.text_secondary')).width('100%');
                  if (item.durationMs > 0 && item.lastPositionMs > 0) {
                    Progress({ value: Math.min(item.lastPositionMs, item.durationMs), total: item.durationMs, type: ProgressType.Linear })
                      .height(4).width('100%').color($r('app.color.brand_primary'));
                  }
                }.alignItems(HorizontalAlign.Start).layoutWeight(1).onClick(() => this.openArticle(item, false));
                if (item.source === 'IMPORTED') {
                  Button({ type: ButtonType.Normal }) {
                    Image($r('app.media.delete')).width(24).height(24).objectFit(ImageFit.Contain);
                  }.width(48).height(48).backgroundColor(Color.Transparent).accessibilityText('删除导入文章')
                    .onClick(() => this.confirmDelete(item));
                }
              }.padding(16).width('100%').backgroundColor($r('app.color.surface_container')).borderRadius(16);
            }
          }, (item: Article) => item.id);
        }.layoutWeight(1).width('100%').edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true });
      }
    }.padding({ left: 16, right: 16, bottom: 12 }).width('100%').height('100%').transition(fadeTransition());
  }

  @Builder importForm() {
    Scroll() {
      Column({ space: 12 }) {
        Row() {
          Button('取消').type(ButtonType.Normal).height(48).fontColor($r('app.color.brand_primary'))
            .backgroundColor(Color.Transparent).enabled(!this.importing).onClick(() => this.dismissImport());
          Text('从音频导入文章').fontSize(22).fontWeight(FontWeight.Bold).layoutWeight(1).textAlign(TextAlign.End);
        }.width('100%');
        Text(this.audioName).fontSize(16).fontWeight(FontWeight.Medium).width('100%');
        Text('支持 M4A、MP3、WAV；音频上限 100MB、30 分钟。')
          .fontSize(13).fontColor($r('app.color.text_secondary')).width('100%');
        Text('标题（必填）').fontSize(14).fontWeight(FontWeight.Medium).width('100%');
        TextInput({ text: this.importTitle }).height(48).width('100%').onChange(value => { this.importTitle = value; });
        Text('主题').fontSize(14).fontWeight(FontWeight.Medium).width('100%');
        TextInput({ text: this.importTopic }).height(48).width('100%').onChange(value => { this.importTopic = value; });
        Divider().color($r('app.color.border'));
        Text('字幕（可选）').fontSize(16).fontWeight(FontWeight.Medium).width('100%');
        if (this.subtitleRef === null) {
          Button('添加 SRT / LRC').type(ButtonType.Normal).height(48)
            .fontColor($r('app.color.brand_primary')).backgroundColor(Color.Transparent)
            .border({ width: 1, color: $r('app.color.border') }).onClick(() => this.chooseSubtitle());
          Text('不添加字幕时，将保存为纯听练习。').fontSize(13)
            .fontColor($r('app.color.text_secondary')).width('100%');
        } else {
          Text(this.subtitleName).fontSize(14).width('100%');
          Row({ space: 8 }) {
            Button('替换').type(ButtonType.Normal).height(48).onClick(() => this.chooseSubtitle());
            Button('移除').type(ButtonType.Normal).height(48).fontColor($r('app.color.danger'))
              .backgroundColor(Color.Transparent).onClick(() => { this.subtitleRef = null; this.subtitleName = ''; });
          }
        }
        Row() {
          Column({ space: 2 }) {
            Text('加入随机练习').fontSize(16).width('100%');
            Text('关闭后仍可从文章列表手动播放').fontSize(13)
              .fontColor($r('app.color.text_secondary')).width('100%');
          }.alignItems(HorizontalAlign.Start).layoutWeight(1);
          Toggle({ type: ToggleType.Switch, isOn: this.includeInRandom })
            .onChange(value => { this.includeInRandom = value; });
        }.height(64).width('100%');
        Button(this.importing ? '导入中' : '确认导入').height(52).width('100%')
          .enabled(!this.importing && this.importTitle.trim().length > 0).onClick(() => this.submitImport());
      }.padding(20).width('100%').alignItems(HorizontalAlign.Start);
    }.width('100%').height('100%').edgeEffect(EdgeEffect.Spring).transition(fadeTransition());
  }

  @Builder playerView() {
    Column() {
      Row() {
        Button('返回').type(ButtonType.Normal).height(48).fontColor($r('app.color.brand_primary'))
          .backgroundColor(Color.Transparent).onClick(() => this.closePlayer());
        Text(this.randomMode ? '随机练习' : this.current.title).fontSize(18).fontWeight(FontWeight.Medium)
          .layoutWeight(1).textAlign(TextAlign.End).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      }.height(56).padding({ left: 8, right: 16 }).width('100%');

      if (this.current.paragraphs.length === 0) {
        Column({ space: 8 }) {
          Blank();
          Text('纯听练习').fontSize(24).fontWeight(FontWeight.Bold);
          Text('这篇文章没有字幕，请专注聆听音频。').fontSize(15)
            .fontColor($r('app.color.text_secondary')).textAlign(TextAlign.Center);
          Blank();
        }.layoutWeight(1).padding(24).width('100%');
      } else {
        List({ space: 8, scroller: this.paragraphScroller }) {
          ForEach(this.current.paragraphs, (paragraph: ArticleParagraph, index: number) => {
            ListItem() {
              Column({ space: 5 }) {
                Text(paragraph.textEn).fontSize(17).lineHeight(26)
                  .fontWeight(this.activeIndex === index ? FontWeight.Bold : FontWeight.Normal).width('100%');
                if (paragraph.textZh.length > 0 && this.expandedTranslations.includes(index)) {
                  Text(paragraph.textZh).fontSize(14).lineHeight(22)
                    .fontColor($r('app.color.text_secondary')).width('100%');
                }
              }.alignItems(HorizontalAlign.Start).padding(14).width('100%')
                .backgroundColor(this.activeIndex === index ? $r('app.color.brand_primary_container') : $r('app.color.surface_container'))
                .borderRadius(12).onClick(() => this.toggleTranslation(index, paragraph));
            }
          }, (_paragraph: ArticleParagraph, index: number) => `${this.current.id}-${index}`);
        }.layoutWeight(1).padding({ left: 16, right: 16 }).width('100%').edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true });
      }

      Column({ space: 4 }) {
        Text(this.current.title).fontSize(14).fontWeight(FontWeight.Medium).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%');
        Slider({ value: this.playback.assetId === this.current.audioAssetId ? this.playback.positionMs : this.current.lastPositionMs,
          min: 0, max: Math.max(1, this.playback.durationMs || this.current.durationMs), step: 1000 })
          .width('100%').onChange(value => { appServices.audio.seekTo(value); });
        Row({ space: 8 }) {
          Text(this.duration(this.playback.assetId === this.current.audioAssetId ? this.playback.positionMs : this.current.lastPositionMs))
            .fontSize(12).fontColor($r('app.color.text_secondary'));
          Blank();
          Text(this.duration(this.playback.durationMs || this.current.durationMs)).fontSize(12)
            .fontColor($r('app.color.text_secondary'));
        }.width('100%');
        Row({ space: 8 }) {
          Button(this.playback.assetId === this.current.audioAssetId && this.playing ? '暂停' : '播放')
            .layoutWeight(1).height(52).onClick(() => this.togglePlay());
          Button('下一篇').type(ButtonType.Normal).layoutWeight(1).height(52)
            .fontColor($r('app.color.brand_primary')).backgroundColor(Color.Transparent)
            .border({ width: 1, color: $r('app.color.border') }).onClick(() => this.nextArticle());
        }.width('100%');
      }.padding({ left: 16, right: 16, top: 10, bottom: 12 }).width('100%')
        .backgroundColor($r('app.color.surface_container_high'));
    }.width('100%').height('100%').transition(fadeTransition());
  }

  private async load(): Promise<void> { try { this.articles = await appServices.articles.list(); } catch (error) { this.toast(error); } }

  private async chooseAudio(): Promise<void> {
    this.menuVisible = false; const source = await fileService.pickOpen(['.m4a', '.mp3', '.wav']); if (source === null) return;
    this.audioRef = source; this.audioName = fileService.displayName(source);
    this.importTitle = this.audioName.replace(new RegExp('\\.[^.]+$'), ''); this.subtitleRef = null; this.subtitleName = '';
    this.importFormVisible = true; this.detailMode = true;
  }

  private async chooseSubtitle(): Promise<void> {
    const source = await fileService.pickOpen(['.srt', '.lrc']); if (source === null) return;
    this.subtitleRef = source; this.subtitleName = fileService.displayName(source);
  }

  private dismissImport(): void {
    this.audioRef = null; this.subtitleRef = null; this.importFormVisible = false; this.detailMode = false;
  }

  private async submitImport(): Promise<void> {
    if (this.audioRef === null) return;
    try {
      this.importing = true;
      const result = await appServices.articles.importAudio(this.audioRef, this.subtitleRef, this.audioName,
        this.subtitleName, this.importTitle, this.importTopic, this.includeInRandom);
      this.importMessage = result.message;
      if (result.ok) { this.dismissImport(); await this.load(); }
    } catch (error) { this.importMessage = shortError(error); }
    finally { this.importing = false; }
  }

  private async importPack(): Promise<void> {
    this.menuVisible = false; const source = await fileService.pickOpen(['.bessarticle']); if (source === null) return;
    const result = await appServices.articles.importPackage(source); this.importMessage = result.message; await this.load();
  }

  private showFormatHelp(): void {
    this.menuVisible = false;
    AlertDialog.show({ title: '文章导入格式',
      message: '普通导入：选择 M4A、MP3 或 WAV 音频，可再添加 SRT/LRC 字幕。音频上限 100MB、30 分钟；字幕上限 2MB、10,000 条，使用 UTF-8 编码。\n\n高级导入：.bessarticle 用于批量发布和内置语料。',
      confirm: { value: '关闭', action: () => {} } });
  }

  private confirmDelete(item: Article): void {
    AlertDialog.show({ title: '删除这篇导入文章？', message: `“${item.title}”及其本地音频和收听进度将被删除，无法撤销。`,
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '删除', fontColor: $r('app.color.danger'), action: () => { this.remove(item); } } });
  }

  private async remove(item: Article): Promise<void> {
    const result = await appServices.articles.deleteImported(item.id); this.importMessage = result.message; await this.load();
  }

  private async random(): Promise<void> {
    this.randomQueue = await appServices.articles.randomIds(); this.randomIndex = 0;
    if (this.randomQueue.length === 0) { this.importMessage = '没有可用于随机练习的文章'; return; }
    const article = await appServices.articles.get(this.randomQueue[0]); if (article !== null) this.openArticle(article, true);
  }

  private openArticle(article: Article, random: boolean): void {
    this.current = article; this.reading = true; this.randomMode = random; this.detailMode = true;
    this.expandedTranslations = []; this.activeIndex = -1; this.lastSavedPosition = article.lastPositionMs; this.playing = false;
  }

  private async togglePlay(): Promise<void> {
    try {
      if (this.playback.assetId !== this.current.audioAssetId) {
        const settings = await appServices.settings.get(); await appServices.audio.play(this.current.audioAssetId, settings.playbackSpeed);
        if (this.current.lastPositionMs > 0 && this.current.lastPositionMs < this.current.durationMs - 1000) {
          await appServices.audio.seekTo(this.current.lastPositionMs);
        } else if (this.current.lastPositionMs >= this.current.durationMs - 1000) {
          await appServices.audio.seekTo(0);
        }
        this.playing = true;
      } else if (this.playing) {
        await appServices.audio.pause(); this.playing = false;
      } else {
        await appServices.audio.resume(); this.playing = true;
      }
    } catch (error) { this.playing = false; this.toast(error); }
  }

  private async closePlayer(): Promise<void> {
    const position = this.playback.assetId === this.current.audioAssetId ? this.playback.positionMs : this.current.lastPositionMs;
    await appServices.articles.saveProgress(this.current.id, position, false); await appServices.audio.stop();
    this.reading = false; this.randomMode = false; this.detailMode = false; this.playing = false; await this.load();
  }

  private async nextArticle(): Promise<void> {
    try {
      const position = this.playback.assetId === this.current.audioAssetId ? this.playback.positionMs : this.current.lastPositionMs;
      await appServices.articles.saveProgress(this.current.id, position, false); await appServices.audio.stop(); this.playing = false;
      let nextId: string | null = null;
      if (this.randomMode) {
        this.randomIndex++;
        if (this.randomIndex >= this.randomQueue.length) { this.randomQueue = await appServices.articles.randomIds(); this.randomIndex = 0; }
        nextId = this.randomQueue[this.randomIndex] ?? null;
      } else {
        const index = this.articles.findIndex(item => item.id === this.current.id);
        if (this.articles.length > 0) nextId = this.articles[(index + 1 + this.articles.length) % this.articles.length].id;
      }
      if (nextId !== null) {
        const article = await appServices.articles.get(nextId);
        if (article !== null) this.openArticle(article, this.randomMode);
      } else {
        this.toast('没有可切换的下一篇');
      }
    } catch (error) {
      this.toast(error);
    }
  }

  private toggleTranslation(index: number, paragraph: ArticleParagraph): void {
    if (paragraph.startMs !== null) appServices.audio.seekTo(paragraph.startMs);
    if (paragraph.textZh.length === 0) return;
    this.expandedTranslations = this.expandedTranslations.includes(index) ?
      this.expandedTranslations.filter(value => value !== index) : this.expandedTranslations.concat(index);
  }

  private findActiveParagraph(positionMs: number): number {
    return this.current.paragraphs.findIndex(item => item.startMs !== null && positionMs >= item.startMs && positionMs < (item.endMs ?? Number.MAX_SAFE_INTEGER));
  }

  private duration(ms: number): string {
    const seconds = Math.max(0, Math.floor(ms / 1000));
    return `${Math.floor(seconds / 60).toString().padStart(2, '0')}:${(seconds % 60).toString().padStart(2, '0')}`;
  }

  private toast(error: Object): void { promptAction.showToast({ message: shortError(error) }); }
}
