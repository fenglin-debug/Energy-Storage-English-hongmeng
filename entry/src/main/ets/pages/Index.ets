import { appServices } from '../ability/AppServices';
import { VocabularyPage } from '../features/vocabulary/VocabularyPage';
import { ScenarioPage } from '../features/scenario/ScenarioPage';
import { ArticlePage } from '../features/article/ArticlePage';
import { SettingsPage } from '../features/settings/SettingsPage';
import { fadeTransition } from '../ui/TransitionUtil';

@Entry
@Component
struct Index {
  @State selectedTab: number = 0;
  @State settingsVisible: boolean = false;
  @StorageLink('detailMode') detailMode: boolean = false;

  onBackPress(): boolean {
    if (this.settingsVisible) {
      this.settingsVisible = false;
      return true;
    }
    return false;
  }

  build() {
    Column() {
      if (!appServices.initialized) {
        Column({ space: 16 }) {
          Text('BESS 无法安全启动').fontSize(24).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.danger'));
          Text('数据库版本过高、内置资源校验失败或初始化异常。应用不会重建或清空现有数据。')
            .fontSize(16).fontColor($r('app.color.text_secondary')).textAlign(TextAlign.Center);
          Text(appServices.initializationError ?? 'INIT_FAILED').fontSize(13)
            .fontColor($r('app.color.text_secondary')).textAlign(TextAlign.Center);
        }.justifyContent(FlexAlign.Center).padding(24).width('100%').height('100%')
          .backgroundColor($r('app.color.surface_muted'));
      } else if (this.settingsVisible) {
        Column() {
          Row({ space: 8 }) {
            Button('返回').type(ButtonType.Normal).height(48).fontColor($r('app.color.brand_primary'))
              .backgroundColor(Color.Transparent).onClick(() => { this.settingsVisible = false; });
            Text('设置').fontSize(24).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'));
          }.height(64).padding({ left: 8, right: 16 }).width('100%');
          SettingsPage().layoutWeight(1);
        }.width('100%').height('100%').transition(fadeTransition());
      } else {
        Column() {
          if (!this.detailMode) {
            Row() {
              Text(this.title()).fontSize(24).fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary')).layoutWeight(1);
              Button({ type: ButtonType.Normal }) {
                Image($r('app.media.settings')).width(24).height(24).objectFit(ImageFit.Contain);
              }.width(48).height(48).borderRadius(24).backgroundColor(Color.Transparent)
                .accessibilityText('设置').onClick(() => { this.settingsVisible = true; });
            }.height(64).padding({ left: 16, right: 8 }).width('100%').transition(fadeTransition());
          }

          if (this.selectedTab === 0) {
            Column() { VocabularyPage(); }.layoutWeight(1).transition(fadeTransition());
          } else if (this.selectedTab === 1) {
            Column() { ScenarioPage(); }.layoutWeight(1).transition(fadeTransition());
          } else {
            Column() { ArticlePage(); }.layoutWeight(1).transition(fadeTransition());
          }

          if (!this.detailMode) {
            Row({ space: 8 }) {
            Button({ type: ButtonType.Normal }) {
              Column({ space: 2 }) {
                Image($r('app.media.nav_vocabulary')).width(24).height(24).objectFit(ImageFit.Contain);
                Text('词汇').fontSize(12).fontWeight(this.selectedTab === 0 ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(this.selectedTab === 0 ? $r('app.color.brand_primary') : $r('app.color.text_secondary'));
              }
            }.layoutWeight(1).height(64).borderRadius(20)
              .backgroundColor(this.selectedTab === 0 ? $r('app.color.brand_primary_container') : Color.Transparent)
              .accessibilityText('词汇').onClick(() => { this.selectedTab = 0; });
            Button({ type: ButtonType.Normal }) {
              Column({ space: 2 }) {
                Image($r('app.media.nav_scenario')).width(24).height(24).objectFit(ImageFit.Contain);
                Text('情景').fontSize(12).fontWeight(this.selectedTab === 1 ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(this.selectedTab === 1 ? $r('app.color.brand_primary') : $r('app.color.text_secondary'));
              }
            }.layoutWeight(1).height(64).borderRadius(20)
              .backgroundColor(this.selectedTab === 1 ? $r('app.color.brand_primary_container') : Color.Transparent)
              .accessibilityText('情景').onClick(() => { this.selectedTab = 1; });
            Button({ type: ButtonType.Normal }) {
              Column({ space: 2 }) {
                Image($r('app.media.nav_article')).width(24).height(24).objectFit(ImageFit.Contain);
                Text('文章').fontSize(12).fontWeight(this.selectedTab === 2 ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(this.selectedTab === 2 ? $r('app.color.brand_primary') : $r('app.color.text_secondary'));
              }
            }.layoutWeight(1).height(64).borderRadius(20)
              .backgroundColor(this.selectedTab === 2 ? $r('app.color.brand_primary_container') : Color.Transparent)
              .accessibilityText('文章').onClick(() => { this.selectedTab = 2; });
            }.height(72).padding({ left: 8, right: 8, top: 4, bottom: 4 }).width('100%')
              .backgroundColor($r('app.color.surface_container')).transition(fadeTransition());
          }
        }.width('100%').height('100%');
      }
    }.width('100%').height('100%').backgroundColor($r('app.color.surface_muted'));
  }

  private title(): string {
    if (this.selectedTab === 0) return '词汇';
    if (this.selectedTab === 1) return '情景';
    return '文章';
  }
}
