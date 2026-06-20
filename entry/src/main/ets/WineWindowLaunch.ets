import { Want } from '@kit.AbilityKit'

export const MAIN_ABILITY_NAME: string = 'MainAbility'
export const FULL_DESKTOP_ABILITY_NAME: string = 'WineFullWindowsDesktopExperienceAbility'
export const STANDALONE_WINDOW_ABILITY_NAME: string = 'WineStandaloneWindowAbility'
export const DEFAULT_FULL_DESKTOP_WINDOW_ID: string = 'wine-desktop-default'
export const DEFAULT_FULL_DESKTOP_PREFIX: string = 'wine-desktop-win11'
export const DEFAULT_FULL_DESKTOP_ARGS: string[] = [
  '/desktop=shell,896x640'
]

export interface WineWindowRequest {
  windowId: string
  sessionId: string
  profileId: string
  kind: string
  label: string
  rawRoot: string
  targetName: string
  executableName: string
  prefixName: string
  args: string[]
  autoLaunch: boolean
}

type WineWindowRequestListener = (request: WineWindowRequest) => void

let currentRequest: WineWindowRequest = defaultWineWindowRequest()
let listeners: WineWindowRequestListener[] = []

export function defaultFullWineDesktopRequest(): WineWindowRequest {
  return {
    windowId: DEFAULT_FULL_DESKTOP_WINDOW_ID,
    sessionId: '',
    profileId: '',
    kind: 'desktop',
    label: 'Wine Desktop',
    rawRoot: '',
    targetName: '',
    executableName: 'explorer.exe',
    prefixName: DEFAULT_FULL_DESKTOP_PREFIX,
    args: DEFAULT_FULL_DESKTOP_ARGS.slice(),
    autoLaunch: true
  }
}

export function defaultStandaloneWineWindowRequest(): WineWindowRequest {
  return {
    windowId: `standalone-window-${Date.now()}`,
    sessionId: '',
    profileId: '',
    kind: 'standalone-window',
    label: 'Wine App',
    rawRoot: '',
    targetName: '',
    executableName: '',
    prefixName: 'default',
    args: [],
    autoLaunch: true
  }
}

export function defaultWineWindowRequest(): WineWindowRequest {
  return defaultFullWineDesktopRequest()
}

function wantString(want: Want, key: string, fallback: string): string {
  const parameters = want.parameters
  if (!parameters) {
    return fallback
  }
  const value = parameters[key]
  return typeof value === 'string' && value.length > 0 ? value : fallback
}

function wantBoolean(want: Want, key: string, fallback: boolean): boolean {
  const parameters = want.parameters
  if (!parameters) {
    return fallback
  }
  const value = parameters[key]
  if (typeof value === 'boolean') {
    return value
  }
  if (typeof value === 'string') {
    return value === 'true'
  }
  return fallback
}

function stringArrayFromAny(value: Object | string | string[] | undefined, fallback: string[]): string[] {
  if (value === undefined) {
    return fallback.slice()
  }
  if (typeof value === 'string') {
    return parseArgsString(value, fallback)
  }
  if (Array.isArray(value)) {
    const items: string[] = []
    for (let i = 0; i < value.length; i++) {
      if (typeof value[i] === 'string') {
        items.push(value[i])
      }
    }
    return items
  }
  return fallback.slice()
}

function parseArgsString(value: string, fallback: string[]): string[] {
  if (value.length === 0) {
    return fallback.slice()
  }
  try {
    const parsed = JSON.parse(value) as Object
    if (Array.isArray(parsed)) {
      const items: string[] = []
      for (let i = 0; i < parsed.length; i++) {
        if (typeof parsed[i] === 'string') {
          items.push(parsed[i])
        }
      }
      return items
    }
  } catch (_) {
  }
  return value.split('\u001f').filter((item: string): boolean => item.length > 0)
}

function wantStringArray(want: Want, key: string, fallback: string[]): string[] {
  const parameters = want.parameters
  if (!parameters) {
    return fallback.slice()
  }
  return stringArrayFromAny(parameters[key] as Object | string | string[] | undefined, fallback)
}

function uriQueryValue(uri: string, key: string, fallback: string): string {
  const queryIndex = uri.indexOf('?')
  if (queryIndex < 0 || queryIndex + 1 >= uri.length) {
    return fallback
  }
  const query = uri.substring(queryIndex + 1)
  const items = query.split('&')
  for (let i = 0; i < items.length; i++) {
    const pair = items[i]
    const splitIndex = pair.indexOf('=')
    if (splitIndex <= 0) {
      continue
    }
    const itemKey = decodeURIComponent(pair.substring(0, splitIndex))
    if (itemKey === key) {
      return decodeURIComponent(pair.substring(splitIndex + 1))
    }
  }
  return fallback
}

function uriQueryBoolean(uri: string, key: string, fallback: boolean): boolean {
  const value = uriQueryValue(uri, key, fallback ? 'true' : 'false')
  return value === 'true'
}

function uriQueryStringArray(uri: string, key: string, fallback: string[]): string[] {
  return parseArgsString(uriQueryValue(uri, key, ''), fallback)
}

export function buildWineWindowUri(request: WineWindowRequest): string {
  return `winewindow://launch?windowId=${encodeURIComponent(request.windowId)}` +
    `&sessionId=${encodeURIComponent(request.sessionId)}` +
    `&profileId=${encodeURIComponent(request.profileId)}` +
    `&kind=${encodeURIComponent(request.kind)}` +
    `&label=${encodeURIComponent(request.label)}` +
    `&rawRoot=${encodeURIComponent(request.rawRoot)}` +
    `&targetName=${encodeURIComponent(request.targetName)}` +
    `&executableName=${encodeURIComponent(request.executableName)}` +
    `&prefixName=${encodeURIComponent(request.prefixName)}` +
    `&args=${encodeURIComponent(JSON.stringify(request.args))}` +
    `&autoLaunch=${request.autoLaunch ? 'true' : 'false'}`
}

export function wineWindowRequestFromWant(want: Want, fallback: WineWindowRequest = defaultWineWindowRequest()): WineWindowRequest {
  if (want.uri && want.uri.length > 0) {
    return {
      windowId: uriQueryValue(want.uri, 'windowId', fallback.windowId),
      sessionId: uriQueryValue(want.uri, 'sessionId', fallback.sessionId),
      profileId: uriQueryValue(want.uri, 'profileId', fallback.profileId),
      kind: uriQueryValue(want.uri, 'kind', fallback.kind),
      label: uriQueryValue(want.uri, 'label', fallback.label),
      rawRoot: uriQueryValue(want.uri, 'rawRoot', fallback.rawRoot),
      targetName: uriQueryValue(want.uri, 'targetName', fallback.targetName),
      executableName: uriQueryValue(want.uri, 'executableName', fallback.executableName),
      prefixName: uriQueryValue(want.uri, 'prefixName', fallback.prefixName),
      args: uriQueryStringArray(want.uri, 'args', fallback.args),
      autoLaunch: uriQueryBoolean(want.uri, 'autoLaunch', fallback.autoLaunch)
    }
  }
  return {
    windowId: wantString(want, 'windowId', fallback.windowId),
    sessionId: wantString(want, 'sessionId', fallback.sessionId),
    profileId: wantString(want, 'profileId', fallback.profileId),
    kind: wantString(want, 'kind', fallback.kind),
    label: wantString(want, 'label', fallback.label),
    rawRoot: wantString(want, 'rawRoot', fallback.rawRoot),
    targetName: wantString(want, 'targetName', fallback.targetName),
    executableName: wantString(want, 'executableName', fallback.executableName),
    prefixName: wantString(want, 'prefixName', fallback.prefixName),
    args: wantStringArray(want, 'args', fallback.args),
    autoLaunch: wantBoolean(want, 'autoLaunch', fallback.autoLaunch)
  }
}

export function setWineWindowRequest(request: WineWindowRequest): void {
  currentRequest = request
  const snapshot = listeners.slice()
  for (let i = 0; i < snapshot.length; i++) {
    snapshot[i](request)
  }
}

export function getWineWindowRequest(): WineWindowRequest {
  return currentRequest
}

export function onWineWindowRequest(listener: WineWindowRequestListener): () => void {
  listeners.push(listener)
  return (): void => {
    const index = listeners.indexOf(listener)
    if (index >= 0) {
      listeners.splice(index, 1)
    }
  }
}
