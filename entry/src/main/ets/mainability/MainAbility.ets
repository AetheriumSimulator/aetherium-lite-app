import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { window } from '@kit.ArkUI'
import * as Proton from 'proton'
import { setAutoStageRuntime } from '../AutoStage'

const DOMAIN = 0x2330
const TAG = 'MainAbility'

function wantBoolean(want: Want, key: string): boolean {
  const parameters = want.parameters
  if (!parameters) {
    return false
  }
  const value = parameters[key]
  return value === true || value === 'true'
}

export default class MainAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET)
      Proton.configureHostContext(this.context)
      setAutoStageRuntime(wantBoolean(want, 'autoStageRuntime'))
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'onCreate failed: %{public}s', JSON.stringify(err))
    }
    hilog.info(DOMAIN, TAG, 'MainAbility onCreate')
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    setAutoStageRuntime(wantBoolean(want, 'autoStageRuntime'))
    Proton.configureHostContext(this.context)
    hilog.info(DOMAIN, TAG, 'MainAbility onNewWant')
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'MainAbility onDestroy')
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, 'MainAbility onWindowStageCreate')
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'load Index failed: %{public}s', JSON.stringify(err))
        return
      }
      hilog.info(DOMAIN, TAG, 'Index page loaded')
    })
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'MainAbility onWindowStageDestroy')
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'MainAbility onForeground')
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'MainAbility onBackground')
  }
}
