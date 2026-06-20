import promptAction from '@ohos.promptAction'
import inputMethod from '@ohos.inputMethod'
import fs from '@ohos.file.fs'
import { hilog } from '@kit.PerformanceAnalysisKit'
import * as Proton from 'proton'
import { writeExplorerPatchFile, writeNtdllPatchFile, writeRuntimePatchFile, writeWin32uPatchFile } from 'libentry.so'
import { defaultWineWindowRequest, getWineWindowRequest, onWineWindowRequest, WineWindowRequest } from '../WineWindowLaunch'

const DOMAIN = 0x2330
const ENABLE_WINE_UI_DIAGNOSTIC_LOGS: boolean = false
const ENABLE_EXPLORER_STATUS_POLL: boolean = true
const ENABLE_WINE_STATUS_HILOG: boolean = true
const WINE_RENDER_ACTIVE_INTERVAL_MS: number = 16
const WINE_RENDER_IDLE_INTERVAL_MS: number = 96
const WINE_RENDER_ACTIVE_TICKS: number = 36
const WINE_BROKER_IDLE_INTERVAL_MS: number = 500
const WINE_BROKER_INPUT_WAKE_DELAY_MS: number = 0
const WINE_BROKER_DRAIN_BATCH: number = 12
const ENTRY_HMOS_FONT_DIRS: string[] = [
  '/system/fonts',
  '/data/themes/fonts',
  '/data/service/el1/public/fonts',
  '/data/service/el1/public/themes'
]
const ENTRY_HMOS_UI_FONT: string = 'HarmonyOS Sans'
const ENTRY_HMOS_CJK_FONT: string = 'HarmonyOS Sans SC'
const ENTRY_HMOS_FONT_SCAN_LIMIT: number = 768
const ENTRY_HMOS_UI_ALIASES: string[] = [
  'Arial',
  'Calibri',
  'Cambria',
  'Helvetica',
  'Helv',
  'MS Sans Serif',
  'MS Shell Dlg',
  'MS Shell Dlg 2',
  'Segoe UI',
  'Segoe UI Semibold',
  'Segoe UI Symbol',
  'Tahoma',
  'Times New Roman',
  'Verdana'
]
const ENTRY_HMOS_CJK_ALIASES: string[] = [
  'DengXian',
  'Microsoft JhengHei',
  'Microsoft JhengHei UI',
  'Microsoft YaHei',
  'Microsoft YaHei UI',
  'MingLiU',
  'MS Gothic',
  'MS PGothic',
  'Malgun Gothic',
  'Meiryo',
  'NSimSun',
  'PMingLiU',
  'SimHei',
  'SimSun',
  'Yu Gothic'
]
const ENTRY_HMOS_FONT_REGISTRY_FILES: string[][] = [
  ['HarmonyOS Sans (TrueType)', 'HarmonyOS_Sans.ttf'],
  ['HarmonyOS Sans SC (TrueType)', 'HarmonyOS_Sans_SC.ttf'],
  ['HarmonyOS Sans TC (TrueType)', 'HarmonyOS_Sans_TC.ttf'],
  ['HarmonyOS Color Emoji (TrueType)', 'HMOSColorEmojiCompat.ttf'],
  ['Noto Sans CJK Regular (TrueType)', 'NotoSansCJK-Regular.ttc']
]

interface EntryFontSyncResult {
  linked: number
  copied: number
  skipped: number
  registryPatched: number
}

function entryJoinPath(left: string, right: string): string {
  return left.endsWith('/') ? `${left}${right}` : `${left}/${right}`
}

function entryParentDir(path: string): string {
  const idx = Math.max(path.lastIndexOf('/'), path.lastIndexOf('\\'))
  return idx <= 0 ? path : path.substring(0, idx)
}

function entryLeafName(path: string): string {
  const idx = Math.max(path.lastIndexOf('/'), path.lastIndexOf('\\'))
  return idx < 0 ? path : path.substring(idx + 1)
}

function entryEnsureDir(path: string): void {
  try {
    fs.mkdirSync(path, true)
  } catch (_) {
  }
}

function entryReadText(path: string): string {
  return fs.readTextSync(path)
}

function entryWriteText(path: string, content: string): void {
  entryEnsureDir(entryParentDir(path))
  const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC)
  try {
    fs.writeSync(file.fd, content)
  } finally {
    fs.closeSync(file)
  }
}

function entryAppendText(path: string, content: string): void {
  entryEnsureDir(entryParentDir(path))
  const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.APPEND)
  try {
    fs.writeSync(file.fd, content)
  } finally {
    fs.closeSync(file)
  }
}

function entryFileExists(path: string): boolean {
  try {
    fs.statSync(path)
    return true
  } catch (_) {
    return false
  }
}

function entryIsDir(path: string): boolean {
  try {
    return fs.statSync(path).isDirectory()
  } catch (_) {
    return false
  }
}

function entryIsFile(path: string): boolean {
  try {
    return fs.statSync(path).isFile()
  } catch (_) {
    return false
  }
}

function entryList(path: string): string[] {
  try {
    return fs.listFileSync(path)
  } catch (_) {
    return []
  }
}

function entryIsFont(path: string): boolean {
  const lower = path.toLowerCase()
  return lower.endsWith('.ttf') || lower.endsWith('.ttc') || lower.endsWith('.otf')
}

function entryCollectFonts(root: string, depth: number, paths: string[]): void {
  if (depth < 0 || paths.length >= ENTRY_HMOS_FONT_SCAN_LIMIT || !entryIsDir(root)) {
    return
  }
  const names = entryList(root)
  for (let i = 0; i < names.length && paths.length < ENTRY_HMOS_FONT_SCAN_LIMIT; i++) {
    const child = entryJoinPath(root, names[i])
    if (entryIsFile(child) && entryIsFont(child) && paths.indexOf(child) < 0) {
      paths.push(child)
    }
  }
  for (let i = 0; i < names.length && paths.length < ENTRY_HMOS_FONT_SCAN_LIMIT; i++) {
    const child = entryJoinPath(root, names[i])
    if (entryIsDir(child)) {
      entryCollectFonts(child, depth - 1, paths)
    }
  }
}

function entryLinkOrCopyFont(source: string, target: string): string {
  try {
    const existing = fs.lstatSync(target)
    if (existing.isSymbolicLink()) {
      fs.unlinkSync(target)
    } else {
      return 'skipped'
    }
  } catch (_) {
  }
  entryEnsureDir(entryParentDir(target))
  try {
    fs.symlinkSync(source, target)
    return 'linked'
  } catch (_) {
    try {
      fs.copyFileSync(source, target)
      return 'copied'
    } catch (_) {
      return 'skipped'
    }
  }
}

function entryUpsertRegString(regPath: string, sectionName: string, key: string, value: string): boolean {
  const header = `[${sectionName}]`
  const entry = `"${key}"="${value}"`
  const block = `\n${header} ${Date.now()}\n${entry}\n`
  if (!entryFileExists(regPath)) {
    entryWriteText(regPath, `WINE REGISTRY Version 2\n\n#arch=win64\n${block}`)
    return true
  }
  const content = entryReadText(regPath)
  const sectionIndex = content.indexOf(header)
  if (sectionIndex < 0) {
    entryAppendText(regPath, block)
    return true
  }
  const nextSectionIndex = content.indexOf('\n[', sectionIndex + 1)
  const before = content.substring(0, sectionIndex)
  const section = nextSectionIndex >= 0 ? content.substring(sectionIndex, nextSectionIndex) : content.substring(sectionIndex)
  const after = nextSectionIndex >= 0 ? content.substring(nextSectionIndex) : ''
  const escapedKey = key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
  const valuePattern = new RegExp(`"${escapedKey}"="[^"]*"`)
  const patchedSection = valuePattern.test(section) ? section.replace(valuePattern, entry) : `${section.trimEnd()}\n${entry}\n`
  const patched = `${before}${patchedSection}${after}`
  if (patched === content) {
    return false
  }
  entryWriteText(regPath, patched)
  return true
}

function entryUpsertRegDword(regPath: string, sectionName: string, key: string, value: number): boolean {
  const header = `[${sectionName}]`
  const entry = `"${key}"=dword:${Math.max(0, value).toString(16).padStart(8, '0')}`
  const block = `\n${header} ${Date.now()}\n${entry}\n`
  if (!entryFileExists(regPath)) {
    entryWriteText(regPath, `WINE REGISTRY Version 2\n\n#arch=win64\n${block}`)
    return true
  }
  const content = entryReadText(regPath)
  const sectionIndex = content.indexOf(header)
  if (sectionIndex < 0) {
    entryAppendText(regPath, block)
    return true
  }
  const nextSectionIndex = content.indexOf('\n[', sectionIndex + 1)
  const before = content.substring(0, sectionIndex)
  const section = nextSectionIndex >= 0 ? content.substring(sectionIndex, nextSectionIndex) : content.substring(sectionIndex)
  const after = nextSectionIndex >= 0 ? content.substring(nextSectionIndex) : ''
  const escapedKey = key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
  const valuePattern = new RegExp(`"${escapedKey}"=dword:[0-9A-Fa-f]+`)
  const patchedSection = valuePattern.test(section) ? section.replace(valuePattern, entry) : `${section.trimEnd()}\n${entry}\n`
  const patched = `${before}${patchedSection}${after}`
  if (patched === content) {
    return false
  }
  entryWriteText(regPath, patched)
  return true
}

function ensureEntryHmosFonts(prefixPath: string): EntryFontSyncResult {
  const result: EntryFontSyncResult = { linked: 0, copied: 0, skipped: 0, registryPatched: 0 }
  const fontsDir = entryJoinPath(prefixPath, 'drive_c/windows/Fonts')
  const userReg = entryJoinPath(prefixPath, 'user.reg')
  const systemReg = entryJoinPath(prefixPath, 'system.reg')
  const sources: string[] = []
  entryEnsureDir(fontsDir)
  for (let i = 0; i < ENTRY_HMOS_FONT_DIRS.length; i++) {
    entryCollectFonts(ENTRY_HMOS_FONT_DIRS[i], 4, sources)
  }
  for (let i = 0; i < sources.length; i++) {
    const target = entryJoinPath(fontsDir, entryLeafName(sources[i]).replace(/[^A-Za-z0-9._-]/g, '_'))
    const status = entryLinkOrCopyFont(sources[i], target)
    if (status === 'linked') {
      result.linked++
    } else if (status === 'copied') {
      result.copied++
    } else {
      result.skipped++
    }
  }
  result.registryPatched += entryUpsertRegString(userReg, 'Software\\\\Wine\\\\HMOS', 'FontFamily', ENTRY_HMOS_UI_FONT) ? 1 : 0
  result.registryPatched += entryUpsertRegDword(userReg, 'Software\\\\Wine\\\\Fonts', 'LogPixels', 96) ? 1 : 0
  for (let i = 0; i < ENTRY_HMOS_UI_ALIASES.length; i++) {
    result.registryPatched += entryUpsertRegString(userReg, 'Software\\\\Wine\\\\Fonts\\\\Replacements', ENTRY_HMOS_UI_ALIASES[i], ENTRY_HMOS_UI_FONT) ? 1 : 0
    result.registryPatched += entryUpsertRegString(systemReg, 'Software\\\\Microsoft\\\\Windows NT\\\\CurrentVersion\\\\FontSubstitutes', ENTRY_HMOS_UI_ALIASES[i], ENTRY_HMOS_UI_FONT) ? 1 : 0
  }
  for (let i = 0; i < ENTRY_HMOS_CJK_ALIASES.length; i++) {
    result.registryPatched += entryUpsertRegString(userReg, 'Software\\\\Wine\\\\Fonts\\\\Replacements', ENTRY_HMOS_CJK_ALIASES[i], ENTRY_HMOS_CJK_FONT) ? 1 : 0
    result.registryPatched += entryUpsertRegString(systemReg, 'Software\\\\Microsoft\\\\Windows NT\\\\CurrentVersion\\\\FontSubstitutes', ENTRY_HMOS_CJK_ALIASES[i], ENTRY_HMOS_CJK_FONT) ? 1 : 0
  }
  for (let i = 0; i < ENTRY_HMOS_FONT_REGISTRY_FILES.length; i++) {
    result.registryPatched += entryUpsertRegString(systemReg, 'Software\\\\Microsoft\\\\Windows NT\\\\CurrentVersion\\\\Fonts',
      ENTRY_HMOS_FONT_REGISTRY_FILES[i][0], ENTRY_HMOS_FONT_REGISTRY_FILES[i][1]) ? 1 : 0
  }
  return result
}

@Entry
@Component
struct WineWindow {
  private logUnsubscribe?: () => void
  private stateUnsubscribe?: () => void
  private requestUnsubscribe?: () => void
  private activeRequest: WineWindowRequest = defaultWineWindowRequest()
  private autoLaunchStarted: boolean = false
  private handwritingPollTimer: number = -1
  private brokerPollTimer: number = -1
  private brokerWakeTimer: number = -1
  private brokerDrainActive: boolean = false
  private fullDesktopCompanionTimer: number = -1
  private fullDesktopCompanionLaunchStarted: boolean = false
  private renderTimer: number = -1
  private renderTick: number = 0
  private renderLoopRunning: boolean = false
  private renderActiveTicks: number = 0
  private lastRenderSource: string = ''
  private lastInputSequence: number = 0
  private explorerStatusTimer: number = -1
  private lastExplorerStatusLength: number = 0
  private runtimePatchesApplied: boolean = false
  private entryFontsSyncedPrefix: string = ''

  @State private windowId: string = 'wine-window-default'
  @State private requestedSessionId: string = ''
  @State private profileId: string = ''
  @State private kind: string = 'desktop'
  @State private label: string = 'Wine Desktop'
  @State private rawRoot: string = ''
  @State private targetName: string = ''
  @State private executableName: string = 'explorer.exe'
  @State private prefixName: string = 'wine-desktop-win11'
  @State private args: string[] = []
  @State private surfaceId: string = 'wine_window_surface_default'
  @State private keyboardHostId: string = 'wine_window_keyboard_host_default'
  @State private runtimeStagePath: string = ''
  @State private payloadStagePath: string = ''
  @State private prefixPath: string = ''
  @State private framePath: string = ''
  @State private activeSessionId: string = ''
  @State private sessionState: string = 'idle'
  @State private isBusy: boolean = false
  @State private logs: Proton.ProtonLogEntry[] = []
  @State private handwritingAnchorVisible: boolean = false
  @State private handwritingAnchorId: string = 'wine_handwriting_anchor'
  @State private handwritingHwnd: string = ''
  @State private handwritingText: string = ''
  @State private handwritingX: number = 0
  @State private handwritingY: number = 0
  @State private handwritingWidth: number = 240
  @State private handwritingHeight: number = 56

  aboutToAppear(): void {
    this.logUnsubscribe = Proton.onLog((entry: Proton.ProtonLogEntry): void => {
      const next = this.logs.concat([entry])
      this.logs = next.length > 160 ? next.slice(next.length - 160) : next
    })
    this.stateUnsubscribe = Proton.onState((state: Proton.ProtonState): void => {
      this.activeSessionId = state.sessionId
      this.sessionState = `${state.state}: ${state.message}`
    })
    this.requestUnsubscribe = onWineWindowRequest((request: WineWindowRequest): void => {
      this.applyRequest(request)
    })
    this.applyRequest(getWineWindowRequest())
    this.startHandwritingPoller()
    this.startBrokerPoller()
    this.startRenderLoop()
    if (ENABLE_EXPLORER_STATUS_POLL) {
      this.startExplorerStatusPoller()
    }
  }

  aboutToDisappear(): void {
    if (this.logUnsubscribe) {
      this.logUnsubscribe()
      this.logUnsubscribe = undefined
    }
    if (this.stateUnsubscribe) {
      this.stateUnsubscribe()
      this.stateUnsubscribe = undefined
    }
    if (this.requestUnsubscribe) {
      this.requestUnsubscribe()
      this.requestUnsubscribe = undefined
    }
    this.stopHandwritingPoller()
    this.stopBrokerPoller()
    this.stopFullDesktopCompanionTimer()
    this.stopRenderLoop()
    this.stopExplorerStatusPoller()
  }

  private addLocalLog(tag: string, message: string): void {
    if (ENABLE_WINE_UI_DIAGNOSTIC_LOGS) {
      hilog.info(DOMAIN, 'WineWindow', '%{public}s: %{public}s', tag, message)
    }
    const entry: Proton.ProtonLogEntry = {
      time: new Date().toISOString(),
      tag,
      message
    }
    const next = this.logs.concat([entry])
    this.logs = next.length > 160 ? next.slice(next.length - 160) : next
  }

  private addStatusLog(tag: string, message: string): void {
    if (ENABLE_WINE_STATUS_HILOG) {
      hilog.info(DOMAIN, 'WineWindow', '%{public}s: %{public}s', tag, message)
    }
    this.addLocalLog(tag, message)
  }

  private showToast(message: string): void {
    try {
      promptAction.showToast({
        message,
        duration: 1800
      })
    } catch (_) {
      this.addLocalLog('ui', message)
    }
  }

  private safeId(value: string): string {
    const clean = value.replace(/[^A-Za-z0-9_]/g, '_')
    return clean.length > 0 ? clean : 'default'
  }

  private applyRequest(request: WineWindowRequest): void {
    if (this.windowId !== 'wine-window-default' && this.windowId !== request.windowId) {
      return
    }
    this.activeRequest = request
    this.windowId = request.windowId
    this.requestedSessionId = request.sessionId
    this.profileId = request.profileId
    this.kind = request.kind
    this.label = request.label
    this.rawRoot = request.rawRoot
    this.targetName = request.targetName
    this.executableName = request.executableName
    this.prefixName = request.prefixName
    this.args = request.args.slice()
    this.surfaceId = `wine_window_surface_${this.safeId(request.windowId)}`
    this.keyboardHostId = `wine_window_keyboard_host_${this.safeId(request.windowId)}`
    this.fullDesktopCompanionLaunchStarted = false
    this.lastExplorerStatusLength = 0
    this.stopFullDesktopCompanionTimer()
    this.addLocalLog('window', `accepted ${request.kind}: ${request.executableName} windowId=${request.windowId} profileId=${request.profileId} autoLaunch=${request.autoLaunch ? 'true' : 'false'}`)
    if (request.autoLaunch && !this.autoLaunchStarted) {
      this.autoLaunchStarted = true
      setTimeout((): void => {
        this.addLocalLog('window', `auto launch fired for ${request.windowId}`)
        void this.launchCurrent()
      }, 300)
    }
  }

  private mountSurface(): void {
    const result = Proton.mountSurface(this.surfaceId)
    this.addLocalLog('surface', `${result.renderer}: ${result.message}`)
    if (result.width !== undefined && result.height !== undefined) {
      Proton.notifyWineSurfaceResize(this.surfaceId, result.width, result.height)
    }
    this.renderCurrentFrame()
  }

  private framePathForSurface(): string {
    if (this.prefixPath.length === 0) {
      return ''
    }
    return `${this.prefixPath}/dosdevices/h:/bridge/hmos-frame-${this.surfaceId}.bgra`
  }

  private focusWineSurface(reason: string): void {
    setTimeout((): void => {
      const hostFocused = focusControl.requestFocus(this.keyboardHostId)
      const surfaceFocused = focusControl.requestFocus(this.surfaceId)
      this.addLocalLog('input', `focus host=${hostFocused ? 'yes' : 'no'} surface=${surfaceFocused ? 'yes' : 'no'} reason=${reason}`)
    }, 20)
  }

  private keyActionName(type: KeyType): string {
    if (type === KeyType.Down) {
      return 'KEY_DOWN'
    }
    if (type === KeyType.Up) {
      return 'KEY_UP'
    }
    return 'KEY_UNKNOWN'
  }

  private dispatchArkKeyEvent(event: KeyEvent): boolean {
    const action = this.keyActionName(event.type)
    if (action === 'KEY_UNKNOWN') {
      return false
    }
    const result = Proton.injectKeyEvent(
      this.surfaceId,
      action,
      event.keyCode,
      event.metaKey,
      `ARKUI_${event.keySource}`,
      event.deviceId,
      event.timestamp
    )
    this.addLocalLog('input', `ark key ${result.success ? 'ok' : 'fail'} ${action} code=${event.keyCode} seq=${result.sequence}: ${result.message}`)
    event.stopPropagation()
    return result.success
  }

  private startRenderLoop(): void {
    if (this.renderLoopRunning) {
      return
    }
    this.renderLoopRunning = true
    this.scheduleNextRender(0)
  }

  private scheduleNextRender(delayMs: number): void {
    if (!this.renderLoopRunning || this.renderTimer >= 0) {
      return
    }
    this.renderTimer = setTimeout((): void => {
      this.renderTimer = -1
      this.renderCurrentFrame()
      const nextDelay = this.renderActiveTicks > 0 ? WINE_RENDER_ACTIVE_INTERVAL_MS : WINE_RENDER_IDLE_INTERVAL_MS
      this.scheduleNextRender(nextDelay)
    }, delayMs)
  }

  private stopRenderLoop(): void {
    this.renderLoopRunning = false
    if (this.renderTimer < 0) {
      return
    }
    clearTimeout(this.renderTimer)
    this.renderTimer = -1
  }

  private startBrokerPoller(): void {
    if (this.brokerPollTimer >= 0) {
      return
    }
    this.brokerPollTimer = setInterval((): void => {
      void this.pollWineProcessBroker()
    }, WINE_BROKER_IDLE_INTERVAL_MS)
  }

  private stopBrokerPoller(): void {
    if (this.brokerPollTimer < 0) {
      this.clearBrokerWakeTimer()
      return
    }
    clearInterval(this.brokerPollTimer)
    this.brokerPollTimer = -1
    this.clearBrokerWakeTimer()
  }

  private clearBrokerWakeTimer(): void {
    if (this.brokerWakeTimer < 0) {
      return
    }
    clearTimeout(this.brokerWakeTimer)
    this.brokerWakeTimer = -1
  }

  private wakeBrokerDrain(reason: string): void {
    if (this.brokerWakeTimer >= 0 || this.prefixPath.length === 0 || this.activeSessionId.length === 0) {
      return
    }
    this.brokerWakeTimer = setTimeout((): void => {
      this.brokerWakeTimer = -1
      void this.pollWineProcessBroker(WINE_BROKER_DRAIN_BATCH, reason)
    }, WINE_BROKER_INPUT_WAKE_DELAY_MS)
  }

  private stopFullDesktopCompanionTimer(): void {
    if (this.fullDesktopCompanionTimer < 0) {
      return
    }
    clearTimeout(this.fullDesktopCompanionTimer)
    this.fullDesktopCompanionTimer = -1
  }

  private startExplorerStatusPoller(): void {
    if (this.explorerStatusTimer >= 0) {
      return
    }
    this.explorerStatusTimer = setInterval((): void => {
      this.pollExplorerStatus()
    }, 500)
  }

  private stopExplorerStatusPoller(): void {
    if (this.explorerStatusTimer < 0) {
      return
    }
    clearInterval(this.explorerStatusTimer)
    this.explorerStatusTimer = -1
  }

  private pollExplorerStatus(): void {
    if (this.prefixName.length === 0 || this.prefixPath.length === 0) {
      return
    }
    try {
      const status = Proton.readExplorerStatus(this.prefixName)
      if (status.length <= this.lastExplorerStatusLength) {
        return
      }
      const delta = status.substring(this.lastExplorerStatusLength).trim()
      this.lastExplorerStatusLength = status.length
      if (delta.length > 0) {
        this.addStatusLog('explorer', delta.replace(/\n/g, ' | '))
      }
    } catch (err) {
      const message = err instanceof Error ? err.message : `${err}`
      this.addStatusLog('explorer', `status read failed: ${message}`)
    }
  }

  private async pollWineProcessBroker(maxRequests: number = WINE_BROKER_DRAIN_BATCH, reason: string = 'poll'): Promise<void> {
    if (this.brokerDrainActive || this.prefixPath.length === 0 || this.activeSessionId.length === 0) {
      return
    }
    this.brokerDrainActive = true
    try {
      const result = await Proton.drainWineProcessBroker(this.prefixName, this.surfaceId, maxRequests)
      if (result.processed > 0) {
        this.addStatusLog('broker', `${reason} drained=${result.processed} launched=${result.launched} blocked=${result.blocked} failed=${result.failed}`)
      }
    } catch (err) {
      const message = err instanceof Error ? err.message : `${err}`
      this.addStatusLog('broker', `drain failed: ${message}`)
    } finally {
      this.brokerDrainActive = false
    }
  }

  private renderCurrentFrame(): void {
    if (this.surfaceId.length === 0) {
      return
    }
    this.renderTick++
    const state = Proton.querySurfaceState(this.surfaceId)
    if (state.inputSequence > this.lastInputSequence) {
      this.lastInputSequence = state.inputSequence
      this.renderActiveTicks = WINE_RENDER_ACTIVE_TICKS
      this.wakeBrokerDrain('input')
    }
    if (!this.frameBridgeFallbackEnabled()) {
      if (ENABLE_WINE_UI_DIAGNOSTIC_LOGS &&
        (state.lastPresentSource !== this.lastRenderSource || this.renderTick <= 4 || this.renderTick % 180 === 0)) {
        this.lastRenderSource = state.lastPresentSource
        this.addLocalLog('surface', `state ${state.renderer} ready=${state.surfaceReady ? 'yes' : 'no'} present=${state.presentCount}/${state.presentFailCount} source=${state.lastPresentSource}`)
      }
      if (this.renderActiveTicks > 0) {
        this.renderActiveTicks--
      }
      return
    }
    const result = Proton.renderSurfaceFrame(this.surfaceId, this.framePath)
    if (!result.success) {
      if (ENABLE_WINE_UI_DIAGNOSTIC_LOGS && (this.renderTick <= 4 || this.renderTick % 180 === 0)) {
        this.addLocalLog('surface', `render skipped: ${result.message}`)
      }
      if (this.renderActiveTicks > 0) {
        this.renderActiveTicks--
      }
      return
    }
    if (result.source === 'frame') {
      this.renderActiveTicks = WINE_RENDER_ACTIVE_TICKS
    } else if (this.renderActiveTicks > 0) {
      this.renderActiveTicks--
    }
    if (ENABLE_WINE_UI_DIAGNOSTIC_LOGS &&
      (result.source !== this.lastRenderSource || this.renderTick <= 4 || this.renderTick % 180 === 0)) {
      this.lastRenderSource = result.source
      this.addLocalLog('surface', `render ${result.source} ${result.width ? result.width : 0}x${result.height ? result.height : 0}`)
    }
    if (result.source === 'frame') {
      this.scheduleFullDesktopCompanionApps()
    }
  }

  private frameBridgeFallbackEnabled(): boolean {
    return this.kind === 'desktop'
  }

  private startHandwritingPoller(): void {
    if (this.handwritingPollTimer >= 0) {
      return
    }
    this.handwritingPollTimer = setInterval((): void => {
      this.pollHandwritingRequest()
    }, 250)
  }

  private stopHandwritingPoller(): void {
    if (this.handwritingPollTimer < 0) {
      return
    }
    clearInterval(this.handwritingPollTimer)
    this.handwritingPollTimer = -1
  }

  private pollHandwritingRequest(): void {
    const request = Proton.consumeHandwritingRequest()
    if (!request.available) {
      return
    }
    if (request.xcomponentId !== this.surfaceId) {
      this.addLocalLog('input', `handwriting probe ignored for ${request.xcomponentId}`)
      return
    }
    this.addLocalLog('input', `handwriting probe editable=${request.editable ? 'yes' : 'no'} reason=${request.reason}`)
    if (!request.editable) {
      return
    }
    this.activateHandwritingAnchor(request)
  }

  private activateHandwritingAnchor(request: Proton.WineHandwritingAnchorRequest): void {
    this.handwritingAnchorId = `wine_handwriting_anchor_${this.safeId(this.windowId)}`
    this.handwritingHwnd = request.hwnd ? request.hwnd : ''
    this.handwritingText = request.text
    this.handwritingX = Math.max(0, request.x)
    this.handwritingY = Math.max(0, request.y)
    this.handwritingWidth = Math.max(48, request.width)
    this.handwritingHeight = Math.max(36, request.height)
    this.handwritingAnchorVisible = true
    setTimeout((): void => {
      const focused = focusControl.requestFocus(this.handwritingAnchorId)
      this.addLocalLog('input', `handwriting anchor focus=${focused ? 'yes' : 'no'} hwnd=${this.handwritingHwnd}`)
      void inputMethod.getController().showTextInput(inputMethod.RequestKeyboardReason.TOUCH)
    }, 20)
  }

  private commitHandwritingText(value: string): void {
    this.handwritingText = value
    if (this.activeSessionId.length === 0 || this.handwritingHwnd.length === 0) {
      this.addLocalLog('input', 'handwriting commit skipped: no active Wine hwnd')
      return
    }
    Proton.commitWineImeText(this.activeSessionId, this.handwritingHwnd, value, {
      start: value.length,
      end: value.length
    }, 'commit')
  }

  private targetPath(): string {
    if (this.payloadStagePath.length > 0) {
      return `${this.payloadStagePath}/${this.executableName}`
    }
    return `${this.targetName}/${this.executableName}`
  }

  private async stageRuntime(): Promise<void> {
    if (this.isBusy) {
      this.addLocalLog('runtime', 'stageRuntime skipped: busy')
      return
    }
    this.isBusy = true
    try {
      this.addLocalLog('runtime', 'stageRuntime start')
      const result = await Proton.stageRuntime()
      this.runtimeStagePath = result.targetPath
      this.addLocalLog('runtime', `runtime: ${result.fileCount} files, copied ${result.copiedCount}, skipped ${result.skippedCount}`)
    } catch (err) {
      const message = err instanceof Error ? err.message : `${err}`
      this.addLocalLog('runtime', message)
      this.showToast(`Runtime failed: ${message}`)
    } finally {
      this.isBusy = false
    }
  }

  private async ensureRuntimeStaged(): Promise<void> {
    if (this.runtimeStagePath.length > 0) {
      await this.applyRuntimePatches()
      return
    }
    await this.stageRuntime()
    if (this.runtimeStagePath.length === 0) {
      throw new Error('runtime staging did not finish')
    }
    await this.applyRuntimePatches()
  }

  private async applyRuntimePatches(): Promise<void> {
    if (this.runtimePatchesApplied || this.runtimeStagePath.length === 0) {
      return
    }
    const targetDir = `${this.runtimeStagePath}/files/lib/wine/x86_64-unix`
    const explorerTarget = `${targetDir}/explorer.exe.so`
    const ntdllTarget = `${targetDir}/ntdll.so`
    const win32uTarget = `${targetDir}/win32u.so`
    const winefileTargets = [
      `${targetDir}/winefile.exe.so`,
      `${targetDir}/winefile.so`
    ]
    let patchedBytes = 0
    this.addLocalLog('runtime', `runtime patch begin: explorer -> ${explorerTarget}`)
    const explorerResult = writeExplorerPatchFile(explorerTarget)
    if (!explorerResult.success) {
      throw new Error(`explorer runtime patch failed: ${explorerResult.message}`)
    }
    patchedBytes += explorerResult.bytes
    this.addLocalLog('runtime', `runtime patch begin: ntdll -> ${ntdllTarget}`)
    const ntdllResult = writeNtdllPatchFile(ntdllTarget)
    if (!ntdllResult.success) {
      throw new Error(`ntdll runtime patch failed: ${ntdllResult.message}`)
    }
    patchedBytes += ntdllResult.bytes
    this.addLocalLog('runtime', `runtime patch begin: win32u -> ${win32uTarget}`)
    const win32uResult = writeWin32uPatchFile(win32uTarget)
    if (!win32uResult.success) {
      throw new Error(`win32u runtime patch failed: ${win32uResult.message}`)
    }
    patchedBytes += win32uResult.bytes
    for (let i = 0; i < winefileTargets.length; i++) {
      const target = winefileTargets[i]
      this.addLocalLog('runtime', `runtime patch begin: winefile -> ${target}`)
      const result = writeRuntimePatchFile(target)
      if (!result.success) {
        throw new Error(`winefile runtime patch failed: ${result.message}`)
      }
      patchedBytes += result.bytes
    }
    this.runtimePatchesApplied = true
    this.addLocalLog('runtime', `runtime patch applied: explorer+ntdll+win32u+winefile totalBytes=${patchedBytes}`)
  }

  private async stagePayload(): Promise<void> {
    if (this.isBusy) {
      this.addLocalLog('staging', 'stagePayload skipped: busy')
      return
    }
    this.isBusy = true
    try {
      this.addLocalLog('staging', `stagePayload start ${this.rawRoot} -> ${this.targetName}`)
      const result = await Proton.stageRawfileTree(this.rawRoot, this.targetName)
      this.payloadStagePath = result.targetPath
      this.addLocalLog('staging', `${this.targetName}: ${result.fileCount} files, copied ${result.copiedCount}, skipped ${result.skippedCount}`)
    } catch (err) {
      const message = err instanceof Error ? err.message : `${err}`
      this.addLocalLog('staging', message)
      this.showToast(`Payload failed: ${message}`)
    } finally {
      this.isBusy = false
    }
  }

  private ensurePrefix(): void {
    this.addLocalLog('wine', `ensurePrefix start ${this.prefixName}`)
    const prefix = Proton.createOrOpenPrefix(this.prefixName)
    this.prefixPath = prefix.prefixPath
    this.framePath = this.framePathForSurface()
    if (this.entryFontsSyncedPrefix !== this.prefixName) {
      const fontSync = ensureEntryHmosFonts(this.prefixPath)
      this.entryFontsSyncedPrefix = this.prefixName
      this.addLocalLog('wine', `entry HMOS fonts linked=${fontSync.linked} copied=${fontSync.copied} skipped=${fontSync.skipped} registryPatched=${fontSync.registryPatched}`)
    } else {
      this.addLocalLog('wine', `entry HMOS fonts cached ${this.prefixName}`)
    }
    Proton.resetSurfaceBridge(this.prefixName, this.surfaceId)
    entryWriteText(`${this.prefixPath}/dosdevices/h:/bridge/hmos-explorer-status.txt`, '')
    this.lastRenderSource = ''
    this.lastInputSequence = 0
    this.renderActiveTicks = WINE_RENDER_ACTIVE_TICKS
    this.lastExplorerStatusLength = 0
    this.addLocalLog('wine', `${prefix.created ? 'created' : 'opened'} prefix: ${prefix.prefixPath}`)
  }

  private scheduleFullDesktopCompanionApps(): void {
    if (this.kind !== 'desktop' || this.fullDesktopCompanionLaunchStarted || this.fullDesktopCompanionTimer >= 0) {
      return
    }
    if (this.args.length > 1) {
      return
    }
    this.fullDesktopCompanionTimer = setTimeout((): void => {
      this.fullDesktopCompanionTimer = -1
      this.fullDesktopCompanionLaunchStarted = true
      void this.launchFullDesktopCompanionApps()
    }, 600)
  }

  private async launchFullDesktopCompanionApps(): Promise<void> {
    if (this.kind !== 'desktop' || this.prefixName.length === 0 || this.surfaceId.length === 0) {
      return
    }
    try {
      this.addLocalLog('process', `desktop companion start winefile surface=${this.surfaceId}`)
      const processResult = await Proton.launchWineProcess({
        kind: 'child',
        targetPath: 'C:\\windows\\system32\\winefile.exe',
        targetIsWinePath: true,
        prefixName: this.prefixName,
        args: [
          'C:\\'
        ],
        env: [
          'WINE_HMOS_INPROCESS_STRICT=0',
          'WINE_HMOS_REQUIRE_PROCESS_BROKER=1'
        ],
        xcomponentId: this.surfaceId
      })
      this.addLocalLog('process', `desktop companion ${processResult.execMode} slot=${processResult.processSlotId ? processResult.processSlotId : 0}: ${processResult.reason}`)
    } catch (err) {
      const message = err instanceof Error ? err.message : `${err}`
      this.addLocalLog('process', `desktop companion failed: ${message}`)
    }
  }

  private async launchCurrent(): Promise<void> {
    if (this.isBusy) {
      this.addLocalLog('process', 'launchCurrent skipped: busy')
      return
    }
    try {
      this.addLocalLog('process', `launchCurrent start ${this.kind}/${this.executableName}`)
      await this.ensureRuntimeStaged()
      if (this.kind !== 'desktop' && this.profileId.length === 0 && this.payloadStagePath.length === 0) {
        await this.stagePayload()
      }
      if (this.kind !== 'desktop' && this.profileId.length === 0 && this.payloadStagePath.length === 0) {
        throw new Error('payload staging did not finish')
      }
      this.ensurePrefix()
      let session: Proton.LaunchSession
      if (this.kind === 'desktop') {
        this.addLocalLog('process', `broker desktop start surface=${this.surfaceId}`)
        const desktopArgs = this.args.length > 0 ? this.args : [
          '/desktop=shell,896x640'
        ]
        const processResult = await Proton.launchWineProcess({
          kind: 'desktop',
          targetPath: 'C:\\windows\\explorer.exe',
          targetIsWinePath: true,
          prefixName: this.prefixName,
          args: desktopArgs,
          env: [
            'WINE_HMOS_INPROCESS_STRICT=0',
            'WINE_HMOS_REQUIRE_PROCESS_BROKER=1'
          ],
          xcomponentId: this.surfaceId
        })
        if (!processResult.session) {
          throw new Error(`${processResult.status}: ${processResult.reason}`)
        }
        session = processResult.session
        this.addLocalLog('process', `broker ${processResult.execMode} slot=${processResult.processSlotId ? processResult.processSlotId : 0}: ${processResult.reason}`)
      } else if (this.profileId.length > 0) {
        const profileOptions: Proton.LaunchProfileOptions = {
          xcomponentId: this.surfaceId
        }
        if (this.args.length > 0) {
          profileOptions.argsOverride = this.args
        }
        this.addLocalLog('process', `profile launch start profileId=${this.profileId} surface=${this.surfaceId}`)
        session = await Proton.launchProfile(this.profileId, profileOptions)
      } else {
        const launchOptions: Proton.WineProcessRequest = {
          kind: this.kind === 'launcher' ? 'launcher' : this.kind,
          targetPath: this.targetPath(),
          prefixName: this.prefixName,
          args: this.args,
          xcomponentId: this.surfaceId
        }
        this.addLocalLog('process', `broker launch start target=${launchOptions.targetPath} surface=${launchOptions.xcomponentId}`)
        const processResult = await Proton.launchWineProcess(launchOptions)
        if (!processResult.session) {
          throw new Error(`${processResult.status}: ${processResult.reason}`)
        }
        session = processResult.session
        this.addLocalLog('process', `broker ${processResult.execMode} slot=${processResult.processSlotId ? processResult.processSlotId : 0}: ${processResult.reason}`)
      }
      this.activeSessionId = session.sessionId
      this.sessionState = `${session.status}: ${session.reason ? session.reason : session.commandLine}`
      this.addLocalLog('process', `${this.label} session ${session.sessionId}`)
    } catch (err) {
      const message = err instanceof Error ? err.message : `${err}`
      this.addLocalLog('process', message)
      this.showToast(`${this.label} failed: ${message}`)
    }
  }

  private stopActive(): void {
    if (this.activeSessionId.length === 0) {
      this.showToast('No active session')
      return
    }
    Proton.stop(this.activeSessionId)
  }

  build() {
    Stack() {
      XComponent({
        id: this.surfaceId,
        type: XComponentType.SURFACE,
        libraryname: 'proton'
      })
        .width('100%')
        .height('100%')
        .backgroundColor('#000000')
        .focusable(true)
        .onLoad(() => {
          this.mountSurface()
          this.focusWineSurface('load')
        })
        .onClick(() => this.focusWineSurface('click'))
      if (this.handwritingAnchorVisible) {
        TextInput({ text: this.handwritingText })
          .id(this.handwritingAnchorId)
          .width(this.handwritingWidth)
          .height(this.handwritingHeight)
          .position({ x: this.handwritingX, y: this.handwritingY })
          .opacity(0.01)
          .enableKeyboardOnFocus(true)
          .zIndex(1)
          .onChange((value: string): void => {
            this.commitHandwritingText(value)
          })
      }
    }
      .id(this.keyboardHostId)
      .width('100%')
      .height('100%')
      .backgroundColor('#000000')
      .focusable(true)
      .defaultFocus(true)
      .focusOnTouch(true)
      .onClick(() => this.focusWineSurface('host-click'))
      .onKeyEvent((event: KeyEvent): boolean => {
        return this.dispatchArkKeyEvent(event)
      })
  }
}
