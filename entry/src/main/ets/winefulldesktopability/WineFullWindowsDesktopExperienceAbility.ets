import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { window } from '@kit.ArkUI'
import * as Proton from 'proton'
import {
  defaultFullWineDesktopRequest,
  setWineWindowRequest,
  wineWindowRequestFromWant
} from '../WineWindowLaunch'

const DOMAIN = 0x2330
const TAG = 'WineFullDesktop'

export default class WineFullWindowsDesktopExperienceAbility extends UIAbility {
  private applyWant(want: Want): void {
    Proton.configureHostContext(this.context)
    setWineWindowRequest(wineWindowRequestFromWant(want, defaultFullWineDesktopRequest()))
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET)
      this.applyWant(want)
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'onCreate failed: %{public}s', JSON.stringify(err))
    }
    hilog.info(DOMAIN, TAG, 'WineFullWindowsDesktopExperienceAbility onCreate')
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.applyWant(want)
    hilog.info(DOMAIN, TAG, 'WineFullWindowsDesktopExperienceAbility onNewWant')
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'WineFullWindowsDesktopExperienceAbility onDestroy')
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, 'WineFullWindowsDesktopExperienceAbility onWindowStageCreate')
    windowStage.loadContent('pages/WineWindow', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'load WineWindow failed: %{public}s', JSON.stringify(err))
        return
      }
      hilog.info(DOMAIN, TAG, 'Wine full desktop page loaded')
    })
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'WineFullWindowsDesktopExperienceAbility onWindowStageDestroy')
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'WineFullWindowsDesktopExperienceAbility onForeground')
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'WineFullWindowsDesktopExperienceAbility onBackground')
  }
}
