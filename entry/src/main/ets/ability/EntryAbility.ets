import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { appServices } from './AppServices';

export default class EntryAbility extends UIAbility {
  onCreate(_want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'BESS', 'EntryAbility created');
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    try {
      await appServices.initialize(this.context);
    } catch (error) {
      hilog.error(0x0000, 'BESS', 'Initialization failed: %{public}s', String(error));
    }
    await windowStage.loadContent('pages/Index');
  }

  async onDestroy(): Promise<void> {
    if (appServices.initialized) await appServices.audio.stop();
  }
}
