import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { window } from '@kit.ArkUI'
import * as Proton from 'proton'
import { setWineWindowRequest, wineWindowRequestFromWant } from '../WineWindowLaunch'

const DOMAIN = 0x2330

export default class WineWindowAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET)
      Proton.configureHostContext(this.context)
      setWineWindowRequest(wineWindowRequestFromWant(want))
    } catch (err) {
      hilog.error(DOMAIN, 'WineWindowAbility', 'onCreate failed: %{public}s', JSON.stringify(err))
    }
    hilog.info(DOMAIN, 'WineWindowAbility', 'WineWindowAbility onCreate')
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    Proton.configureHostContext(this.context)
    setWineWindowRequest(wineWindowRequestFromWant(want))
    hilog.info(DOMAIN, 'WineWindowAbility', 'WineWindowAbility onNewWant')
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'WineWindowAbility', 'WineWindowAbility onDestroy')
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'WineWindowAbility', 'WineWindowAbility onWindowStageCreate')
    windowStage.loadContent('pages/WineWindow', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'WineWindowAbility', 'load WineWindow failed: %{public}s', JSON.stringify(err))
        return
      }
      hilog.info(DOMAIN, 'WineWindowAbility', 'WineWindow page loaded')
    })
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'WineWindowAbility', 'WineWindowAbility onWindowStageDestroy')
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'WineWindowAbility', 'WineWindowAbility onForeground')
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'WineWindowAbility', 'WineWindowAbility onBackground')
  }
}
