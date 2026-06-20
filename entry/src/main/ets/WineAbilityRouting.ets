import common from '@ohos.app.ability.common'
import {
  buildWineWindowUri,
  defaultFullWineDesktopRequest,
  FULL_DESKTOP_ABILITY_NAME,
  MAIN_ABILITY_NAME,
  STANDALONE_WINDOW_ABILITY_NAME,
  WineWindowRequest
} from './WineWindowLaunch'

const BUNDLE_NAME: string = 'com.caidingding233.genohinimbact'

class WineAbilityWant {
  bundleName: string = BUNDLE_NAME
  abilityName: string = ''
  uri: string = ''
}

class MainAbilityWant {
  bundleName: string = BUNDLE_NAME
  abilityName: string = MAIN_ABILITY_NAME
}

function startWineAbility(context: common.UIAbilityContext, abilityName: string, request: WineWindowRequest): Promise<void> {
  const want = new WineAbilityWant()
  want.abilityName = abilityName
  want.uri = buildWineWindowUri(request)
  return context.startSelfUIAbilityInCurrentProcess(want, request.windowId)
}

export function launchFullWineDesktop(context: common.UIAbilityContext, request: WineWindowRequest = defaultFullWineDesktopRequest()): Promise<void> {
  return startWineAbility(context, FULL_DESKTOP_ABILITY_NAME, request)
}

export function launchStandaloneWineWindow(context: common.UIAbilityContext, request: WineWindowRequest): Promise<void> {
  return startWineAbility(context, STANDALONE_WINDOW_ABILITY_NAME, request)
}

export function openMainHome(context: common.UIAbilityContext): Promise<void> {
  return context.startSelfUIAbilityInCurrentProcess(new MainAbilityWant(), `main-home-${Date.now()}`)
}
