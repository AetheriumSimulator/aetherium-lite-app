import common from '@ohos.app.ability.common'
import application from '@ohos.app.ability.application'
import deviceInfo from '@ohos.deviceInfo'
import font from '@ohos.font'
import fs from '@ohos.file.fs'
import hilog from '@ohos.hilog'
import i18n from '@ohos.i18n'
import taskpool from '@ohos.taskpool'
import worker from '@ohos.worker'
import { childProcessManager } from '@kit.AbilityKit'
import protonNative from 'libproton.so'

declare function canIUse(syscap: string): boolean

const LOG_DOMAIN: number = 0x2330
const LOG_TAG: string = 'ProtonHsp'
const STAGE_ROOT_DIR: string = 'proton-stage'
const PREFIX_ROOT_DIR: string = 'proton-prefix'
const MANIFEST_NAME: string = '.proton-stage-manifest.json'
const RAWFILE_INDEX_NAME: string = 'proton_rawfile_index.json'
const COPY_CHUNK_SIZE: number = 1024 * 1024
const RAWFILE_CONTENT_TIMEOUT_MS: number = 15000
const MODULE_CONTEXT_TIMEOUT_MS: number = 5000
const RUNTIME_BOX64_IN_PROCESS: string = 'in-process:libbox64_hmos_core.so'
const RUNTIME_PROTON_RAW_ROOT: string = 'runtime/proton'
const RUNTIME_PROTON_TARGET_NAME: string = 'runtime-proton'
const RUNTIME_WINE_LOADER_RELATIVE_PATH: string = 'files/lib/wine/x86_64-unix/wine-hmos-loader.so'
const RUNTIME_WINE_ENTRY_SYMBOL: string = 'wine_hmos_main'
const RUNTIME_WINE_SERVER_LIBRARY: string = 'libwine_hmos_server.so'
const RUNTIME_WINE_VERSION: string = 'win11'
const RUNTIME_WINE_HMOS_DRIVER: string = 'wineonarkui'
const RUNTIME_WINE_HMOS_GRAPHICS_BACKEND: string = 'xcomponent'
const RUNTIME_WINE_HMOS_COMPOSITOR: string = 'native'
const RUNTIME_WINE_HMOS_TRACE: string = 'surface,vulkan,present,input'
const RUNTIME_DEFAULT_PFX_RELATIVE_PATH: string = 'files/share/default_pfx'
const PREFIX_DEFAULT_PFX_MARKER: string = '.hmos-default-pfx-ready'
const PREFIX_FONT_STACK_MARKER: string = '.hmos-font-stack-ready'
const REQUIRED_DEFAULT_PREFIX_RELATIVE_PATHS: string[] = [
  'drive_c/windows/explorer.exe',
  'drive_c/windows/system32/explorer.exe',
  'drive_c/windows/system32/gdi32.dll',
  'drive_c/windows/system32/kernel32.dll',
  'drive_c/windows/system32/shcore.dll',
  'drive_c/windows/system32/shell32.dll',
  'drive_c/windows/system32/shlwapi.dll',
  'drive_c/windows/system32/uxtheme.dll',
  'drive_c/windows/system32/user32.dll',
  'drive_c/windows/system32/control.exe',
  'drive_c/windows/system32/rundll32.exe',
  'drive_c/windows/system32/winecfg.exe',
  'drive_c/windows/system32/winefile.exe',
  'drive_c/windows/system32/appwiz.cpl',
  'drive_c/windows/system32/bthprops.cpl',
  'drive_c/windows/system32/desk.cpl',
  'drive_c/windows/system32/inetcpl.cpl',
  'drive_c/windows/system32/irprops.cpl',
  'drive_c/windows/system32/joy.cpl',
  'drive_c/windows/syswow64/explorer.exe',
  'drive_c/windows/syswow64/gdi32.dll',
  'drive_c/windows/syswow64/kernel32.dll',
  'drive_c/windows/syswow64/shcore.dll',
  'drive_c/windows/syswow64/shell32.dll',
  'drive_c/windows/syswow64/shlwapi.dll',
  'drive_c/windows/syswow64/uxtheme.dll',
  'drive_c/windows/syswow64/user32.dll',
  'drive_c/windows/syswow64/control.exe',
  'drive_c/windows/syswow64/rundll32.exe',
  'drive_c/windows/syswow64/winecfg.exe',
  'drive_c/windows/syswow64/winefile.exe',
  'drive_c/windows/syswow64/appwiz.cpl',
  'drive_c/windows/syswow64/bthprops.cpl',
  'drive_c/windows/syswow64/desk.cpl',
  'drive_c/windows/syswow64/inetcpl.cpl',
  'drive_c/windows/syswow64/irprops.cpl',
  'drive_c/windows/syswow64/joy.cpl'
]
interface DefaultPrefixCopyPath {
  source: string
  target: string
}

const EXTRA_DEFAULT_PREFIX_COPY_PATHS: DefaultPrefixCopyPath[] = [
  {
    source: 'drive_c/windows/system32/uxtheme.dll',
    target: 'drive_c/windows/uxtheme.dll'
  }
]
const PREFIX_HMOS_DRIVE_DIR: string = 'hmos_drive'
const PREFIX_HMOS_DRIVE_LETTER: string = 'h:'
const PREFIX_HMOS_BRIDGE_DIR: string = 'bridge'
const PREFIX_HMOS_APPS_DIR: string = 'apps'
const PREFIX_HMOS_INSTALLERS_DIR: string = 'installers'
const PREFIX_HMOS_PROFILES_DIR: string = 'profiles'
const PREFIX_HMOS_INSTALL_RECORDS_DIR: string = 'install-records'
const WINE_CHILD_ENTRY_POINT: string = 'libproton.so:WineChildMain'
const WINE_WORKER_SCRIPT_URL: string = 'proton/ets/workers/WineProcessWorker.ets'
const WINE_PROCESS_SYSCAP: string = 'SystemCapability.Ability.AbilityRuntime.Core'
const MAX_EMULATED_PROCESS_SLOTS: number = 4
const RUNTIME_FONT_RELATIVE_PREFIXES: string[] = [
  'files/share/fonts/',
  'files/share/wine/fonts/'
]
const HMOS_FONT_SOURCE_DIRS: string[] = [
  '/data/themes/fonts',
  '/data/service/el1/public/themes',
  '/data/storage/el1/base/fonts',
  '/data/storage/el2/base/fonts',
  '/data/service/el1/public/fonts',
  '/system/fonts'
]
const HMOS_FONT_SCAN_MAX_DEPTH: number = 4
const HMOS_FONT_SCAN_LIMIT: number = 768
const HMOS_UI_FONT_FAMILY: string = 'HarmonyOS Sans'
const HMOS_CJK_FONT_FAMILY: string = 'HarmonyOS Sans SC'
const HMOS_SYSTEM_FONT_REGISTRY_ENTRIES: string[][] = [
  ['HarmonyOS Sans (TrueType)', 'HarmonyOS_Sans.ttf'],
  ['HarmonyOS Sans SC (TrueType)', 'HarmonyOS_Sans_SC.ttf'],
  ['HarmonyOS Sans TC (TrueType)', 'HarmonyOS_Sans_TC.ttf'],
  ['HarmonyOS Sans Italic (TrueType)', 'HarmonyOS_Sans_Italic.ttf'],
  ['HarmonyOS Color Emoji (TrueType)', 'HMOSColorEmojiCompat.ttf'],
  ['Noto Sans CJK Regular (TrueType)', 'NotoSansCJK-Regular.ttc']
]
const HMOS_UI_FONT_ALIASES: string[] = [
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
const HMOS_CJK_FONT_ALIASES: string[] = [
  'DengXian',
  'FangSong',
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
  'Noto Sans CJK SC',
  'Noto Sans CJK TC',
  'PMingLiU',
  'SimHei',
  'SimSun',
  'Yu Gothic'
]
interface HmosFontChoice {
  family: string
  path: string
  source: string
  fileName: string
}

interface HmosSystemSettings {
  language: string
  region: string
  locale: string
  firstPreferredLanguage: string
  preferredLanguages: string
  posixLocale: string
  gnuLanguage: string
  fontFamily: string
  fontPath: string
  fontSource: string
  fontFileName: string
  cjkFontFamily: string
  cjkFontPath: string
  cjkFontSource: string
  cjkFontFileName: string
}

const FORCE_REFRESH_RUNTIME_RELATIVE_PATHS: string[] = [
  'files/lib/wine/x86_64-unix/ntdll.so',
  'files/lib/wine/x86_64-unix/win32u.so',
  'files/lib/wine/x86_64-unix/wine-hmos-loader.so',
  'files/lib/wine/x86_64-unix/explorer.exe.so',
  'files/lib/wine/x86_64-windows/explorer.exe',
  'files/lib/wine/x86_64-windows/gdi32.dll',
  'files/lib/wine/x86_64-windows/kernel32.dll',
  'files/lib/wine/x86_64-windows/shcore.dll',
  'files/lib/wine/x86_64-windows/shell32.dll',
  'files/lib/wine/x86_64-windows/shlwapi.dll',
  'files/lib/wine/x86_64-windows/uxtheme.dll',
  'files/lib/wine/x86_64-windows/user32.dll',
  'files/lib/wine/x86_64-windows/winefile.exe',
  'files/share/default_pfx/drive_c/windows/explorer.exe',
  'files/share/default_pfx/drive_c/windows/system32/explorer.exe',
  'files/share/default_pfx/drive_c/windows/system32/gdi32.dll',
  'files/share/default_pfx/drive_c/windows/system32/kernel32.dll',
  'files/share/default_pfx/drive_c/windows/system32/shcore.dll',
  'files/share/default_pfx/drive_c/windows/system32/shell32.dll',
  'files/share/default_pfx/drive_c/windows/system32/shlwapi.dll',
  'files/share/default_pfx/drive_c/windows/system32/uxtheme.dll',
  'files/share/default_pfx/drive_c/windows/system32/user32.dll',
  'files/share/default_pfx/drive_c/windows/system32/winefile.exe',
  'files/share/default_pfx/drive_c/windows/syswow64/explorer.exe',
  'files/share/default_pfx/drive_c/windows/syswow64/gdi32.dll',
  'files/share/default_pfx/drive_c/windows/syswow64/kernel32.dll',
  'files/share/default_pfx/drive_c/windows/syswow64/shcore.dll',
  'files/share/default_pfx/drive_c/windows/syswow64/shell32.dll',
  'files/share/default_pfx/drive_c/windows/syswow64/shlwapi.dll',
  'files/share/default_pfx/drive_c/windows/syswow64/uxtheme.dll',
  'files/share/default_pfx/drive_c/windows/syswow64/user32.dll',
  'files/share/default_pfx/drive_c/windows/syswow64/winefile.exe'
]
const CONTENT_COPY_RAW_ROOTS: string[] = [
  RUNTIME_PROTON_RAW_ROOT,
  'win32-smoke'
]
const OPTIONAL_RUNTIME_RAW_PREFIXES: string[] = [
  'files/share/wine/mono/',
  'files/share/wine/gecko/'
]

export interface RuntimeComponent {
  name: string
  library: string
  available: boolean
  error: string
  processModel?: string
}

export interface RuntimeProbe {
  abi: string
  nativeModule: string
  vulkanLinked: boolean
  vulkanProbeResult: number
  vulkanApiVersion: number
  runtimeReady: boolean
  runtimeComponents: RuntimeComponent[]
  hasHostContext: boolean
  rawfileReady: boolean
  jitPolicy: string
  executableMemoryPolicy: string
  xcomponentBridge: string
  stage: string
}

interface NativeRuntimeProbe {
  nativeModule: string
  abi: string
  vulkanLinked: boolean
  vulkanProbeResult: number
  vulkanApiVersion: number
  runtimeReady: boolean
  runtimeComponents: RuntimeComponent[]
  stage: string
}

export interface GraphicsCapabilities {
  nativeModule: string
  abi: string
  nativeWindow: boolean
  cpuPresent: boolean
  vulkanLinked: boolean
  vulkanProbeResult: number
  vulkanApiVersion: number
  instanceExtensionResult: number
  instanceExtensions: string[]
  hasKhrSurface: boolean
  hasOhosSurface: boolean
  hasArkUiVulkanSurface: boolean
  instanceCreateResult: number
  physicalDeviceResult: number
  physicalDeviceCount: number
  swapchainDeviceCount: number
  hasSwapchain: boolean
  presentBackend: string
}

interface NativeSurfaceResult {
  success: boolean
  xcomponentId: string
  renderer: string
  message: string
  windowHandle?: string
  width?: number
  height?: number
  generation?: number
  nativeWindowConfigured?: boolean
}

export interface SurfaceState {
  success: boolean
  xcomponentId: string
  renderer: string
  surfaceReady: boolean
  windowHandle: string
  width: number
  height: number
  offsetX: number
  offsetY: number
  generation: number
  destroyCount: number
  nativeWindowConfigured: boolean
  frameWidth: number
  frameHeight: number
  inputSequence: number
  presentCount: number
  presentFailCount: number
  lastPresentMs: number
  lastPresentSource: string
  lastPresentMessage: string
  lastPresentWidth: number
  lastPresentHeight: number
  lastPresentFrame: number
}

interface NativeFrameResult {
  success: boolean
  xcomponentId: string
  framePath: string
  source: string
  message: string
  width?: number
  height?: number
  frameNumber?: number
  inputSequence?: number
}

interface NativeLaunchSession {
  sessionId: string
  status: string
  reason: string
  exitCode?: number
}

interface NativeChmodResult {
  path: string
  success: boolean
  errnoCode: number
  message: string
}

export interface NativeInputBridgeResult {
  success: boolean
  xcomponentId: string
  message: string
  inputPath: string
  sequence: number
}

export interface NativePresentReport {
  success: boolean
  xcomponentId: string
  message: string
}

export interface WineRect {
  x: number
  y: number
  width: number
  height: number
}

export interface WineTextSelection {
  start: number
  end: number
}

export interface WineHandwritingAnchorRequest {
  available: boolean
  editable: boolean
  reason: string
  xcomponentId: string
  sessionId?: string
  hwnd?: string
  x: number
  y: number
  width: number
  height: number
  text: string
  selectionStart: number
  selectionEnd: number
}

export interface ControllerDevice {
  deviceId: number
  name: string
  source: string
  dinputIndex: number
  xinputIndex: number
}

export interface ControllerState {
  deviceId: number
  connected: boolean
  buttons: Record<string, boolean>
  axes: Record<string, number>
}

export interface ControllerOutput {
  deviceId: number
  lowFrequencyRumble?: number
  highFrequencyRumble?: number
  adaptiveTrigger?: string
  hdHaptics?: string
}

interface NativeZipStageResult {
  success: boolean
  error: string
  hspPath: string
  zipRoot: string
  targetPath: string
  fileCount: number
  copiedCount: number
  skippedCount: number
  totalBytes: number
}

interface NativeProtonModule {
  probeRuntime(): NativeRuntimeProbe
  mountSurface(xcomponentId: string): NativeSurfaceResult
  queryGraphicsCapabilities(): GraphicsCapabilities
  querySurfaceState(xcomponentId: string): SurfaceState
  reportWinePresent(xcomponentId: string, source: string, success: number, width: number, height: number, frameNumber: number, message: string): NativePresentReport
  renderSurfaceFrame(xcomponentId: string, framePath: string): NativeFrameResult
  clearSurfaceFrameCache(xcomponentId: string): void
  notifyWineSurfaceResize(windowId: string, width: number, height: number): void
  injectKeyEvent(xcomponentId: string, action: string, keyCode: number, modifiers: number, source: string, deviceId: number, timestamp: number): NativeInputBridgeResult
  consumeHandwritingRequest(): WineHandwritingAnchorRequest
  showWineHandwritingAnchor(sessionId: string, hwnd: string, rect: string, text: string, selection: string): void
  hideWineHandwritingAnchor(sessionId: string, reason: string): void
  commitWineImeText(sessionId: string, hwnd: string, text: string, selection: string, compositionState: string): void
  enumerateControllers(): ControllerDevice[]
  getControllerState(deviceId: number): ControllerState
  sendControllerOutput(deviceId: number, output: string): void
  launchSession(launchRequest: string): NativeLaunchSession
  launchSessionInCurrentProcess(launchRequest: string): NativeLaunchSession
  chmodExecutable(path: string): NativeChmodResult
  stageDirectoryRawfileTree(sourceRoot: string, targetPath: string): NativeZipStageResult
  stageStoredZipRawfileTree(hspPath: string, zipRoot: string, targetPath: string): NativeZipStageResult
  stopSession(sessionId: string): void
}

interface RawDescriptor {
  fd: number
  offset: number
  length: number
}

interface RawfileIndexFile {
  path?: string
  size?: number
}

interface RawfileIndex {
  files: Array<string | RawfileIndexFile>
}

interface IndexedRawfile {
  rawPath: string
  size: number
}

interface RuntimeApplicationInfo {
  codePath?: string
  name?: string
  bundleName?: string
}

export interface StagedFile {
  rawPath: string
  targetPath: string
  size: number
  hash: string
  copied: boolean
}

export interface StageResult {
  rawRoot: string
  targetName: string
  targetPath: string
  fileCount: number
  copiedCount: number
  skippedCount: number
  totalBytes: number
  manifestPath: string
  files: StagedFile[]
}

export interface SurfaceResult {
  success: boolean
  xcomponentId: string
  renderer: string
  message: string
  windowHandle?: string
  width?: number
  height?: number
}

export interface PrefixResult {
  prefixName: string
  prefixPath: string
  created: boolean
}

export interface LaunchOptions {
  targetPath: string
  targetIsWinePath?: boolean
  prefixName?: string
  args?: string[]
  workingDirectory?: string
  env?: string[]
  xcomponentId?: string
}

export interface DesktopLaunchOptions {
  prefixName?: string
  args?: string[]
  workingDirectory?: string
  env?: string[]
  xcomponentId?: string
}

export interface LaunchSession {
  sessionId: string
  kind: string
  targetPath: string
  prefixPath: string
  status: string
  commandLine: string
  reason?: string
  exitCode?: number
}

export enum ExecMode {
  NATIVE_CHILD_PROCESS = 'NATIVE_CHILD_PROCESS',
  WORKER_EMULATED_PROCESS = 'WORKER_EMULATED_PROCESS',
  TASKPOOL_EMULATED_PROCESS = 'TASKPOOL_EMULATED_PROCESS'
}

export interface ExecutionCapabilities {
  deviceType: string
  sdkApiVersion: number
  childProcessSyscap: boolean
  nativeChildProcess: boolean
  workerAvailable: boolean
  taskpoolAvailable: boolean
  selectedMode: ExecMode
  reason: string
}

export interface WineProcessRequest {
  kind: string
  targetPath: string
  targetIsWinePath?: boolean
  prefixName?: string
  args?: string[]
  workingDirectory?: string
  env?: string[]
  xcomponentId?: string
  preferBackend?: ExecMode
  shortLived?: boolean
}

export interface WineProcessResult {
  requestId: string
  execMode: ExecMode
  session?: LaunchSession
  pid?: number
  processSlotId?: number
  status: string
  reason: string
}

export interface WineBrokerDrainResult {
  prefixName: string
  brokerRoot: string
  scanned: number
  processed: number
  launched: number
  blocked: number
  failed: number
  messages: string[]
}

interface WineWorkerLaunchMessage {
  type: string
  requestId: string
  slotId: number
  launchRequest: string
}

interface WineWorkerResultMessage {
  type: string
  requestId: string
  slotId: number
  status: string
  reason: string
  exitCode?: number
}

interface WineEmulatedSlot {
  slotId: number
  mode: ExecMode
  requestId: string
  active: boolean
  workerRef?: worker.ThreadWorker
}

export interface ImportWineExecutableRequest {
  sourcePath: string
  prefixName: string
  profileName?: string
  copyDirectory?: boolean
  executableName?: string
}

export interface ImportWineInstallerRequest {
  sourcePath: string
  prefixName: string
  installerType?: string
  profileName?: string
  args?: string[]
}

export interface LaunchProfileOptions {
  xcomponentId?: string
  argsOverride?: string[]
  envOverride?: string[]
}

export interface WineLaunchProfile {
  profileId: string
  type: string
  prefixName: string
  displayName: string
  winePath: string
  hostPath: string
  workingDirectory: string
  args: string[]
  env: string[]
  sourceRecordId?: string
  createdAt: string
}

export interface WineInstallRecord {
  recordId: string
  prefixName: string
  displayName: string
  installerType: string
  sourcePath: string
  stagedPath: string
  winePath: string
  args: string[]
  status: string
  createdAt: string
  discoveredProfiles: WineLaunchProfile[]
}

export interface ProtonLogEntry {
  time: string
  tag: string
  message: string
}

export interface ProtonState {
  sessionId: string
  state: string
  message: string
}

let hostContext: common.UIAbilityContext | undefined = undefined
let runtimeBox64Path: string = ''
let runtimeProtonPath: string = ''
let initializedPrefixNames: string[] = []
const logCallbacks: Array<(entry: ProtonLogEntry) => void> = []
const stateCallbacks: Array<(state: ProtonState) => void> = []
const nativeBridge = protonNative as NativeProtonModule
let nextEmulatedSlotId: number = 1
const emulatedSlots: WineEmulatedSlot[] = []
let cachedHmosSystemSettings: HmosSystemSettings | undefined = undefined

@Concurrent
function runWineTaskpoolLaunch(launchRequest: string): string {
  const taskNativeBridge = protonNative as NativeProtonModule
  const result = taskNativeBridge.launchSessionInCurrentProcess(launchRequest)
  return JSON.stringify(result)
}

function nowText(): string {
  return new Date().toISOString()
}

function emitLog(tag: string, message: string): void {
  const entry: ProtonLogEntry = {
    time: nowText(),
    tag,
    message
  }
  hilog.info(LOG_DOMAIN, LOG_TAG, '[%{public}s] %{public}s', tag, message)
  const callbacks = logCallbacks.slice()
  setTimeout(() => {
    for (let i = 0; i < callbacks.length; i++) {
      callbacks[i](entry)
    }
  }, 0)
}

function emitState(sessionId: string, state: string, message: string): void {
  const item: ProtonState = {
    sessionId,
    state,
    message
  }
  const callbacks = stateCallbacks.slice()
  setTimeout(() => {
    for (let i = 0; i < callbacks.length; i++) {
      callbacks[i](item)
    }
  }, 0)
}

function requireContext(): common.UIAbilityContext {
  if (!hostContext) {
    throw new Error('Proton host context is not configured')
  }
  return hostContext
}

function sanitizeName(value: string): string {
  const clean = value.replace(/\\/g, '/').split('/').filter((part: string) => part.length > 0).join('-')
  if (clean.length === 0) {
    return 'default'
  }
  return clean.replace(/\.\./g, '_')
}

function hmosFrameFileName(xcomponentId?: string): string {
  const clean = xcomponentId && xcomponentId.length > 0 ? sanitizeName(xcomponentId) : 'default'
  return `hmos-frame-${clean}.bgra`
}

function hmosInputFileName(xcomponentId?: string): string {
  const clean = xcomponentId && xcomponentId.length > 0 ? sanitizeName(xcomponentId) : 'default'
  return `hmos-input-${clean}.txt`
}

function removeFileIfPresent(path: string): boolean {
  try {
    fs.unlinkSync(path)
    return true
  } catch (_) {
    return false
  }
}

function joinPath(left: string, right: string): string {
  if (left.endsWith('/')) {
    return `${left}${right}`
  }
  return `${left}/${right}`
}

function ensureDir(path: string): void {
  try {
    fs.mkdirSync(path, true)
  } catch (err) {
    const text = err instanceof Error ? err.message : `${err}`
    if (text.indexOf('File exists') < 0) {
      throw new Error(`mkdir failed: ${path}: ${text}`)
    }
  }
}

function parentDir(path: string): string {
  const idx = Math.max(path.lastIndexOf('/'), path.lastIndexOf('\\'))
  if (idx <= 0) {
    return path
  }
  return path.substring(0, idx)
}

function leafName(path: string): string {
  const idx = Math.max(path.lastIndexOf('/'), path.lastIndexOf('\\'))
  if (idx < 0) {
    return path
  }
  return path.substring(idx + 1)
}

function stripExtension(name: string): string {
  const idx = name.lastIndexOf('.')
  return idx > 0 ? name.substring(0, idx) : name
}

function lowerName(path: string): string {
  return leafName(path).toLowerCase()
}

function canUseSystemCapability(name: string): boolean {
  try {
    return canIUse(name)
  } catch (_) {
    return false
  }
}

function profileIdFromName(name: string): string {
  return sanitizeName(`${stripExtension(name)}-${Date.now()}`)
}

function shouldSkipRawfileLeaf(path: string): boolean {
  const leaf = leafName(path)
  return leaf.length === 0 ||
    leaf === RAWFILE_INDEX_NAME ||
    leaf === '.proton-rawfile-index.json' ||
    leaf === '.gitkeep' ||
    leaf === 'PROTON_PLACEHOLDER.txt' ||
    leaf.startsWith('.')
}

function shouldSkipRuntimeRelativePath(relativePath: string): boolean {
  for (let i = 0; i < OPTIONAL_RUNTIME_RAW_PREFIXES.length; i++) {
    if (relativePath.startsWith(OPTIONAL_RUNTIME_RAW_PREFIXES[i])) {
      return true
    }
  }
  return false
}

function shouldForceRefreshStagedFile(rawRoot: string, relativePath: string): boolean {
  if (rawRoot === 'win32-smoke') {
    return true
  }
  if (rawRoot !== RUNTIME_PROTON_RAW_ROOT) {
    return false
  }
  for (let i = 0; i < FORCE_REFRESH_RUNTIME_RELATIVE_PATHS.length; i++) {
    if (relativePath === FORCE_REFRESH_RUNTIME_RELATIVE_PATHS[i]) {
      return true
    }
  }
  return false
}

function fileExists(path: string): boolean {
  try {
    fs.statSync(path)
    return true
  } catch (_) {
    return false
  }
}

function isDirectoryPath(path: string): boolean {
  try {
    return fs.statSync(path).isDirectory()
  } catch (_) {
    return false
  }
}

function isRegularFilePath(path: string): boolean {
  try {
    return fs.statSync(path).isFile()
  } catch (_) {
    return false
  }
}

function listFilesSafe(path: string): string[] {
  try {
    return fs.listFileSync(path)
  } catch (_) {
    return []
  }
}

function findFirstExe(root: string, maxDepth: number = 4): string {
  if (maxDepth < 0 || !isDirectoryPath(root)) {
    return ''
  }
  const names = listFilesSafe(root)
  for (let i = 0; i < names.length; i++) {
    const child = joinPath(root, names[i])
    if (isRegularFilePath(child) && lowerName(child).endsWith('.exe')) {
      return child
    }
  }
  for (let i = 0; i < names.length; i++) {
    const child = joinPath(root, names[i])
    if (isDirectoryPath(child)) {
      const found = findFirstExe(child, maxDepth - 1)
      if (found.length > 0) {
        return found
      }
    }
  }
  return ''
}

function ensureSymlink(target: string, linkPath: string, directoryFallback: boolean = false): void {
  try {
    const stat = fs.lstatSync(linkPath)
    if (stat.isSymbolicLink()) {
      emitLog('wine', `dosdevices link ready: ${linkPath}`)
      return
    }
    if (directoryFallback && stat.isDirectory()) {
      emitLog('wine', `dosdevices directory fallback ready: ${linkPath}`)
      return
    }
    if (stat.isFile()) {
      try {
        fs.unlinkSync(linkPath)
        emitLog('wine', `dosdevices placeholder removed: ${linkPath}`)
      } catch (unlinkErr) {
        emitLog('wine', `dosdevices placeholder remove failed: ${linkPath}: ${errorMessage(unlinkErr)}`)
        return
      }
    } else {
      emitLog('wine', `dosdevices path exists but is not a symlink: ${linkPath}`)
      return
    }
  } catch (_) {
  }

  try {
    ensureDir(parentDir(linkPath))
    fs.symlinkSync(target, linkPath)
    emitLog('wine', `dosdevices link created: ${linkPath} -> ${target}`)
  } catch (err) {
    emitLog('wine', `dosdevices link failed: ${linkPath} -> ${target}: ${errorMessage(err)}`)
    if (directoryFallback) {
      try {
        ensureDir(linkPath)
        emitLog('wine', `dosdevices directory fallback created: ${linkPath}`)
        return
      } catch (fallbackErr) {
        emitLog('wine', `dosdevices directory fallback failed: ${linkPath}: ${errorMessage(fallbackErr)}`)
      }
    }
    if (!fileExists(linkPath)) {
      try {
        writeTextFile(linkPath, `${target}\n`)
        emitLog('wine', `dosdevices placeholder created: ${linkPath} -> ${target}`)
      } catch (placeholderErr) {
        emitLog('wine', `dosdevices placeholder failed: ${linkPath}: ${errorMessage(placeholderErr)}`)
      }
    }
  }
}

function ensureWineDosDevices(prefixPath: string): void {
  const dosDevicesPath = joinPath(prefixPath, 'dosdevices')
  ensureDir(dosDevicesPath)
  ensureDir(joinPath(prefixPath, PREFIX_HMOS_DRIVE_DIR))
  ensureSymlink('../drive_c', joinPath(dosDevicesPath, 'c:'), true)
  ensureSymlink(`../${PREFIX_HMOS_DRIVE_DIR}`, joinPath(dosDevicesPath, PREFIX_HMOS_DRIVE_LETTER), true)
  ensureSymlink('/', joinPath(dosDevicesPath, 'z:'))
}

function fileExistsWithSize(path: string, size: number): boolean {
  try {
    const stat = fs.statSync(path)
    return Number(stat.size) === size
  } catch (_) {
    return false
  }
}

function chmodExecutableIfPresent(path: string): void {
  if (!fileExists(path)) {
    return
  }
  const result = nativeBridge.chmodExecutable(path)
  if (result.success) {
    emitLog('runtime', `executable permission ready: ${path}`)
    return
  }
  emitLog('runtime', `chmod executable failed: ${path}: ${result.message}`)
}

function toHex32(value: number): string {
  const unsignedValue = value >>> 0
  return unsignedValue.toString(16).padStart(8, '0')
}

function updateHash(hash: number, bytes: Uint8Array, length: number): number {
  let next = hash >>> 0
  for (let i = 0; i < length; i++) {
    next = (next ^ bytes[i]) >>> 0
    next = Math.imul(next, 16777619) >>> 0
  }
  return next >>> 0
}

function errorMessage(err: Error | Object): string {
  if (err instanceof Error) {
    return err.message
  }
  try {
    return JSON.stringify(err)
  } catch (_) {
    return `${err}`
  }
}

async function openRawDescriptor(context: common.Context, rawPath: string): Promise<RawDescriptor> {
  try {
    const descriptor = await context.resourceManager.getRawFd(rawPath)
    return {
      fd: descriptor.fd,
      offset: descriptor.offset,
      length: descriptor.length
    }
  } catch (err) {
    throw new Error(`open rawfile failed: ${rawPath}: ${errorMessage(err)}`)
  }
}

async function closeRawDescriptor(context: common.Context, rawPath: string): Promise<void> {
  try {
    await context.resourceManager.closeRawFd(rawPath)
  } catch (err) {
    emitLog('rawfile', `close failed ${rawPath}: ${errorMessage(err)}`)
  }
}

async function listRawEntries(context: common.Context, rawPath: string): Promise<string[]> {
  try {
    return await context.resourceManager.getRawFileList(rawPath)
  } catch (err) {
    throw new Error(`list rawfile failed: ${rawPath}: ${errorMessage(err)}`)
  }
}

function timeoutError<T>(message: string): Promise<T> {
  return new Promise<T>((_resolve, reject) => {
    setTimeout(() => {
      reject(new Error(message))
    }, RAWFILE_CONTENT_TIMEOUT_MS)
  })
}

function timeoutAfter<T>(timeoutMs: number, message: string): Promise<T> {
  return new Promise<T>((_resolve, reject) => {
    setTimeout(() => {
      reject(new Error(message))
    }, timeoutMs)
  })
}

function decodeUtf8(bytes: Uint8Array): string {
  let result = ''
  const chunkSize = 8192
  for (let offset = 0; offset < bytes.length; offset += chunkSize) {
    const end = Math.min(offset + chunkSize, bytes.length)
    let chunk = ''
    for (let i = offset; i < end; i++) {
      chunk += String.fromCharCode(bytes[i])
    }
    result += chunk
  }
  return result
}

async function readRawfileIndex(context: common.Context, rawRoot: string): Promise<IndexedRawfile[] | undefined> {
  const indexPath = joinPath(rawRoot, RAWFILE_INDEX_NAME)
  let bytes: Uint8Array
  try {
    bytes = await context.resourceManager.getRawFileContent(indexPath)
  } catch (_) {
    return undefined
  }

  const parsed = JSON.parse(decodeUtf8(bytes)) as RawfileIndex
  if (!Array.isArray(parsed.files)) {
    throw new Error(`rawfile index missing files array: ${indexPath}`)
  }

  const rawFiles: IndexedRawfile[] = []
  for (let i = 0; i < parsed.files.length; i++) {
    const indexItem = parsed.files[i]
    let relativePath = ''
    let size = -1
    if (typeof indexItem === 'string') {
      relativePath = indexItem
    } else if (indexItem && typeof indexItem.path === 'string') {
      relativePath = indexItem.path
      if (typeof indexItem.size === 'number') {
        size = indexItem.size
      }
    }
    if (shouldSkipRawfileLeaf(relativePath) || shouldSkipRuntimeRelativePath(relativePath)) {
      continue
    }
    rawFiles.push({
      rawPath: joinPath(rawRoot, relativePath),
      size
    })
  }
  return rawFiles
}

async function tryOpenRawFile(context: common.Context, rawPath: string): Promise<boolean> {
  try {
    const descriptor = await openRawDescriptor(context, rawPath)
    await closeRawDescriptor(context, rawPath)
    return true
  } catch (_) {
    return false
  }
}

function openWriteFile(path: string): fs.File {
  try {
    return fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC)
  } catch (err) {
    throw new Error(`open output failed: ${path}: ${errorMessage(err)}`)
  }
}

function openAppendFile(path: string): fs.File {
  try {
    return fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.APPEND)
  } catch (err) {
    throw new Error(`open append failed: ${path}: ${errorMessage(err)}`)
  }
}

async function readChunk(fd: number, buffer: ArrayBuffer, offset: number, length: number): Promise<number> {
  try {
    return await fs.read(fd, buffer, {
      offset,
      length
    })
  } catch (err) {
    throw new Error(`read failed: ${errorMessage(err)}`)
  }
}

function writeChunk(fd: number, buffer: ArrayBuffer, length: number): void {
  try {
    fs.writeSync(fd, buffer, {
      length
    })
  } catch (err) {
    throw new Error(`write failed: ${errorMessage(err)}`)
  }
}

function closeFile(file: fs.File): void {
  try {
    fs.closeSync(file)
  } catch (err) {
    emitLog('fs', `close failed: ${errorMessage(err)}`)
  }
}

async function yieldToEventLoop(): Promise<void> {
  await new Promise<void>((resolve) => {
    setTimeout(() => {
      resolve()
    }, 0)
  })
}

function shouldUseContentCopy(rawPath: string): boolean {
  for (let i = 0; i < CONTENT_COPY_RAW_ROOTS.length; i++) {
    const root = CONTENT_COPY_RAW_ROOTS[i]
    if (rawPath === root || rawPath.startsWith(`${root}/`)) {
      return true
    }
  }
  return false
}

function writeTextFile(path: string, content: string): void {
  const file = openWriteFile(path)
  try {
    fs.writeSync(file.fd, content)
  } catch (err) {
    throw new Error(`write text failed: ${path}: ${errorMessage(err)}`)
  } finally {
    closeFile(file)
  }
}

function appendTextFile(path: string, content: string): void {
  const file = openAppendFile(path)
  try {
    fs.writeSync(file.fd, content)
  } catch (err) {
    throw new Error(`append text failed: ${path}: ${errorMessage(err)}`)
  } finally {
    closeFile(file)
  }
}

function readTextFile(path: string): string {
  try {
    return fs.readTextSync(path)
  } catch (err) {
    throw new Error(`read text failed: ${path}: ${errorMessage(err)}`)
  }
}

function appendUniqueString(values: string[], value: string): void {
  if (value.length === 0 || values.indexOf(value) >= 0) {
    return
  }
  values.push(value)
}

function safeI18nString(label: string, supplier: () => string, fallback: string): string {
  try {
    const value = supplier()
    if (value && value.length > 0) {
      return value
    }
  } catch (err) {
    emitLog('wine', `system ${label} unavailable: ${errorMessage(err)}`)
  }
  return fallback
}

function safePreferredLanguages(): string[] {
  try {
    const values = i18n.System.getPreferredLanguageList()
    if (values && values.length > 0) {
      return values
    }
  } catch (err) {
    emitLog('wine', `system preferred language list unavailable: ${errorMessage(err)}`)
  }
  return []
}

function safeSystemLocale(): string {
  try {
    const localeObject = i18n.System.getSystemLocaleInstance()
    const value = `${localeObject}`
    if (value.length > 0 && value !== '[object Object]') {
      return value
    }
  } catch (err) {
    emitLog('wine', `system locale instance unavailable: ${errorMessage(err)}`)
  }
  return safeI18nString('locale', () => i18n.System.getSystemLocale(), 'en-US')
}

function normalizeLocaleTag(value: string): string {
  const trimmed = value.trim().replace(/_/g, '-')
  return trimmed.length > 0 ? trimmed : 'en-US'
}

function localeLanguageFromTag(value: string): string {
  const parts = normalizeLocaleTag(value).split('-')
  return parts.length > 0 && parts[0].length > 0 ? parts[0].toLowerCase() : 'en'
}

function localeRegionFromTag(value: string, fallbackRegion: string): string {
  const parts = normalizeLocaleTag(value).split('-')
  for (let i = parts.length - 1; i >= 1; i--) {
    const part = parts[i]
    if (part.length === 2 || part.length === 3) {
      return part.toUpperCase()
    }
  }
  const normalized = normalizeLocaleTag(value).toLowerCase()
  if (normalized.indexOf('zh-hant') === 0) {
    return 'TW'
  }
  if (normalized.indexOf('zh-hans') === 0) {
    return 'CN'
  }
  return fallbackRegion.length > 0 ? fallbackRegion.toUpperCase() : 'US'
}

function winePosixLocale(localeValue: string, languageValue: string, regionValue: string): string {
  const normalized = normalizeLocaleTag(localeValue)
  const language = localeLanguageFromTag(languageValue.length > 0 ? languageValue : normalized)
  const region = localeRegionFromTag(normalized, regionValue)
  return `${language}_${region}.UTF-8`
}

function gnuLanguageList(primary: string, preferredLanguages: string[]): string {
  const values: string[] = []
  appendUniqueString(values, winePosixLocale(primary, primary, '').replace('.UTF-8', ''))
  appendUniqueString(values, localeLanguageFromTag(primary))
  for (let i = 0; i < preferredLanguages.length; i++) {
    const item = preferredLanguages[i]
    appendUniqueString(values, winePosixLocale(item, item, '').replace('.UTF-8', ''))
    appendUniqueString(values, localeLanguageFromTag(item))
  }
  return values.join(':')
}

function hmosFontFileName(path: string): string {
  return path.length > 0 ? safeHmosFontTargetName(path) : ''
}

function hmosFontChoice(family: string, path: string, source: string): HmosFontChoice {
  return {
    family,
    path,
    source,
    fileName: hmosFontFileName(path)
  }
}

function isThemeFontPath(path: string): boolean {
  const lower = path.toLowerCase()
  return lower.indexOf('/data/themes') >= 0 ||
    lower.indexOf('/themes/') >= 0 ||
    lower.indexOf('/theme/') >= 0 ||
    lower.indexOf('/data/service/el1/public/themes') >= 0
}

function isUserFontPath(path: string): boolean {
  const lower = path.toLowerCase()
  return isThemeFontPath(path) ||
    lower.indexOf('/data/storage/') >= 0 ||
    lower.indexOf('/data/service/el1/public/fonts') >= 0
}

function isUsableUiFontFamily(family: string): boolean {
  const lower = family.toLowerCase()
  return family.length > 0 &&
    lower.indexOf('emoji') < 0 &&
    lower.indexOf('icon') < 0 &&
    lower.indexOf('symbol') < 0 &&
    lower.indexOf('ding') < 0 &&
    lower.indexOf('math') < 0
}

function isAsciiText(value: string): boolean {
  for (let i = 0; i < value.length; i++) {
    if (value.charCodeAt(i) > 0x7f) {
      return false
    }
  }
  return true
}

function wineSafeFontFamily(family: string, path: string, fallback: string): string {
  if (family.length > 0 && isAsciiText(family)) {
    return family
  }
  const lowerPath = path.toLowerCase()
  if (lowerPath.indexOf('harmonyos_sans_sc') >= 0) {
    return HMOS_CJK_FONT_FAMILY
  }
  if (lowerPath.indexOf('harmonyos_sans_tc') >= 0) {
    return 'HarmonyOS Sans TC'
  }
  if (lowerPath.indexOf('harmonyos_sans') >= 0) {
    return HMOS_UI_FONT_FAMILY
  }
  return fallback
}

function fontChoiceFromFontName(fontName: string, source: string): HmosFontChoice {
  if (!isUsableUiFontFamily(fontName)) {
    return hmosFontChoice('', '', '')
  }
  try {
    const info = font.getFontByName(fontName)
    const family = info.family && info.family.length > 0 ? info.family : fontName
    const path = info.path && info.path.length > 0 ? info.path : ''
    return hmosFontChoice(family, path, source)
  } catch (_) {
    return hmosFontChoice(fontName, '', source)
  }
}

function systemFontNamesSafe(): string[] {
  try {
    const names = font.getSystemFontList()
    if (names && names.length > 0) {
      return names
    }
  } catch (err) {
    emitLog('wine', `system font list unavailable: ${errorMessage(err)}`)
  }
  return []
}

function chooseThemeFontFromSystemList(): HmosFontChoice {
  const names = systemFontNamesSafe()
  for (let i = 0; i < names.length; i++) {
    const candidate = fontChoiceFromFontName(names[i], 'font-api-theme')
    if (candidate.family.length > 0 && isThemeFontPath(candidate.path)) {
      return candidate
    }
  }
  for (let i = 0; i < names.length; i++) {
    const candidate = fontChoiceFromFontName(names[i], 'font-api-user')
    if (candidate.family.length > 0 && isUserFontPath(candidate.path)) {
      return candidate
    }
  }
  return hmosFontChoice('', '', '')
}

function chooseUiGenericFont(aliasName: string): HmosFontChoice {
  try {
    const config = font.getUIFontConfig()
    for (let i = 0; i < config.generic.length; i++) {
      const item = config.generic[i]
      if (item.family.length === 0) {
        continue
      }
      if (item.family === aliasName) {
        return fontChoiceFromFontName(item.family, 'ui-font-config')
      }
      for (let a = 0; a < item.alias.length; a++) {
        const alias = item.alias[a].name.toLowerCase()
        if (alias === aliasName.toLowerCase()) {
          return fontChoiceFromFontName(item.family, 'ui-font-config')
        }
      }
    }
  } catch (err) {
    emitLog('wine', `ui font config unavailable: ${errorMessage(err)}`)
  }
  return hmosFontChoice('', '', '')
}

function chooseLocaleFallbackFont(localeValue: string, defaultFamily: string): HmosFontChoice {
  try {
    const language = localeLanguageFromTag(localeValue)
    const config = font.getUIFontConfig()
    for (let i = 0; i < config.fallbackGroups.length; i++) {
      const group = config.fallbackGroups[i]
      if (group.fontSetName.length > 0 && group.fontSetName !== defaultFamily) {
        continue
      }
      for (let f = 0; f < group.fallback.length; f++) {
        const item = group.fallback[f]
        if (item.family.length > 0 && item.language.toLowerCase().indexOf(language) === 0) {
          return fontChoiceFromFontName(item.family, 'ui-font-fallback')
        }
      }
    }
  } catch (_) {
  }
  return hmosFontChoice('', '', '')
}

function chooseScannedThemeFont(): HmosFontChoice {
  const paths: string[] = []
  for (let i = 0; i < HMOS_FONT_SOURCE_DIRS.length; i++) {
    const root = HMOS_FONT_SOURCE_DIRS[i]
    if (isThemeFontPath(root) || isUserFontPath(root)) {
      collectHmosFontFiles(root, HMOS_FONT_SCAN_MAX_DEPTH, paths)
    }
  }
  if (paths.length === 0) {
    return hmosFontChoice('', '', '')
  }
  const path = paths[0]
  return hmosFontChoice(stripExtension(leafName(path)), path, 'theme-font-scan')
}

function chooseNamedSystemFont(names: string[]): HmosFontChoice {
  const available = systemFontNamesSafe()
  for (let i = 0; i < names.length; i++) {
    const wanted = names[i].toLowerCase()
    for (let a = 0; a < available.length; a++) {
      if (available[a].toLowerCase() === wanted) {
        return fontChoiceFromFontName(available[a], 'font-api-named')
      }
    }
  }
  return hmosFontChoice('', '', '')
}

function chooseDefaultHmosFont(localeValue: string): HmosFontChoice {
  const themeChoice = chooseThemeFontFromSystemList()
  if (themeChoice.family.length > 0) {
    return themeChoice
  }
  const genericChoice = chooseUiGenericFont('sans-serif')
  if (genericChoice.family.length > 0) {
    return genericChoice
  }
  const scannedChoice = chooseScannedThemeFont()
  if (scannedChoice.family.length > 0) {
    return scannedChoice
  }
  const cjkLocale = localeLanguageFromTag(localeValue) === 'zh'
  const namedChoice = chooseNamedSystemFont(cjkLocale ?
    [HMOS_UI_FONT_FAMILY, HMOS_CJK_FONT_FAMILY, 'Noto Sans CJK SC'] :
    [HMOS_UI_FONT_FAMILY, 'sans-serif', HMOS_CJK_FONT_FAMILY])
  if (namedChoice.family.length > 0) {
    return namedChoice
  }
  return hmosFontChoice(HMOS_UI_FONT_FAMILY, '', 'fallback')
}

function hmosFontSourceDirs(): string[] {
  const dirs: string[] = []
  try {
    const config = font.getUIFontConfig()
    for (let i = 0; i < config.fontDir.length; i++) {
      appendUniqueString(dirs, config.fontDir[i])
    }
  } catch (_) {
  }
  for (let i = 0; i < HMOS_FONT_SOURCE_DIRS.length; i++) {
    appendUniqueString(dirs, HMOS_FONT_SOURCE_DIRS[i])
  }
  return dirs
}

function currentHmosSystemSettings(): HmosSystemSettings {
  if (cachedHmosSystemSettings) {
    return cachedHmosSystemSettings
  }
  const locale = normalizeLocaleTag(safeSystemLocale())
  const language = safeI18nString('language', () => i18n.System.getSystemLanguage(), localeLanguageFromTag(locale))
  const region = safeI18nString('region', () => i18n.System.getSystemRegion(), localeRegionFromTag(locale, 'US'))
  const firstPreferredLanguage = safeI18nString('first preferred language', () => i18n.System.getFirstPreferredLanguage(), language)
  const preferredLanguageList = safePreferredLanguages()
  const fontChoice = chooseDefaultHmosFont(locale)
  const cjkChoice = chooseLocaleFallbackFont(locale, fontChoice.family)
  const effectiveFontChoice = (localeLanguageFromTag(locale) === 'zh' &&
    (fontChoice.source === 'fallback' || fontChoice.family === HMOS_UI_FONT_FAMILY) &&
    cjkChoice.family.length > 0) ? cjkChoice : fontChoice
  const effectiveCjkChoice = cjkChoice.family.length > 0 ? cjkChoice : fontChoice
  const wineFontFamily = wineSafeFontFamily(effectiveFontChoice.family, effectiveFontChoice.path, HMOS_UI_FONT_FAMILY)
  const wineCjkFontFamily = wineSafeFontFamily(effectiveCjkChoice.family, effectiveCjkChoice.path, HMOS_CJK_FONT_FAMILY)
  const posixLocale = winePosixLocale(locale, language, region)
  const settings: HmosSystemSettings = {
    language,
    region,
    locale,
    firstPreferredLanguage,
    preferredLanguages: preferredLanguageList.join(','),
    posixLocale,
    gnuLanguage: gnuLanguageList(locale, preferredLanguageList),
    fontFamily: wineFontFamily,
    fontPath: effectiveFontChoice.path,
    fontSource: effectiveFontChoice.source.length > 0 ? effectiveFontChoice.source : 'fallback',
    fontFileName: effectiveFontChoice.fileName,
    cjkFontFamily: wineCjkFontFamily,
    cjkFontPath: effectiveCjkChoice.path,
    cjkFontSource: effectiveCjkChoice.source.length > 0 ? effectiveCjkChoice.source : 'fallback',
    cjkFontFileName: effectiveCjkChoice.fileName
  }
  cachedHmosSystemSettings = settings
  emitLog('wine', `HMOS system bridge locale=${settings.locale} language=${settings.language} region=${settings.region} posix=${settings.posixLocale} font=${settings.fontFamily} cjk=${settings.cjkFontFamily} fontSource=${settings.fontSource} fontPath=${settings.fontPath}`)
  return settings
}

function writeJsonFile(path: string, value: Object): void {
  ensureDir(parentDir(path))
  writeTextFile(path, JSON.stringify(value))
}

function readJsonFile<T>(path: string): T {
  return JSON.parse(readTextFile(path)) as T
}

function jsonPath(root: string, id: string): string {
  return joinPath(root, `${sanitizeName(id)}.json`)
}

function ensureWineWin11Prefix(prefixPath: string): void {
  const userReg = joinPath(prefixPath, 'user.reg')
  const versionBlock = `\n[Software\\\\Wine] ${Date.now()}\n"Version"="${RUNTIME_WINE_VERSION}"\n`
  if (!fileExists(userReg)) {
    writeTextFile(userReg, `WINE REGISTRY Version 2\n;; All keys relative to REGISTRY\\User\\S-1-5-21-0-0-0-1000\n\n#arch=win64\n${versionBlock}`)
    emitLog('wine', `prefix Windows version set to ${RUNTIME_WINE_VERSION}`)
    return
  }

  const content = readTextFile(userReg)
  const wineSectionIndex = content.indexOf('[Software\\\\Wine]')
  if (wineSectionIndex < 0) {
    appendTextFile(userReg, versionBlock)
    emitLog('wine', `prefix Windows version appended as ${RUNTIME_WINE_VERSION}`)
    return
  }

  const nextSectionIndex = content.indexOf('\n[', wineSectionIndex + 1)
  const before = content.substring(0, wineSectionIndex)
  const section = nextSectionIndex >= 0 ? content.substring(wineSectionIndex, nextSectionIndex) : content.substring(wineSectionIndex)
  const after = nextSectionIndex >= 0 ? content.substring(nextSectionIndex) : ''
  const patchedSection = section.indexOf('"Version"=') >= 0 ?
    section.replace(/"Version"="[^"]*"/, `"Version"="${RUNTIME_WINE_VERSION}"`) :
    `${section.trimEnd()}\n"Version"="${RUNTIME_WINE_VERSION}"\n`
  const patched = `${before}${patchedSection}${after}`
  if (patched !== content) {
    writeTextFile(userReg, patched)
    emitLog('wine', `prefix Windows version patched to ${RUNTIME_WINE_VERSION}`)
  } else {
    emitLog('wine', `prefix Windows version already ${RUNTIME_WINE_VERSION}`)
  }
}

function ensureWineHmosPrefix(prefixPath: string): void {
  const settings = currentHmosSystemSettings()
  let patched = 0
  patched += upsertWineUserRegString(prefixPath, 'Software\\\\Wine\\\\HMOS', 'Driver', RUNTIME_WINE_HMOS_DRIVER) ? 1 : 0
  patched += upsertWineUserRegString(prefixPath, 'Software\\\\Wine\\\\HMOS', 'GraphicsBackend', RUNTIME_WINE_HMOS_GRAPHICS_BACKEND) ? 1 : 0
  patched += upsertWineUserRegString(prefixPath, 'Software\\\\Wine\\\\HMOS', 'FontFamily', settings.fontFamily) ? 1 : 0
  patched += upsertWineUserRegString(prefixPath, 'Software\\\\Wine\\\\HMOS', 'CjkFontFamily', settings.cjkFontFamily) ? 1 : 0
  patched += upsertWineUserRegString(prefixPath, 'Software\\\\Wine\\\\HMOS', 'FontPath', settings.fontPath) ? 1 : 0
  patched += upsertWineUserRegString(prefixPath, 'Software\\\\Wine\\\\HMOS', 'FontSource', settings.fontSource) ? 1 : 0
  patched += upsertWineUserRegString(prefixPath, 'Software\\\\Wine\\\\HMOS', 'Locale', settings.locale) ? 1 : 0
  patched += upsertWineUserRegString(prefixPath, 'Software\\\\Wine\\\\HMOS', 'Language', settings.language) ? 1 : 0
  patched += upsertWineUserRegString(prefixPath, 'Software\\\\Wine\\\\HMOS', 'Region', settings.region) ? 1 : 0
  patched += upsertWineUserRegString(prefixPath, 'Software\\\\Wine\\\\HMOS', 'FirstPreferredLanguage', settings.firstPreferredLanguage) ? 1 : 0
  patched += upsertWineUserRegString(prefixPath, 'Software\\\\Wine\\\\HMOS', 'PreferredLanguages', settings.preferredLanguages) ? 1 : 0
  patched += upsertWineUserRegString(prefixPath, 'Software\\\\Wine\\\\HMOS', 'PosixLocale', settings.posixLocale) ? 1 : 0
  patched += upsertWineUserRegString(prefixPath, 'Control Panel\\\\International', 'LocaleName', settings.locale) ? 1 : 0
  patched += upsertWineUserRegString(prefixPath, 'Control Panel\\\\International', 'sLanguage', settings.language) ? 1 : 0
  patched += upsertWineUserRegString(prefixPath, 'Control Panel\\\\International', 'sCountry', settings.region) ? 1 : 0

  if (patched > 0) {
    emitLog('wine', `prefix HMOS system bridge patched entries=${patched} locale=${settings.locale} font=${settings.fontFamily}`)
  } else {
    emitLog('wine', `prefix HMOS system bridge already ready locale=${settings.locale} font=${settings.fontFamily}`)
  }
}

function upsertWineUserRegString(prefixPath: string, sectionName: string, key: string, value: string): boolean {
  const userReg = joinPath(prefixPath, 'user.reg')
  return upsertWineRegStringFile(userReg, sectionName, key, value)
}

function upsertWineRegStringFile(regPath: string, sectionName: string, key: string, value: string): boolean {
  const header = `[${sectionName}]`
  const entry = `"${key}"="${value}"`
  const block = `\n${header} ${Date.now()}\n${entry}\n`

  if (!fileExists(regPath)) {
    writeTextFile(regPath, `WINE REGISTRY Version 2\n\n#arch=win64\n${block}`)
    return true
  }

  const content = readTextFile(regPath)
  const sectionIndex = content.indexOf(header)
  if (sectionIndex < 0) {
    appendTextFile(regPath, block)
    return true
  }

  const nextSectionIndex = content.indexOf('\n[', sectionIndex + 1)
  const before = content.substring(0, sectionIndex)
  const section = nextSectionIndex >= 0 ? content.substring(sectionIndex, nextSectionIndex) : content.substring(sectionIndex)
  const after = nextSectionIndex >= 0 ? content.substring(nextSectionIndex) : ''
  const escapedKey = key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
  const valuePattern = new RegExp(`"${escapedKey}"="[^"]*"`)
  const patchedSection = valuePattern.test(section) ?
    section.replace(valuePattern, entry) :
    `${section.trimEnd()}\n${entry}\n`
  const patched = `${before}${patchedSection}${after}`
  if (patched === content) {
    return false
  }
  writeTextFile(regPath, patched)
  return true
}

function upsertWineUserRegDword(prefixPath: string, sectionName: string, key: string, value: number): boolean {
  const userReg = joinPath(prefixPath, 'user.reg')
  const header = `[${sectionName}]`
  const hex = Math.max(0, value).toString(16).padStart(8, '0')
  const entry = `"${key}"=dword:${hex}`
  const block = `\n${header} ${Date.now()}\n${entry}\n`

  if (!fileExists(userReg)) {
    writeTextFile(userReg, `WINE REGISTRY Version 2\n;; All keys relative to REGISTRY\\User\\S-1-5-21-0-0-0-1000\n\n#arch=win64\n${block}`)
    return true
  }

  const content = readTextFile(userReg)
  const sectionIndex = content.indexOf(header)
  if (sectionIndex < 0) {
    appendTextFile(userReg, block)
    return true
  }

  const nextSectionIndex = content.indexOf('\n[', sectionIndex + 1)
  const before = content.substring(0, sectionIndex)
  const section = nextSectionIndex >= 0 ? content.substring(sectionIndex, nextSectionIndex) : content.substring(sectionIndex)
  const after = nextSectionIndex >= 0 ? content.substring(nextSectionIndex) : ''
  const escapedKey = key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
  const valuePattern = new RegExp(`"${escapedKey}"=dword:[0-9A-Fa-f]+`)
  const patchedSection = valuePattern.test(section) ?
    section.replace(valuePattern, entry) :
    `${section.trimEnd()}\n${entry}\n`
  const patched = `${before}${patchedSection}${after}`
  if (patched === content) {
    return false
  }
  writeTextFile(userReg, patched)
  return true
}

function ensureWineGraphicsDriverPrefix(prefixPath: string): void {
  const changed = upsertWineUserRegString(prefixPath, 'Software\\\\Wine\\\\Drivers', 'Graphics', 'null')
  emitLog('wine', changed ? 'prefix Wine graphics driver forced to null' : 'prefix Wine graphics driver already null')
}

function ensureWineDesktopShellPrefix(prefixPath: string): void {
  const sizeChanged = upsertWineUserRegString(prefixPath, 'Software\\\\Wine\\\\Explorer\\\\Desktops', 'shell', '896x640')
  const shellChanged = upsertWineUserRegDword(prefixPath, 'Software\\\\Wine\\\\Explorer\\\\Desktops\\\\shell', 'EnableShell', 1)
  const systrayChanged = upsertWineUserRegDword(prefixPath, 'Software\\\\Wine\\\\Explorer\\\\Desktops\\\\shell', 'ShowSystray', 1)
  emitLog('wine', (sizeChanged || shellChanged || systrayChanged) ?
    'prefix Wine desktop shell registry patched' :
    'prefix Wine desktop shell registry already ready')
}

function defaultPrefixTargetPath(prefixPath: string, driveCRoot: string, relativePath: string): string {
  if (relativePath.startsWith('drive_c/')) {
    return joinPath(driveCRoot, relativePath.substring('drive_c/'.length))
  }
  return joinPath(prefixPath, relativePath)
}

function requiredDefaultPrefixMisses(sourceRoot: string, prefixPath: string, driveCRoot: string): string[] {
  const misses: string[] = []
  for (let i = 0; i < REQUIRED_DEFAULT_PREFIX_RELATIVE_PATHS.length; i++) {
    const relativePath = REQUIRED_DEFAULT_PREFIX_RELATIVE_PATHS[i]
    const sourcePath = joinPath(sourceRoot, relativePath)
    const targetPath = defaultPrefixTargetPath(prefixPath, driveCRoot, relativePath)
    let sourceSize = -1
    try {
      sourceSize = Number(fs.statSync(sourcePath).size)
    } catch (_) {
      misses.push(`source:${relativePath}`)
      continue
    }
    if (!fileExistsWithSize(targetPath, sourceSize)) {
      misses.push(relativePath)
    }
  }
  for (let i = 0; i < EXTRA_DEFAULT_PREFIX_COPY_PATHS.length; i++) {
    const item = EXTRA_DEFAULT_PREFIX_COPY_PATHS[i]
    const sourcePath = joinPath(sourceRoot, item.source)
    const targetPath = defaultPrefixTargetPath(prefixPath, driveCRoot, item.target)
    let sourceSize = -1
    try {
      sourceSize = Number(fs.statSync(sourcePath).size)
    } catch (_) {
      misses.push(`source:${item.source}`)
      continue
    }
    if (!fileExistsWithSize(targetPath, sourceSize)) {
      misses.push(item.target)
    }
  }
  return misses
}

function ensureDefaultPrefixContents(prefixPath: string): void {
  const sourceRoot = joinPath(runtimeProtonStagePath(), RUNTIME_DEFAULT_PFX_RELATIVE_PATH)
  const markerPath = joinPath(prefixPath, PREFIX_DEFAULT_PFX_MARKER)
  const driveCRoot = prefixDriveCRootPath(prefixPath)
  const kernel32Path = joinPath(driveCRoot, 'windows/system32/kernel32.dll')
  const requiredMisses = requiredDefaultPrefixMisses(sourceRoot, prefixPath, driveCRoot)
  if (fileExists(markerPath) && fileExists(kernel32Path) && requiredMisses.length === 0) {
    emitLog('wine', `default prefix already merged: ${prefixPath}`)
    return
  }
  if (fileExists(markerPath) && requiredMisses.length > 0) {
    emitLog('wine', `default prefix refresh required: missingOrStale=${requiredMisses.join(',')}`)
  }
  if (!fileExists(sourceRoot)) {
    emitLog('wine', `default prefix source missing: ${sourceRoot}`)
    return
  }

  const manifestPath = joinPath(runtimeProtonStagePath(), MANIFEST_NAME)
  if (!fileExists(manifestPath)) {
    emitLog('wine', `default prefix manifest missing: ${manifestPath}`)
    return
  }

  const manifest = JSON.parse(readTextFile(manifestPath)) as StageResult
  if (!manifest || !Array.isArray(manifest.files)) {
    emitLog('wine', `default prefix manifest has no files: ${manifestPath}`)
    return
  }

  const sourcePrefix = `${sourceRoot}/`
  let copied = 0
  let skipped = 0
  for (let i = 0; i < manifest.files.length; i++) {
    const item = manifest.files[i]
    const sourcePath = item.targetPath
    if (!sourcePath.startsWith(sourcePrefix)) {
      continue
    }
    const relativePath = sourcePath.substring(sourcePrefix.length)
    if (relativePath.length === 0 || relativePath.startsWith('dosdevices/')) {
      continue
    }
    const targetPath = relativePath.startsWith('drive_c/') ?
      joinPath(driveCRoot, relativePath.substring('drive_c/'.length)) :
      joinPath(prefixPath, relativePath)
    const expectedSize = Number(item.size)
    if (expectedSize >= 0 && fileExistsWithSize(targetPath, expectedSize)) {
      skipped++
      continue
    }
    ensureDir(parentDir(targetPath))
    fs.copyFileSync(sourcePath, targetPath)
    copied++
  }
  for (let i = 0; i < EXTRA_DEFAULT_PREFIX_COPY_PATHS.length; i++) {
    const item = EXTRA_DEFAULT_PREFIX_COPY_PATHS[i]
    const sourcePath = joinPath(sourceRoot, item.source)
    const targetPath = defaultPrefixTargetPath(prefixPath, driveCRoot, item.target)
    if (!fileExists(sourcePath)) {
      emitLog('wine', `default prefix extra source missing: ${item.source}`)
      continue
    }
    const expectedSize = Number(fs.statSync(sourcePath).size)
    if (expectedSize >= 0 && fileExistsWithSize(targetPath, expectedSize)) {
      skipped++
      continue
    }
    ensureDir(parentDir(targetPath))
    fs.copyFileSync(sourcePath, targetPath)
    copied++
  }

  if (!fileExists(kernel32Path)) {
    emitLog('wine', `default prefix merge incomplete: missing ${kernel32Path}`)
    return
  }

  writeTextFile(markerPath, `source=${sourceRoot}\ncopied=${copied}\nskipped=${skipped}\n`)
  emitLog('wine', `default prefix merged: copied=${copied}, skipped=${skipped}, source=${sourceRoot}`)
}

function isWineFontAsset(path: string): boolean {
  const lower = path.toLowerCase()
  return lower.endsWith('.ttf') || lower.endsWith('.ttc') || lower.endsWith('.otf') || lower.endsWith('.fon')
}

function ensureWineFontFiles(prefixPath: string): void {
  const markerPath = joinPath(prefixPath, PREFIX_FONT_STACK_MARKER)
  const driveCRoot = prefixDriveCRootPath(prefixPath)
  const fontTargetDir = joinPath(driveCRoot, 'windows/Fonts')
  const manifestPath = joinPath(runtimeProtonStagePath(), MANIFEST_NAME)
  if (!fileExists(manifestPath)) {
    emitLog('wine', `font stack manifest missing: ${manifestPath}`)
    return
  }

  const manifest = JSON.parse(readTextFile(manifestPath)) as StageResult
  if (!manifest || !Array.isArray(manifest.files)) {
    emitLog('wine', `font stack manifest has no files: ${manifestPath}`)
    return
  }

  ensureDir(fontTargetDir)
  let copied = 0
  let skipped = 0
  for (let i = 0; i < manifest.files.length; i++) {
    const item = manifest.files[i]
    const sourcePath = item.targetPath
    let relativeFontPath = ''
    for (let p = 0; p < RUNTIME_FONT_RELATIVE_PREFIXES.length; p++) {
      const stagePrefix = joinPath(runtimeProtonStagePath(), RUNTIME_FONT_RELATIVE_PREFIXES[p])
      if (sourcePath.startsWith(stagePrefix)) {
        relativeFontPath = sourcePath.substring(stagePrefix.length)
        break
      }
    }
    if (relativeFontPath.length === 0 || relativeFontPath.indexOf('/') >= 0 || !isWineFontAsset(relativeFontPath)) {
      continue
    }
    const targetPath = joinPath(fontTargetDir, relativeFontPath)
    const expectedSize = Number(item.size)
    if (expectedSize >= 0 && fileExistsWithSize(targetPath, expectedSize)) {
      skipped++
      continue
    }
    fs.copyFileSync(sourcePath, targetPath)
    copied++
  }

  const linked = ensureHmosFontLinks(fontTargetDir)
  const registryPatched = ensureWineHmosFontRegistry(prefixPath)
  const settings = currentHmosSystemSettings()
  writeTextFile(markerPath,
    `copied=${copied}\nskipped=${skipped}\nhmosLinked=${linked.linked}\nhmosCopied=${linked.copied}\nhmosSkipped=${linked.skipped}\nregistryPatched=${registryPatched}\nfontFamily=${settings.fontFamily}\ncjkFontFamily=${settings.cjkFontFamily}\nfontPath=${settings.fontPath}\nlocale=${settings.locale}\n`)
  emitLog('wine', `font stack synced: copied=${copied}, skipped=${skipped}, hmosLinked=${linked.linked}, hmosCopied=${linked.copied}, hmosSkipped=${linked.skipped}, registryPatched=${registryPatched}, font=${settings.fontFamily}, cjk=${settings.cjkFontFamily}, target=${fontTargetDir}`)
}

interface HmosFontLinkResult {
  linked: number
  copied: number
  skipped: number
}

function appendUniqueFontPath(paths: string[], path: string): void {
  if (path.length === 0 || paths.length >= HMOS_FONT_SCAN_LIMIT || paths.indexOf(path) >= 0) {
    return
  }
  paths.push(path)
}

function collectHmosFontFiles(root: string, depth: number, paths: string[]): void {
  if (depth < 0 || paths.length >= HMOS_FONT_SCAN_LIMIT || !isDirectoryPath(root)) {
    return
  }
  const names = listFilesSafe(root)
  for (let i = 0; i < names.length && paths.length < HMOS_FONT_SCAN_LIMIT; i++) {
    const child = joinPath(root, names[i])
    if (isRegularFilePath(child) && isWineFontAsset(child)) {
      appendUniqueFontPath(paths, child)
    }
  }
  for (let i = 0; i < names.length && paths.length < HMOS_FONT_SCAN_LIMIT; i++) {
    const child = joinPath(root, names[i])
    if (isDirectoryPath(child)) {
      collectHmosFontFiles(child, depth - 1, paths)
    }
  }
}

function safeHmosFontTargetName(sourcePath: string): string {
  return leafName(sourcePath).replace(/[^A-Za-z0-9._-]/g, '_')
}

function linkOrCopyHmosFont(sourcePath: string, targetPath: string): string {
  try {
    const existing = fs.lstatSync(targetPath)
    if (existing.isSymbolicLink()) {
      fs.unlinkSync(targetPath)
    } else {
      return 'skipped'
    }
  } catch (_) {
  }

  ensureDir(parentDir(targetPath))
  try {
    fs.symlinkSync(sourcePath, targetPath)
    return 'linked'
  } catch (linkErr) {
    try {
      fs.copyFileSync(sourcePath, targetPath)
      return 'copied'
    } catch (copyErr) {
      emitLog('wine', `hmos font unavailable: ${sourcePath}: link=${errorMessage(linkErr)} copy=${errorMessage(copyErr)}`)
      return 'skipped'
    }
  }
}

function ensureHmosFontLinks(fontTargetDir: string): HmosFontLinkResult {
  const result: HmosFontLinkResult = {
    linked: 0,
    copied: 0,
    skipped: 0
  }
  const settings = currentHmosSystemSettings()
  const sourcePaths: string[] = []
  appendUniqueFontPath(sourcePaths, settings.fontPath)
  appendUniqueFontPath(sourcePaths, settings.cjkFontPath)
  const sourceDirs = hmosFontSourceDirs()
  for (let i = 0; i < sourceDirs.length; i++) {
    collectHmosFontFiles(sourceDirs[i], HMOS_FONT_SCAN_MAX_DEPTH, sourcePaths)
  }

  for (let i = 0; i < sourcePaths.length; i++) {
    const sourcePath = sourcePaths[i]
    const targetPath = joinPath(fontTargetDir, safeHmosFontTargetName(sourcePath))
    const status = linkOrCopyHmosFont(sourcePath, targetPath)
    if (status === 'linked') {
      result.linked++
    } else if (status === 'copied') {
      result.copied++
    } else {
      result.skipped++
    }
  }
  return result
}

function ensureWineHmosFontRegistry(prefixPath: string): number {
  const userReg = joinPath(prefixPath, 'user.reg')
  const systemReg = joinPath(prefixPath, 'system.reg')
  const settings = currentHmosSystemSettings()
  const uiFamily = settings.fontFamily.length > 0 ? settings.fontFamily : HMOS_UI_FONT_FAMILY
  const cjkFamily = settings.cjkFontFamily.length > 0 ? settings.cjkFontFamily : uiFamily
  let patched = 0

  patched += upsertWineUserRegString(prefixPath, 'Software\\\\Wine\\\\HMOS', 'FontFamily', uiFamily) ? 1 : 0
  patched += upsertWineUserRegString(prefixPath, 'Software\\\\Wine\\\\HMOS', 'CjkFontFamily', cjkFamily) ? 1 : 0
  patched += upsertWineUserRegString(prefixPath, 'Software\\\\Wine\\\\HMOS', 'FontPath', settings.fontPath) ? 1 : 0
  patched += upsertWineUserRegString(prefixPath, 'Software\\\\Wine\\\\HMOS', 'CjkFontPath', settings.cjkFontPath) ? 1 : 0
  patched += upsertWineUserRegString(prefixPath, 'Software\\\\Wine\\\\HMOS', 'FontSource', settings.fontSource) ? 1 : 0
  patched += upsertWineUserRegDword(prefixPath, 'Software\\\\Wine\\\\Fonts', 'LogPixels', 96) ? 1 : 0
  for (let i = 0; i < HMOS_UI_FONT_ALIASES.length; i++) {
    patched += upsertWineUserRegString(prefixPath, 'Software\\\\Wine\\\\Fonts\\\\Replacements', HMOS_UI_FONT_ALIASES[i], uiFamily) ? 1 : 0
    patched += upsertWineRegStringFile(systemReg, 'Software\\\\Microsoft\\\\Windows NT\\\\CurrentVersion\\\\FontSubstitutes', HMOS_UI_FONT_ALIASES[i], uiFamily) ? 1 : 0
  }
  for (let i = 0; i < HMOS_CJK_FONT_ALIASES.length; i++) {
    patched += upsertWineUserRegString(prefixPath, 'Software\\\\Wine\\\\Fonts\\\\Replacements', HMOS_CJK_FONT_ALIASES[i], cjkFamily) ? 1 : 0
    patched += upsertWineRegStringFile(systemReg, 'Software\\\\Microsoft\\\\Windows NT\\\\CurrentVersion\\\\FontSubstitutes', HMOS_CJK_FONT_ALIASES[i], cjkFamily) ? 1 : 0
  }
  for (let i = 0; i < HMOS_SYSTEM_FONT_REGISTRY_ENTRIES.length; i++) {
    patched += upsertWineRegStringFile(systemReg, 'Software\\\\Microsoft\\\\Windows NT\\\\CurrentVersion\\\\Fonts',
      HMOS_SYSTEM_FONT_REGISTRY_ENTRIES[i][0], HMOS_SYSTEM_FONT_REGISTRY_ENTRIES[i][1]) ? 1 : 0
  }
  if (settings.fontFileName.length > 0) {
    patched += upsertWineRegStringFile(systemReg, 'Software\\\\Microsoft\\\\Windows NT\\\\CurrentVersion\\\\Fonts',
      `${uiFamily} (TrueType)`, settings.fontFileName) ? 1 : 0
  }
  if (settings.cjkFontFileName.length > 0) {
    patched += upsertWineRegStringFile(systemReg, 'Software\\\\Microsoft\\\\Windows NT\\\\CurrentVersion\\\\Fonts',
      `${cjkFamily} (TrueType)`, settings.cjkFontFileName) ? 1 : 0
  }
  patched += upsertWineRegStringFile(systemReg, 'Software\\\\Microsoft\\\\Windows NT\\\\CurrentVersion\\\\FontSubstitutes', 'MS Shell Dlg', uiFamily) ? 1 : 0
  patched += upsertWineRegStringFile(systemReg, 'Software\\\\Microsoft\\\\Windows NT\\\\CurrentVersion\\\\FontSubstitutes', 'MS Shell Dlg 2', uiFamily) ? 1 : 0

  if (patched > 0) {
    emitLog('wine', `HMOS font registry patched entries=${patched} font=${uiFamily} cjk=${cjkFamily} user=${userReg} system=${systemReg}`)
  } else {
    emitLog('wine', `HMOS font registry already mapped font=${uiFamily} cjk=${cjkFamily}`)
  }
  return patched
}

async function copyRawFileContent(rawContext: common.Context, rawPath: string, targetPath: string, expectedSizeHint: number = -1, forceOverwrite: boolean = false): Promise<StagedFile> {
  ensureDir(parentDir(targetPath))
  if (!forceOverwrite && expectedSizeHint >= 0 && fileExistsWithSize(targetPath, expectedSizeHint)) {
    return {
      rawPath,
      targetPath,
      size: expectedSizeHint,
      hash: 'indexed-size-only',
      copied: false
    }
  }

  let bytes: Uint8Array
  try {
    bytes = await Promise.race([
      rawContext.resourceManager.getRawFileContent(rawPath),
      timeoutError<Uint8Array>(`read rawfile content timed out after ${RAWFILE_CONTENT_TIMEOUT_MS}ms: ${rawPath}`)
    ])
  } catch (err) {
    throw new Error(`read rawfile content failed: ${rawPath}: ${errorMessage(err)}`)
  }

  const expectedSize = bytes.byteLength
  if (!forceOverwrite && fileExistsWithSize(targetPath, expectedSize)) {
    return {
      rawPath,
      targetPath,
      size: expectedSize,
      hash: 'content-size-only',
      copied: false
    }
  }

  await yieldToEventLoop()
  const target = openWriteFile(targetPath)
  try {
    const buffer = new ArrayBuffer(expectedSize)
    new Uint8Array(buffer).set(bytes)
    writeChunk(target.fd, buffer, expectedSize)
  } finally {
    closeFile(target)
  }
  await yieldToEventLoop()

  return {
    rawPath,
    targetPath,
    size: expectedSize,
    hash: 'content-size-only',
    copied: true
  }
}

async function copyRawFile(rawContext: common.Context, rawPath: string, targetPath: string, expectedSizeHint: number = -1, forceOverwrite: boolean = false): Promise<StagedFile> {
  if (!forceOverwrite && expectedSizeHint >= 0 && fileExistsWithSize(targetPath, expectedSizeHint)) {
    return {
      rawPath,
      targetPath,
      size: expectedSizeHint,
      hash: 'indexed-size-only',
      copied: false
    }
  }

  if (shouldUseContentCopy(rawPath)) {
    return await copyRawFileContent(rawContext, rawPath, targetPath, expectedSizeHint, forceOverwrite)
  }

  const context = rawContext
  const descriptor = await openRawDescriptor(context, rawPath)
  const expectedSize = Number(descriptor.length)
  ensureDir(parentDir(targetPath))

  if (!forceOverwrite && fileExistsWithSize(targetPath, expectedSize)) {
    await closeRawDescriptor(context, rawPath)
    return {
      rawPath,
      targetPath,
      size: expectedSize,
      hash: 'size-only',
      copied: false
    }
  }

  const target = openWriteFile(targetPath)
  let copied = 0
  let hash = 2166136261
  const buffer = new ArrayBuffer(COPY_CHUNK_SIZE)
  try {
    while (copied < expectedSize) {
      const readLen = Math.min(COPY_CHUNK_SIZE, expectedSize - copied)
      const n = await readChunk(descriptor.fd, buffer, descriptor.offset + copied, readLen)
      if (!n || n <= 0) {
        break
      }
      const view = new Uint8Array(buffer)
      hash = updateHash(hash, view, n)
      writeChunk(target.fd, buffer, n)
      copied += n
      if (copied % (COPY_CHUNK_SIZE * 8) === 0) {
        await yieldToEventLoop()
      }
    }
  } finally {
    closeFile(target)
    await closeRawDescriptor(context, rawPath)
  }

  return {
    rawPath,
    targetPath,
    size: copied,
    hash: toHex32(hash),
    copied: true
  }
}

async function collectRawFiles(rawContext: common.Context, rawRoot: string, current: string, out: IndexedRawfile[]): Promise<void> {
  const context = rawContext
  if (current !== rawRoot && await tryOpenRawFile(context, current)) {
    const relativePath = current.substring(rawRoot.length).replace(/^\/+/, '')
    if (shouldSkipRawfileLeaf(current) || shouldSkipRuntimeRelativePath(relativePath)) {
      return
    }
    out.push({
      rawPath: current,
      size: -1
    })
    return
  }

  const entries = await listRawEntries(context, current)
  for (let i = 0; i < entries.length; i++) {
    const name = entries[i]
    if (name.length === 0) {
      continue
    }
    if (name === '.gitkeep' || name === 'PROTON_PLACEHOLDER.txt' || name === RAWFILE_INDEX_NAME || name === '.proton-rawfile-index.json') {
      continue
    }
    const child = joinPath(current, name)
    await collectRawFiles(context, rawRoot, child, out)
  }
}

function quoteCommandArg(value: string): string {
  return `"${value.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`
}

function buildCommandLine(options: LaunchOptions): string {
  const args = options.args ? options.args : []
  const commandParts: string[] = [
    runtimeWineLoaderPath(),
    options.targetPath
  ]
  for (let i = 0; i < args.length; i++) {
    commandParts.push(args[i])
  }
  return commandParts.map((item: string): string => quoteCommandArg(item)).join(' ')
}

function stageLaunchTargetInPrefix(prefix: PrefixResult, targetPath: string): string {
  const targetStat = fs.statSync(targetPath)
  const targetParent = parentDir(targetPath)
  const sourceDirKey = sanitizeName(parentDir(targetPath))
  const driveTargetDir = joinPath(joinPath(prefixHmosDriveRoot(prefix), 'launch'), sourceDirKey)
  const driveTargetPath = joinPath(driveTargetDir, leafName(targetPath))
  ensureDir(driveTargetDir)
  if (!fileExistsWithSize(driveTargetPath, Number(targetStat.size))) {
    fs.copyFileSync(targetPath, driveTargetPath)
    emitLog('wine', `launch target copied into HMOS drive: ${driveTargetPath}`)
  } else {
    emitLog('wine', `launch target ready in HMOS drive: ${driveTargetPath}`)
  }
  const companionNames: string[] = [
    'uxtheme.dll'
  ]
  for (let i = 0; i < companionNames.length; i++) {
    const companionSource = joinPath(targetParent, companionNames[i])
    if (!fileExists(companionSource)) {
      continue
    }
    const companionStat = fs.statSync(companionSource)
    const companionTarget = joinPath(driveTargetDir, companionNames[i])
    if (!fileExistsWithSize(companionTarget, Number(companionStat.size))) {
      fs.copyFileSync(companionSource, companionTarget)
      emitLog('wine', `launch companion copied into HMOS drive: ${companionTarget}`)
    } else {
      emitLog('wine', `launch companion ready in HMOS drive: ${companionTarget}`)
    }
  }
  return driveTargetPath
}

function prefixDriveCRoot(prefix: PrefixResult): string {
  return prefixDriveCRootPath(prefix.prefixPath)
}

function prefixBridgeRoot(prefix: PrefixResult): string {
  return joinPath(prefixHmosDriveRoot(prefix), PREFIX_HMOS_BRIDGE_DIR)
}

function prefixBrokerRoot(prefix: PrefixResult): string {
  return joinPath(prefixBridgeRoot(prefix), 'process-broker')
}

function hmosAppRoot(prefix: PrefixResult): string {
  return joinPath(prefixHmosDriveRoot(prefix), PREFIX_HMOS_APPS_DIR)
}

function hmosInstallerRoot(prefix: PrefixResult): string {
  return joinPath(prefixHmosDriveRoot(prefix), PREFIX_HMOS_INSTALLERS_DIR)
}

function hmosProfileRoot(prefix: PrefixResult): string {
  return joinPath(prefixHmosDriveRoot(prefix), PREFIX_HMOS_PROFILES_DIR)
}

function hmosInstallRecordRoot(prefix: PrefixResult): string {
  return joinPath(prefixHmosDriveRoot(prefix), PREFIX_HMOS_INSTALL_RECORDS_DIR)
}

function prefixHmosDriveRoot(prefix: PrefixResult): string {
  return prefixHmosDriveRootPath(prefix.prefixPath)
}

function prefixHmosDriveRootPath(prefixPath: string): string {
  const dosDrive = joinPath(joinPath(prefixPath, 'dosdevices'), PREFIX_HMOS_DRIVE_LETTER)
  try {
    const stat = fs.lstatSync(dosDrive)
    if (!stat.isSymbolicLink() && stat.isDirectory()) {
      return dosDrive
    }
  } catch (_) {
  }
  return joinPath(prefixPath, PREFIX_HMOS_DRIVE_DIR)
}

function existingPrefixResult(prefixName: string): PrefixResult {
  const context = requireContext()
  const cleanPrefix = sanitizeName(prefixName)
  return {
    prefixName: cleanPrefix,
    prefixPath: joinPath(joinPath(context.filesDir, PREFIX_ROOT_DIR), cleanPrefix),
    created: false
  }
}

function prefixDriveCRootPath(prefixPath: string): string {
  const dosDrive = joinPath(joinPath(prefixPath, 'dosdevices'), 'c:')
  try {
    const stat = fs.lstatSync(dosDrive)
    if (!stat.isSymbolicLink() && stat.isDirectory()) {
      return dosDrive
    }
  } catch (_) {
  }
  return joinPath(prefixPath, 'drive_c')
}

function winePathForHostPath(targetPath: string): string {
  if (targetPath.startsWith('/')) {
    return `Z:${targetPath.replace(/\//g, '\\')}`
  }
  return targetPath
}

function winePathForHmosDrive(prefix: PrefixResult, targetPath: string): string {
  const driveRoot = joinPath(prefix.prefixPath, PREFIX_HMOS_DRIVE_DIR)
  const dosDriveRoot = joinPath(joinPath(prefix.prefixPath, 'dosdevices'), PREFIX_HMOS_DRIVE_LETTER)
  if (targetPath === driveRoot || targetPath === dosDriveRoot) {
    return 'H:\\'
  }
  if (targetPath.startsWith(`${driveRoot}/`)) {
    const relativePath = targetPath.substring(driveRoot.length + 1).replace(/\//g, '\\')
    return `H:\\${relativePath}`
  }
  if (targetPath.startsWith(`${dosDriveRoot}/`)) {
    const relativePath = targetPath.substring(dosDriveRoot.length + 1).replace(/\//g, '\\')
    return `H:\\${relativePath}`
  }
  return targetPath
}

function winePathForPrefixDriveC(prefix: PrefixResult, targetPath: string): string {
  const driveRoot = joinPath(prefix.prefixPath, 'drive_c')
  const dosDriveRoot = joinPath(joinPath(prefix.prefixPath, 'dosdevices'), 'c:')
  if (targetPath === driveRoot) {
    return 'C:\\'
  }
  if (targetPath === dosDriveRoot) {
    return 'C:\\'
  }
  if (targetPath.startsWith(`${driveRoot}/`)) {
    const relativePath = targetPath.substring(driveRoot.length + 1).replace(/\//g, '\\')
    return `C:\\${relativePath}`
  }
  if (targetPath.startsWith(`${dosDriveRoot}/`)) {
    const relativePath = targetPath.substring(dosDriveRoot.length + 1).replace(/\//g, '\\')
    return `C:\\${relativePath}`
  }
  return targetPath
}

function runtimeBox64ExecutablePath(): string {
  return runtimeBox64Path.length > 0 ? runtimeBox64Path : RUNTIME_BOX64_IN_PROCESS
}

function runtimeProtonStagePath(): string {
  const context = requireContext()
  if (runtimeProtonPath.length > 0) {
    return runtimeProtonPath
  }
  return joinPath(joinPath(context.filesDir, STAGE_ROOT_DIR), RUNTIME_PROTON_TARGET_NAME)
}

function runtimeWineLoaderPath(): string {
  return joinPath(runtimeProtonStagePath(), RUNTIME_WINE_LOADER_RELATIVE_PATH)
}

function runtimeHspPathCandidates(context: common.UIAbilityContext): string[] {
  const appInfo = context.applicationInfo as RuntimeApplicationInfo
  if (!appInfo.codePath || appInfo.codePath.length === 0) {
    return []
  }
  const candidates: string[] = [
    joinPath(appInfo.codePath, 'proton.hsp'),
    joinPath(parentDir(appInfo.codePath), 'proton.hsp')
  ]
  const bundleName = appInfo.bundleName && appInfo.bundleName.length > 0 ? appInfo.bundleName : appInfo.name
  if (bundleName && bundleName.length > 0) {
    candidates.push(`/data/app/el1/bundle/public/${bundleName}/proton.hsp`)
  }
  return candidates
}

function runtimeRawDirCandidates(context: common.UIAbilityContext): string[] {
  const appInfo = context.applicationInfo as RuntimeApplicationInfo
  if (!appInfo.codePath || appInfo.codePath.length === 0) {
    return []
  }
  const candidates: string[] = [
    joinPath(appInfo.codePath, 'proton/resources/rawfile/runtime/proton'),
    joinPath(parentDir(appInfo.codePath), 'proton/resources/rawfile/runtime/proton')
  ]
  const bundleName = appInfo.bundleName && appInfo.bundleName.length > 0 ? appInfo.bundleName : appInfo.name
  if (bundleName && bundleName.length > 0) {
    candidates.push(`/data/app/el1/bundle/public/${bundleName}/proton/resources/rawfile/runtime/proton`)
  }
  return candidates
}

function envelopeValue(value: string): string {
  return value.replace(/\r/g, ' ').replace(/\n/g, ' ')
}

function envKeyOf(line: string): string {
  const index = line.indexOf('=')
  return index > 0 ? line.substring(0, index) : line
}

function envValueOf(lines: string[] | undefined, key: string, fallback: string): string {
  if (!lines) {
    return fallback
  }
  for (let i = lines.length - 1; i >= 0; i--) {
    const line = lines[i]
    if (envKeyOf(line) === key) {
      const split = line.indexOf('=')
      return split >= 0 ? line.substring(split + 1) : ''
    }
  }
  return fallback
}

function shouldUseFrameBridgeFallback(options: LaunchOptions): boolean {
  const target = options.targetPath.toLowerCase()
  if (target.indexOf('explorer.exe') >= 0 || target.indexOf('winefile.exe') >= 0) {
    return true
  }
  return envValueOf(options.env, 'WINE_HMOS_COMPOSITOR', '') === 'fallback'
}

function selectedCompositorMode(options: LaunchOptions): string {
  const requested = envValueOf(options.env, 'WINE_HMOS_COMPOSITOR', '')
  if (requested.length > 0) {
    return requested
  }
  if (!options.xcomponentId || options.xcomponentId.length === 0) {
    return RUNTIME_WINE_HMOS_COMPOSITOR
  }
  return shouldUseFrameBridgeFallback(options) ? 'native' : 'vulkan'
}

function selectedFrameBridgeMode(options: LaunchOptions, compositorMode: string): string {
  const requested = envValueOf(options.env, 'WINE_HMOS_FRAME_BRIDGE', '')
  if (requested.length > 0) {
    return requested
  }
  return compositorMode === 'fallback' || shouldUseFrameBridgeFallback(options) ? '1' : '0'
}

function withoutEnvKeys(lines: string[] | undefined, keys: string[]): string[] {
  if (!lines) {
    return []
  }
  const filtered: string[] = []
  for (let i = 0; i < lines.length; i++) {
    const key = envKeyOf(lines[i])
    let blocked = false
    for (let k = 0; k < keys.length; k++) {
      if (key === keys[k]) {
        blocked = true
        break
      }
    }
    if (!blocked) {
      filtered.push(lines[i])
    }
  }
  return filtered
}

function buildLaunchRequest(options: LaunchOptions, prefix: PrefixResult, commandLine: string): string {
  const workdir = options.workingDirectory && options.workingDirectory.length > 0 ? options.workingDirectory : parentDir(options.targetPath)
  const protonPath = runtimeProtonStagePath()
  const bridgeRoot = prefixBridgeRoot(prefix)
  const brokerRoot = prefixBrokerRoot(prefix)
  ensureDir(bridgeRoot)
  ensureDir(brokerRoot)
  const requestedExecMode = envValueOf(options.env, 'WINE_HMOS_EXEC_BACKEND', '')
  const execMode = requestedExecMode.length > 0 ? requestedExecMode : selectWineExecMode()
  const compositorMode = selectedCompositorMode(options)
  const frameBridgeMode = selectedFrameBridgeMode(options, compositorMode)
  const graphics = nativeBridge.queryGraphicsCapabilities()
  const settings = currentHmosSystemSettings()
  const ldLibraryPath = [
    joinPath(protonPath, 'files/lib'),
    joinPath(protonPath, 'files/lib/x86_64-linux-gnu'),
    joinPath(protonPath, 'files/lib/i386-linux-gnu')
  ].join(':')
  const winDllPath = joinPath(protonPath, 'files/lib/wine')
  const envLines: string[] = [
    'BOX64_DYNAREC=0',
    'BOX64_LOG=1',
    'BOX64_NOBANNER=1',
    `BOX64_LD_LIBRARY_PATH=${ldLibraryPath}`,
    `WINEPREFIX=${prefix.prefixPath}`,
    'WINEARCH=win64',
    `WINELOADER=${runtimeWineLoaderPath()}`,
    'WINELOADERNOEXEC=1',
    'WINE_HMOS_PROCESS_MODEL=in-process-so',
    'WINE_HMOS_INPROCESS_STRICT=0',
    `WINE_HMOS_EXEC_BACKEND=${execMode}`,
    `WINE_HMOS_PROCESS_BROKER_DIR=${brokerRoot}`,
    `WINE_HMOS_PROCESS_BROKER_ENTRY=${WINE_CHILD_ENTRY_POINT}`,
    'WINE_HMOS_SKIP_WINEBOOT=1',
    `WINE_HMOS_DRIVER=${RUNTIME_WINE_HMOS_DRIVER}`,
    `WINE_HMOS_GRAPHICS_BACKEND=${RUNTIME_WINE_HMOS_GRAPHICS_BACKEND}`,
    `WINE_HMOS_COMPOSITOR=${compositorMode}`,
    `WINE_HMOS_FRAME_BRIDGE=${frameBridgeMode}`,
    `WINE_HMOS_TRACE=${RUNTIME_WINE_HMOS_TRACE}`,
    `WINE_HMOS_LOG_DIR=${bridgeRoot}`,
    `WINE_HMOS_VULKAN_SURFACE_BACKEND=${graphics.hasArkUiVulkanSurface ? 'VK_OHOS_surface' : 'unavailable'}`,
    `WINE_HMOS_VULKAN_HAS_OHOS_SURFACE=${graphics.hasOhosSurface ? '1' : '0'}`,
    `WINE_HMOS_VULKAN_HAS_SWAPCHAIN=${graphics.hasSwapchain ? '1' : '0'}`,
    `WINE_HMOS_FONT_FAMILY=${settings.fontFamily}`,
    `WINE_HMOS_CJK_FONT_FAMILY=${settings.cjkFontFamily}`,
    `WINE_HMOS_FONT_PATH=${settings.fontPath}`,
    `WINE_HMOS_FONT_SOURCE=${settings.fontSource}`,
    `WINE_HMOS_FONT_DIR=${joinPath(protonPath, 'files/share/fonts')}`,
    `WINE_HMOS_SYSTEM_LOCALE=${settings.locale}`,
    `WINE_HMOS_SYSTEM_LANGUAGE=${settings.language}`,
    `WINE_HMOS_SYSTEM_REGION=${settings.region}`,
    `WINE_HMOS_FIRST_PREFERRED_LANGUAGE=${settings.firstPreferredLanguage}`,
    `WINE_HMOS_PREFERRED_LANGUAGES=${settings.preferredLanguages}`,
    `WINE_HMOS_POSIX_LOCALE=${settings.posixLocale}`,
    `LANG=${settings.posixLocale}`,
    `LC_ALL=${settings.posixLocale}`,
    `LC_CTYPE=${settings.posixLocale}`,
    `LANGUAGE=${settings.gnuLanguage}`,
    'WINE_HMOS_DISABLE_X11=1',
    'WINEDLLOVERRIDES=uxtheme=b',
    `WINE_HMOS_SERVER_LIBRARY=${RUNTIME_WINE_SERVER_LIBRARY}`,
    `WINE_HMOS_NTDLL_SO=${joinPath(runtimeProtonStagePath(), 'files/lib/wine/x86_64-unix/ntdll.so')}`,
    `WINESERVER=${joinPath(protonPath, 'files/bin/wineserver')}`,
    `WINEDLLPATH=${winDllPath}`,
    `LD_LIBRARY_PATH=${ldLibraryPath}`,
    `PATH=${joinPath(protonPath, 'files/bin')}`,
    'WINEDEBUG=-all',
    'DXVK_LOG_LEVEL=info',
    `DXVK_LOG_PATH=${bridgeRoot}`,
    'VKD3D_DEBUG=warn',
    `VKD3D_LOG_FILE=${joinPath(bridgeRoot, 'vkd3d.log')}`
  ]
  emitLog('vulkan', `wineonarkui mode=${compositorMode} frameBridge=${frameBridgeMode} present=${graphics.presentBackend} ohosSurface=${graphics.hasOhosSurface ? 'yes' : 'no'} swapchainDevices=${graphics.swapchainDeviceCount}`)
  if (options.xcomponentId && options.xcomponentId.length > 0) {
    const surface = nativeBridge.mountSurface(options.xcomponentId)
    const frameFileName = hmosFrameFileName(options.xcomponentId)
    const inputFileName = hmosInputFileName(options.xcomponentId)
    const hostFramePath = joinPath(bridgeRoot, frameFileName)
    const hostInputPath = joinPath(bridgeRoot, inputFileName)
    const hostInputSurfacesPath = `${hostInputPath}.surfaces`
    try {
      ensureDir(parentDir(hostInputPath))
      if (!fileExists(hostInputPath)) {
        writeTextFile(hostInputPath, '')
      }
      writeTextFile(hostInputSurfacesPath, '')
    } catch (err) {
      emitLog('input', `input bridge precreate failed: ${hostInputPath}: ${errorMessage(err)}`)
    }
    envLines.push(`WINE_HMOS_XCOMPONENT_ID=${options.xcomponentId}`)
    envLines.push(`WINE_HMOS_SURFACE_MAP=${options.xcomponentId}`)
    envLines.push(`WINE_HMOS_FRAME_PATH=${winePathForHmosDrive(prefix, hostFramePath)}`)
    envLines.push(`WINE_HMOS_HOST_FRAME_PATH=${hostFramePath}`)
    envLines.push(`WINE_HMOS_INPUT_PATH=${winePathForHmosDrive(prefix, hostInputPath)}`)
    envLines.push(`WINE_HMOS_HOST_INPUT_PATH=${hostInputPath}`)
    envLines.push(`WINE_HMOS_INPUT_SURFACES_PATH=${winePathForHmosDrive(prefix, hostInputSurfacesPath)}`)
    envLines.push(`WINE_HMOS_HOST_INPUT_SURFACES_PATH=${hostInputSurfacesPath}`)
    envLines.push('WINE_HMOS_INPUT_BACKEND=surface-map')
    envLines.push(`WINE_HMOS_MARKER_PATH=${winePathForHmosDrive(prefix, joinPath(bridgeRoot, 'tinygame-entry.txt'))}`)
    envLines.push(`WINE_HMOS_HOST_MARKER_PATH=${joinPath(bridgeRoot, 'tinygame-entry.txt')}`)
    envLines.push(`WINE_HMOS_HOST_EXPLORER_STATUS_PATH=${joinPath(bridgeRoot, 'hmos-explorer-status.txt')}`)
    envLines.push(`WINE_HMOS_GRAPHICS_BACKEND=${RUNTIME_WINE_HMOS_GRAPHICS_BACKEND}`)
    if (surface.success && surface.windowHandle && surface.windowHandle.length > 0) {
      envLines.push(`WINE_HMOS_NATIVE_WINDOW=${surface.windowHandle}`)
      envLines.push(`WINE_HMOS_SURFACE_WIDTH=${surface.width ? surface.width : 0}`)
      envLines.push(`WINE_HMOS_SURFACE_HEIGHT=${surface.height ? surface.height : 0}`)
    }
  }
  const lines: string[] = [
    `box64=${envelopeValue(runtimeBox64ExecutablePath())}`,
    `entry=${envelopeValue(RUNTIME_WINE_ENTRY_SYMBOL)}`,
    `prefix=${envelopeValue(prefix.prefixPath)}`,
    `runtime=${envelopeValue(protonPath)}`,
    `workdir=${envelopeValue(workdir)}`,
    `cmd=${envelopeValue(commandLine)}`
  ]
  if (options.xcomponentId && options.xcomponentId.length > 0) {
    lines.push(`xcomponent=${envelopeValue(options.xcomponentId)}`)
  }
  for (let i = 0; i < envLines.length; i++) {
    lines.push(`env.${i}=${envelopeValue(envLines[i])}`)
  }
  if (options.env) {
    for (let i = 0; i < options.env.length; i++) {
      lines.push(`env.${envLines.length + i}=${envelopeValue(options.env[i])}`)
    }
  }
  return lines.join('\n')
}

function failedLaunch(kind: string, targetPath: string, commandLine: string, status: string, reason: string): LaunchSession {
  const sessionId = `${kind}-${Date.now()}`
  const result: LaunchSession = {
    sessionId,
    kind,
    targetPath,
    prefixPath: '',
    status,
    commandLine,
    reason
  }
  emitLog('process', `${kind} rejected: ${reason}`)
  emitState(sessionId, status, reason)
  return result
}

function chooseExecMode(deviceType: string, childProcessReady: boolean, workerReady: boolean, taskpoolReady: boolean, shortLived: boolean = false): ExecMode {
  const bigScreen = deviceType === 'tablet' || deviceType === '2in1' || deviceType === 'pc'
  if (bigScreen && childProcessReady) {
    return ExecMode.NATIVE_CHILD_PROCESS
  }
  if (!shortLived && workerReady) {
    return ExecMode.WORKER_EMULATED_PROCESS
  }
  if (taskpoolReady) {
    return ExecMode.TASKPOOL_EMULATED_PROCESS
  }
  return ExecMode.WORKER_EMULATED_PROCESS
}

export function probeExecutionCapabilities(): ExecutionCapabilities {
  let deviceTypeValue = 'unknown'
  let sdkApiVersionValue = 0
  try {
    deviceTypeValue = deviceInfo.deviceType
    sdkApiVersionValue = deviceInfo.sdkApiVersion
  } catch (err) {
    emitLog('broker', `deviceInfo probe failed: ${errorMessage(err)}`)
  }

  const childProcessSyscap = canUseSystemCapability(WINE_PROCESS_SYSCAP)
  const langSyscap = canUseSystemCapability('SystemCapability.Utils.Lang')
  const bigScreen = deviceTypeValue === 'tablet' || deviceTypeValue === '2in1' || deviceTypeValue === 'pc'
  const nativeChildProcess = bigScreen && childProcessSyscap
  const workerAvailable = langSyscap
  const taskpoolAvailable = langSyscap
  const selectedMode = chooseExecMode(deviceTypeValue, nativeChildProcess, workerAvailable, taskpoolAvailable)
  const reason = nativeChildProcess ?
    `native child process selected for ${deviceTypeValue}` :
    `native child process unavailable for ${deviceTypeValue}; forcing ${selectedMode}`
  const result: ExecutionCapabilities = {
    deviceType: deviceTypeValue,
    sdkApiVersion: sdkApiVersionValue,
    childProcessSyscap,
    nativeChildProcess,
    workerAvailable,
    taskpoolAvailable,
    selectedMode,
    reason
  }
  emitLog('broker', `capabilities device=${result.deviceType} api=${result.sdkApiVersion} child=${result.nativeChildProcess ? 'yes' : 'no'} worker=${result.workerAvailable ? 'yes' : 'no'} taskpool=${result.taskpoolAvailable ? 'yes' : 'no'} selected=${result.selectedMode}`)
  return result
}

export function selectWineExecMode(): ExecMode {
  return probeExecutionCapabilities().selectedMode
}

function prepareLaunch(kind: string, options: LaunchOptions): LaunchSession | string {
  const winePath = runtimeWineLoaderPath()
  if (!fileExists(winePath)) {
    return failedLaunch(kind, options.targetPath, '', 'missing-wine-payload', `Wine guest loader SO not staged: ${winePath}`)
  }
  chmodExecutableIfPresent(winePath)
  if (!options.targetIsWinePath && !fileExists(options.targetPath)) {
    return failedLaunch(kind, options.targetPath, '', 'missing-target', `target executable not found: ${options.targetPath}`)
  }

  const prefix = createOrOpenPrefix(options.prefixName ? options.prefixName : 'default')
  ensureWineWin11Prefix(prefix.prefixPath)
  ensureWineHmosPrefix(prefix.prefixPath)
  ensureWineGraphicsDriverPrefix(prefix.prefixPath)
  const launchTargetPath = options.targetIsWinePath ? options.targetPath : stageLaunchTargetInPrefix(prefix, options.targetPath)
  const launchTargetWinePath = options.targetIsWinePath ? options.targetPath : winePathForHmosDrive(prefix, launchTargetPath)
  const launchOptions: LaunchOptions = {
    targetPath: launchTargetWinePath,
    targetIsWinePath: options.targetIsWinePath,
    prefixName: options.prefixName,
    args: options.args,
    workingDirectory: options.workingDirectory && options.workingDirectory.length > 0 ?
      options.workingDirectory :
      (options.targetIsWinePath ? prefixDriveCRoot(prefix) : parentDir(options.targetPath)),
    env: options.env,
    xcomponentId: options.xcomponentId
  }
  const commandLine = buildCommandLine(launchOptions)
  return [
    `prepared.kind=${kind}`,
    `prepared.target=${envelopeValue(launchTargetPath)}`,
    `prepared.prefix=${envelopeValue(prefix.prefixPath)}`,
    buildLaunchRequest(launchOptions, prefix, commandLine)
  ].join('\n')
}

function launchSessionFromEnvelope(kind: string, targetPath: string, prefixPath: string, commandLine: string, nativeSession: NativeLaunchSession): LaunchSession {
  const sessionId = `${kind}-${Date.now()}`
  const result: LaunchSession = {
    sessionId,
    kind,
    targetPath,
    prefixPath,
    status: nativeSession.status,
    commandLine,
    reason: nativeSession.reason,
    exitCode: nativeSession.exitCode
  }
  emitLog('process', `${kind} native result: ${result.status}, exit=${result.exitCode}, reason=${result.reason}`)
  emitState(sessionId, result.status, result.reason ? result.reason : 'session created')
  return result
}

function envelopeField(envelope: string, key: string): string {
  const lines = envelope.split('\n')
  const prefix = `${key}=`
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].startsWith(prefix)) {
      return lines[i].substring(prefix.length)
    }
  }
  return ''
}

function nativeSessionFromJson(value: string): NativeLaunchSession {
  try {
    const parsed = JSON.parse(value) as NativeLaunchSession
    return {
      sessionId: parsed.sessionId ? parsed.sessionId : 'emulated-process',
      status: parsed.status ? parsed.status : 'runtime-error',
      reason: parsed.reason ? parsed.reason : 'no reason returned',
      exitCode: parsed.exitCode
    }
  } catch (err) {
    return {
      sessionId: 'emulated-process',
      status: 'runtime-error',
      reason: `invalid task result: ${errorMessage(err)}`
    }
  }
}

function isWorkerResultMessage(value: Object): boolean {
  const message = value as WineWorkerResultMessage
  return typeof message.type === 'string' &&
    typeof message.requestId === 'string' &&
    typeof message.slotId === 'number' &&
    typeof message.status === 'string'
}

function parseBrokerRequest(content: string): Record<string, string> {
  const fields: Record<string, string> = {}
  const lines = content.split('\n')
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim()
    if (line.length === 0 || line.startsWith('#')) {
      continue
    }
    const index = line.indexOf('=')
    if (index <= 0) {
      continue
    }
    fields[line.substring(0, index)] = line.substring(index + 1)
  }
  return fields
}

function cleanWineDebugString(value: string): string {
  let text = value.trim()
  if (text.startsWith('L"') && text.endsWith('"')) {
    text = text.substring(2, text.length - 1)
  } else if (text.startsWith('"') && text.endsWith('"')) {
    text = text.substring(1, text.length - 1)
  }
  return text.replace(/\\\\/g, '\\')
}

function splitBrokerCommandLine(commandLine: string): string[] {
  const tokens: string[] = []
  let current = ''
  let quoted = false
  for (let i = 0; i < commandLine.length; i++) {
    const ch = commandLine.charAt(i)
    if (ch === '"') {
      quoted = !quoted
      continue
    }
    if (!quoted && (ch === ' ' || ch === '\t')) {
      if (current.length > 0) {
        tokens.push(current)
        current = ''
      }
      continue
    }
    current += ch
  }
  if (current.length > 0) {
    tokens.push(current)
  }
  return tokens
}

function brokerRequestArgv(fields: Record<string, string>): string[] {
  const args: string[] = []
  const argcText = fields['argc'] ? fields['argc'] : ''
  const argc = argcText.length > 0 ? Number.parseInt(argcText) : 0
  const limit = argc > 0 ? Math.min(argc, 64) : 64
  for (let i = 0; i < limit; i++) {
    const key = `argv.${i}`
    if (!fields[key]) {
      if (argc > 0) {
        continue
      }
      break
    }
    args.push(cleanWineDebugString(fields[key]))
  }
  return args
}

function targetEndsWithWindowsProgram(target: string, executableName: string): boolean {
  const lower = target.toLowerCase().replace(/\//g, '\\')
  return lower === executableName || lower.endsWith(`\\${executableName}`)
}

function isRundllControlRunDllLaunch(target: string, args: string[]): boolean {
  if (!targetEndsWithWindowsProgram(target, 'rundll32.exe') || args.length === 0) {
    return false
  }
  const entry = args[0].toLowerCase()
  return entry === 'shell32.dll,control_rundll' ||
    entry === 'shell32.dll,control_rundllw' ||
    entry === 'shell32.dll,control_rundlla'
}

function normalizeControlPanelAppletArg(value: string): string {
  let text = value.trim()
  if (text.length >= 4) {
    const first = text.charAt(0)
    if ((first === '\\' || first === '/') && text.charAt(2) === ':') {
      text = text.substring(1)
    }
  }
  return text.replace(/\\,/g, ',').replace(/\/,/g, ',')
}

function normalizeRundllControlRunDllArgs(target: string, args: string[]): string[] {
  if (!isRundllControlRunDllLaunch(target, args)) {
    return args
  }
  const normalized: string[] = []
  for (let i = 0; i < args.length; i++) {
    const before = args[i]
    const after = i === 0 ? before : normalizeControlPanelAppletArg(before)
    if (after !== before) {
      emitLog('broker', `normalized Control_RunDLL arg ${i}: ${before} -> ${after}`)
    }
    normalized.push(after)
  }
  return normalized
}

function normalizeRundllControlRunDllParts(target: string, parts: string[]): string[] {
  if (parts.length < 3 || !targetEndsWithWindowsProgram(target, 'rundll32.exe')) {
    return parts
  }
  let targetIndex = -1
  for (let i = 1; i < parts.length; i++) {
    if (parts[i] === target || targetEndsWithWindowsProgram(parts[i], 'rundll32.exe')) {
      targetIndex = i
      break
    }
  }
  if (targetIndex < 0 || targetIndex + 1 >= parts.length) {
    return parts
  }
  const args = parts.slice(targetIndex + 1)
  const normalizedArgs = normalizeRundllControlRunDllArgs(target, args)
  if (normalizedArgs === args) {
    return parts
  }
  return parts.slice(0, targetIndex + 1).concat(normalizedArgs)
}

function isWineProgramToken(value: string): boolean {
  const lower = value.toLowerCase()
  return lower.indexOf(':\\') > 0 ||
    lower.startsWith('\\\\') ||
    lower.endsWith('.exe') ||
    lower.endsWith('.com') ||
    lower.endsWith('.bat') ||
    lower.endsWith('.cmd') ||
    lower.endsWith('.msi')
}

function isBrokerLoaderPath(value: string): boolean {
  const lower = value.toLowerCase().replace(/\\/g, '/')
  return lower.endsWith('/wine-hmos-loader.so') ||
    lower.endsWith('/wine64') ||
    lower.endsWith('/wine') ||
    lower.endsWith('/wine64-preloader') ||
    lower.endsWith('/wine-preloader') ||
    lower.endsWith('/box64-hmos-inprocess')
}

function isBrokerPreloaderPath(value: string): boolean {
  const lower = value.toLowerCase().replace(/\\/g, '/')
  return lower.endsWith('/wine64-preloader') || lower.endsWith('/wine-preloader')
}

function firstWineProgramToken(tokens: string[]): string {
  for (let i = 0; i < tokens.length; i++) {
    const token = tokens[i]
    if (token.length > 0 && isWineProgramToken(token) && !isBrokerLoaderPath(token)) {
      return token
    }
  }
  return ''
}

function brokerRequestTarget(fields: Record<string, string>): string {
  const image = fields['image'] ? cleanWineDebugString(fields['image']) : ''
  if (image.length > 0) {
    return image
  }
  const argvTarget = firstWineProgramToken(brokerRequestArgv(fields))
  if (argvTarget.length > 0) {
    return argvTarget
  }
  const commandLine = fields['cmd'] ? cleanWineDebugString(fields['cmd']) : ''
  const tokens = splitBrokerCommandLine(commandLine)
  const commandTarget = firstWineProgramToken(tokens)
  if (commandTarget.length > 0) {
    return commandTarget
  }
  const path = fields['path'] ? cleanWineDebugString(fields['path']) : ''
  if (path.length > 0 && !isBrokerLoaderPath(path)) {
    return path
  }
  return tokens.length > 0 && !isBrokerLoaderPath(tokens[0]) ? tokens[0] : ''
}

function brokerRequestArgs(fields: Record<string, string>, target: string): string[] {
  const argv = brokerRequestArgv(fields)
  if (argv.length > 0 && target.length > 0) {
    const result: string[] = []
    let sawTarget = false
    for (let i = 0; i < argv.length; i++) {
      const token = argv[i]
      if (!sawTarget) {
        if (token === target) {
          sawTarget = true
        }
        continue
      }
      result.push(token)
    }
    if (sawTarget) {
      return normalizeRundllControlRunDllArgs(target, result)
    }
  }
  const commandLine = fields['cmd'] ? cleanWineDebugString(fields['cmd']) : ''
  if (commandLine.length === 0 || target.length === 0) {
    return []
  }
  const tokens = splitBrokerCommandLine(commandLine)
  const result: string[] = []
  let sawTarget = false
  for (let i = 0; i < tokens.length; i++) {
    const token = tokens[i]
    if (!sawTarget) {
      if (token === target) {
        sawTarget = true
      }
      continue
    }
    result.push(token)
  }
  return normalizeRundllControlRunDllArgs(target, sawTarget ? result : tokens.slice(1))
}

function brokerRequestIsShortLived(fields: Record<string, string>): boolean {
  const target = brokerRequestTarget(fields).toLowerCase()
  const call = fields['call'] ? fields['call'].toLowerCase() : ''
  return call.indexOf('helper') >= 0 ||
    target.endsWith('\\rundll32.exe') ||
    target.endsWith('\\regsvr32.exe') ||
    target.endsWith('\\cmd.exe')
}

function brokerRequestIsWineLoaderExec(fields: Record<string, string>): boolean {
  const call = fields['call'] ? fields['call'].toLowerCase() : ''
  const path = fields['path'] ? cleanWineDebugString(fields['path']) : ''
  return call.startsWith('exec') && isBrokerLoaderPath(path)
}

function brokerRequestIsNestedExplorerDesktop(fields: Record<string, string>, target: string): boolean {
  const lowerTarget = target.toLowerCase().replace(/\//g, '\\')
  if (!lowerTarget.endsWith('\\windows\\explorer.exe') &&
    !lowerTarget.endsWith('\\windows\\system32\\explorer.exe')) {
    return false
  }
  const args = brokerRequestArgs(fields, target)
  for (let i = 0; i < args.length; i++) {
    if (args[i].toLowerCase().startsWith('/desktop')) {
      return true
    }
  }
  return false
}

function brokerExecCommandLine(fields: Record<string, string>, target: string): string {
  const argv = brokerRequestArgv(fields)
  const path = fields['path'] ? cleanWineDebugString(fields['path']) : ''
  const parts: string[] = [runtimeWineLoaderPath()]
  if (argv.length > 0) {
    const first = argv[0]
    const start = isBrokerLoaderPath(first) || first === path ? 1 : 0
    for (let i = start; i < argv.length; i++) {
      if (argv[i].length > 0) {
        parts.push(argv[i])
      }
    }
  }
  if (parts.length === 1 && target.length > 0) {
    parts.push(target)
    const args = brokerRequestArgs(fields, target)
    for (let i = 0; i < args.length; i++) {
      parts.push(args[i])
    }
  }
  const normalizedParts = normalizeRundllControlRunDllParts(target, parts)
  return normalizedParts.map((item: string): string => quoteCommandArg(item)).join(' ')
}

function brokerExecEnv(fields: Record<string, string>, backend: string, requestName: string): string[] {
  const env: string[] = [
    'WINE_HMOS_INPROCESS_STRICT=0',
    `WINE_HMOS_PARENT_BACKEND=${backend}`,
    `WINE_HMOS_PARENT_BROKER_REQUEST=${requestName}`,
    'WINE_HMOS_BROKER_RESUME_EXEC=1'
  ]
  const keys: string[] = [
    'WINEPRELOADRESERVE',
    'WINELOADERNOEXEC',
    'WINE_LD_PRELOAD',
    'LD_PRELOAD',
    'BOX64_ARG0'
  ]
  if (fields['exec_env.WINESERVERSOCKET'] && fields['exec_env.WINESERVERSOCKET'].length > 0) {
    emitLog('broker', `dropping inherited WINESERVERSOCKET=${fields['exec_env.WINESERVERSOCKET']} for ${requestName}; native child will reconnect`)
  }
  for (let i = 0; i < keys.length; i++) {
    const field = `exec_env.${keys[i]}`
    if (fields[field] && fields[field].length > 0) {
      env.push(`${keys[i]}=${fields[field]}`)
    }
  }
  return env
}

function brokerExecWorkdir(fields: Record<string, string>, prefix: PrefixResult): string {
  const cwd = fields['cwd'] ? cleanWineDebugString(fields['cwd']) : ''
  return cwd.length > 0 ? cwd : prefixDriveCRoot(prefix)
}

function brokerDonePath(path: string, status: string): string {
  return `${path}.${sanitizeName(status)}`
}

function markBrokerRequest(path: string, status: string, note: string): void {
  const target = brokerDonePath(path, status)
  try {
    appendTextFile(path, `\nbroker_status=${status}\nbroker_note=${envelopeValue(note)}\n`)
  } catch (_) {
  }
  try {
    fs.renameSync(path, target)
  } catch (err) {
    emitLog('broker', `request mark failed ${leafName(path)} -> ${status}: ${errorMessage(err)}`)
    try {
      fs.unlinkSync(path)
    } catch (_) {
    }
  }
}

function activeEmulatedSlotCount(): number {
  let count = 0
  for (let i = 0; i < emulatedSlots.length; i++) {
    if (emulatedSlots[i].active) {
      count++
    }
  }
  return count
}

function allocateEmulatedSlot(mode: ExecMode, requestId: string): WineEmulatedSlot | undefined {
  if (activeEmulatedSlotCount() >= MAX_EMULATED_PROCESS_SLOTS) {
    emitLog('broker', `emulation-limit: active slots exceed ${MAX_EMULATED_PROCESS_SLOTS}; request=${requestId}`)
    return undefined
  }
  const slot: WineEmulatedSlot = {
    slotId: nextEmulatedSlotId++,
    mode,
    requestId,
    active: true
  }
  emulatedSlots.push(slot)
  emitLog('broker', `allocated ${mode} slot=${slot.slotId} request=${requestId}`)
  return slot
}

function releaseEmulatedSlot(slotId: number, reason: string): void {
  for (let i = 0; i < emulatedSlots.length; i++) {
    const slot = emulatedSlots[i]
    if (slot.slotId !== slotId || !slot.active) {
      continue
    }
    slot.active = false
    emitLog('broker', `released emulated slot=${slotId}: ${reason}`)
    return
  }
}

function wineProcessEnvForMode(request: WineProcessRequest, mode: ExecMode, slotId: number): string[] {
  const env = withoutEnvKeys(request.env, [
    'WINESERVERSOCKET',
    'WINE_HMOS_EXEC_BACKEND',
    'WINE_HMOS_PROCESS_ISOLATION',
    'WINE_HMOS_PROCESS_SLOT_ID',
    'WINE_HMOS_EMULATED_SLOT_COUNT'
  ])
  env.push(`WINE_HMOS_EXEC_BACKEND=${mode}`)
  if (mode === ExecMode.NATIVE_CHILD_PROCESS) {
    env.push('WINE_HMOS_PROCESS_ISOLATION=native-child')
  } else {
    env.push('WINE_HMOS_PROCESS_ISOLATION=emulated')
    env.push(`WINE_HMOS_PROCESS_SLOT_ID=${slotId}`)
    env.push(`WINE_HMOS_EMULATED_SLOT_COUNT=${MAX_EMULATED_PROCESS_SLOTS}`)
    env.push(`WINE_HMOS_EMULATED_SLOT_MODE=${mode}`)
  }
  return env
}

function prepareWineProcessLaunch(request: WineProcessRequest, mode: ExecMode, slotId: number): LaunchSession | string {
  return prepareLaunch(request.kind, {
    targetPath: request.targetPath,
    targetIsWinePath: request.targetIsWinePath,
    prefixName: request.prefixName,
    args: request.args,
    workingDirectory: request.workingDirectory,
    env: wineProcessEnvForMode(request, mode, slotId),
    xcomponentId: request.xcomponentId
  })
}

async function launchViaNativeChildProcess(launchRequest: string): Promise<number> {
  return await childProcessManager.startNativeChildProcess(WINE_CHILD_ENTRY_POINT, {
    entryParams: launchRequest
  }, {
    isolationMode: false
  })
}

async function launchViaWorkerEmulatedBackend(launchRequest: string, requestId: string, slot: WineEmulatedSlot): Promise<NativeLaunchSession> {
  return await new Promise<NativeLaunchSession>((resolve) => {
    let settled = false
    const finishFirst = (result: NativeLaunchSession): void => {
      if (settled) {
        return
      }
      settled = true
      resolve(result)
    }
    try {
      const thread = new worker.ThreadWorker(WINE_WORKER_SCRIPT_URL, {
        name: `wine-worker-${slot.slotId}`
      })
      slot.workerRef = thread
      thread.onmessage = (event): void => {
        const data = event.data as Object
        if (!isWorkerResultMessage(data)) {
          emitLog('broker', `worker slot=${slot.slotId} returned non broker message`)
          return
        }
        const message = data as WineWorkerResultMessage
        emitLog('broker', `worker slot=${slot.slotId} ${message.type}: ${message.status} ${message.reason}`)
        if (message.type === 'started') {
          finishFirst({
            sessionId: `worker-slot-${slot.slotId}`,
            status: message.status,
            reason: message.reason,
            exitCode: message.exitCode
          })
          return
        }
        if (message.type === 'finished' || message.type === 'failed') {
          releaseEmulatedSlot(slot.slotId, `${message.type}: ${message.status}`)
        }
      }
      thread.onerror = (err): void => {
        const reason = `worker slot error: ${err.message}`
        emitLog('broker', reason)
        releaseEmulatedSlot(slot.slotId, reason)
        finishFirst({
          sessionId: `worker-slot-${slot.slotId}`,
          status: 'runtime-error',
          reason
        })
      }
      thread.onexit = (code: number): void => {
        releaseEmulatedSlot(slot.slotId, `worker exit code=${code}`)
        if (!settled) {
          finishFirst({
            sessionId: `worker-slot-${slot.slotId}`,
            status: code === 0 ? 'finished' : 'runtime-error',
            reason: `worker exited before start ack code=${code}`,
            exitCode: code
          })
        }
      }
      const message: WineWorkerLaunchMessage = {
        type: 'launch',
        requestId,
        slotId: slot.slotId,
        launchRequest
      }
      thread.postMessage(message)
    } catch (err) {
      const reason = `worker init failed: ${errorMessage(err)}`
      emitLog('broker', `${reason}; falling back to shared emulated native slot`)
      releaseEmulatedSlot(slot.slotId, reason)
      const result = nativeBridge.launchSessionInCurrentProcess(launchRequest)
      finishFirst({
        sessionId: result.sessionId,
        status: result.status,
        reason: `${reason}; shared slot result=${result.reason}`,
        exitCode: result.exitCode
      })
    }
  })
}

async function launchViaTaskpoolEmulatedBackend(launchRequest: string, slot: WineEmulatedSlot): Promise<NativeLaunchSession> {
  try {
    emitLog('broker', `taskpool slot=${slot.slotId} dispatch`)
    const result = await taskpool.execute(runWineTaskpoolLaunch, launchRequest) as string
    releaseEmulatedSlot(slot.slotId, 'taskpool completed')
    return nativeSessionFromJson(result)
  } catch (err) {
    const reason = `taskpool emulation failed: ${errorMessage(err)}`
    emitLog('broker', `${reason}; falling back to shared emulated native slot`)
    releaseEmulatedSlot(slot.slotId, reason)
    const result = nativeBridge.launchSessionInCurrentProcess(launchRequest)
    return {
      sessionId: result.sessionId,
      status: result.status,
      reason: `${reason}; shared slot result=${result.reason}`,
      exitCode: result.exitCode
    }
  }
}

async function launchViaEmulatedBackend(launchRequest: string, mode: ExecMode, requestId: string, slot: WineEmulatedSlot): Promise<NativeLaunchSession> {
  emitLog('broker', `${mode} requested; slot=${slot.slotId} isolation=emulated`)
  if (mode === ExecMode.TASKPOOL_EMULATED_PROCESS) {
    return await launchViaTaskpoolEmulatedBackend(launchRequest, slot)
  }
  return await launchViaWorkerEmulatedBackend(launchRequest, requestId, slot)
}

export async function launchWineProcess(request: WineProcessRequest): Promise<WineProcessResult> {
  const capabilities = probeExecutionCapabilities()
  let mode = request.preferBackend ? request.preferBackend : chooseExecMode(
    capabilities.deviceType,
    capabilities.nativeChildProcess,
    capabilities.workerAvailable,
    capabilities.taskpoolAvailable,
    request.shortLived === true)
  const requestId = `${request.kind}-${Date.now()}`
  let prepared = prepareWineProcessLaunch(request, mode, 0)
  if (typeof prepared !== 'string') {
    return {
      requestId: prepared.sessionId,
      execMode: mode,
      session: prepared,
      status: prepared.status,
      reason: prepared.reason ? prepared.reason : prepared.status
    }
  }

  let kind = envelopeField(prepared, 'prepared.kind')
  let target = envelopeField(prepared, 'prepared.target')
  let prefixPath = envelopeField(prepared, 'prepared.prefix')
  let launchRequest = prepared
  let commandLine = envelopeField(prepared, 'cmd')
  emitLog('broker', `launchWineProcess ${kind} mode=${mode} target=${target}`)

  if (mode === ExecMode.NATIVE_CHILD_PROCESS) {
    try {
      const pid = await launchViaNativeChildProcess(launchRequest)
      const session: LaunchSession = {
        sessionId: requestId,
        kind,
        targetPath: target,
        prefixPath,
        status: 'started',
        commandLine,
        reason: `native child process pid=${pid}`
      }
      emitState(session.sessionId, session.status, session.reason ? session.reason : 'native child process started')
      return {
        requestId,
        execMode: mode,
        session,
        pid,
        status: 'started',
        reason: session.reason ? session.reason : 'native child process started'
      }
    } catch (err) {
      emitLog('broker', `native child process failed, falling back to emulated backend: ${errorMessage(err)}`)
      mode = chooseExecMode(capabilities.deviceType, false, capabilities.workerAvailable, capabilities.taskpoolAvailable, request.shortLived === true)
    }
  }

  const fallbackMode = mode === ExecMode.TASKPOOL_EMULATED_PROCESS ? ExecMode.TASKPOOL_EMULATED_PROCESS : ExecMode.WORKER_EMULATED_PROCESS
  const slot = allocateEmulatedSlot(fallbackMode, requestId)
  if (slot === undefined) {
    const session = failedLaunch(request.kind, request.targetPath, commandLine, 'emulation-limit', `no emulated Wine process slot available; max=${MAX_EMULATED_PROCESS_SLOTS}`)
    return {
      requestId,
      execMode: fallbackMode,
      session,
      status: session.status,
      reason: session.reason ? session.reason : session.status
    }
  }
  prepared = prepareWineProcessLaunch(request, fallbackMode, slot.slotId)
  if (typeof prepared !== 'string') {
    releaseEmulatedSlot(slot.slotId, prepared.status)
    return {
      requestId: prepared.sessionId,
      execMode: fallbackMode,
      processSlotId: slot.slotId,
      session: prepared,
      status: prepared.status,
      reason: prepared.reason ? prepared.reason : prepared.status
    }
  }
  kind = envelopeField(prepared, 'prepared.kind')
  target = envelopeField(prepared, 'prepared.target')
  prefixPath = envelopeField(prepared, 'prepared.prefix')
  launchRequest = prepared
  commandLine = envelopeField(prepared, 'cmd')
  const nativeSession = await launchViaEmulatedBackend(launchRequest, fallbackMode, requestId, slot)
  const session = launchSessionFromEnvelope(kind, target, prefixPath, commandLine, nativeSession)
  return {
    requestId,
    execMode: fallbackMode,
    processSlotId: slot.slotId,
    session,
    status: session.status,
    reason: session.reason ? session.reason : session.status
  }
}

async function launchBrokerExecRequest(
  prefix: PrefixResult,
  fields: Record<string, string>,
  requestName: string,
  backend: string,
  xcomponentId?: string
): Promise<WineProcessResult> {
  const capabilities = probeExecutionCapabilities()
  let mode = chooseExecMode(
    capabilities.deviceType,
    capabilities.nativeChildProcess,
    capabilities.workerAvailable,
    capabilities.taskpoolAvailable,
    brokerRequestIsShortLived(fields))
  const requestId = `broker-exec-${Date.now()}`
  const target = brokerRequestTarget(fields)
  const commandLine = brokerExecCommandLine(fields, target)
  const baseEnv = brokerExecEnv(fields, backend, requestName)
  const buildRequestForMode = (execMode: ExecMode, slotId: number): string => {
    const env = wineProcessEnvForMode({
      kind: 'child',
      targetPath: target,
      targetIsWinePath: true,
      prefixName: prefix.prefixName,
      env: baseEnv,
      shortLived: brokerRequestIsShortLived(fields),
      xcomponentId
    }, execMode, slotId)
    return buildLaunchRequest({
      targetPath: runtimeWineLoaderPath(),
      targetIsWinePath: false,
      prefixName: prefix.prefixName,
      workingDirectory: brokerExecWorkdir(fields, prefix),
      env,
      xcomponentId
    }, prefix, commandLine)
  }

  let launchRequest = buildRequestForMode(mode, 0)
  emitLog('broker', `resume exec ${requestName} mode=${mode} target=${target}`)
  if (mode === ExecMode.NATIVE_CHILD_PROCESS) {
    try {
      const pid = await launchViaNativeChildProcess(launchRequest)
      const session: LaunchSession = {
        sessionId: requestId,
        kind: 'child',
        targetPath: target,
        prefixPath: prefix.prefixPath,
        status: 'started',
        commandLine,
        reason: `native child process pid=${pid}`
      }
      emitState(session.sessionId, session.status, session.reason ? session.reason : 'native child process started')
      return {
        requestId,
        execMode: mode,
        session,
        pid,
        status: session.status,
        reason: session.reason ? session.reason : session.status
      }
    } catch (err) {
      emitLog('broker', `resume exec native child failed, falling back: ${errorMessage(err)}`)
      mode = chooseExecMode(capabilities.deviceType, false, capabilities.workerAvailable, capabilities.taskpoolAvailable, brokerRequestIsShortLived(fields))
    }
  }

  const fallbackMode = mode === ExecMode.TASKPOOL_EMULATED_PROCESS ? ExecMode.TASKPOOL_EMULATED_PROCESS : ExecMode.WORKER_EMULATED_PROCESS
  const slot = allocateEmulatedSlot(fallbackMode, requestId)
  if (slot === undefined) {
    const session = failedLaunch('child', target, commandLine, 'emulation-limit', `no emulated Wine process slot available; max=${MAX_EMULATED_PROCESS_SLOTS}`)
    return {
      requestId,
      execMode: fallbackMode,
      session,
      status: session.status,
      reason: session.reason ? session.reason : session.status
    }
  }
  launchRequest = buildRequestForMode(fallbackMode, slot.slotId)
  const nativeSession = await launchViaEmulatedBackend(launchRequest, fallbackMode, requestId, slot)
  const session = launchSessionFromEnvelope('child', target, prefix.prefixPath, commandLine, nativeSession)
  return {
    requestId,
    execMode: fallbackMode,
    processSlotId: slot.slotId,
    session,
    status: session.status,
    reason: session.reason ? session.reason : session.status
  }
}

export async function drainWineProcessBroker(prefixName: string, xcomponentId?: string, maxRequests: number = 8): Promise<WineBrokerDrainResult> {
  const prefix = existingPrefixResult(prefixName)
  const brokerRoot = prefixBrokerRoot(prefix)
  const result: WineBrokerDrainResult = {
    prefixName: prefix.prefixName,
    brokerRoot,
    scanned: 0,
    processed: 0,
    launched: 0,
    blocked: 0,
    failed: 0,
    messages: []
  }
  if (!isDirectoryPath(brokerRoot)) {
    return result
  }
  const names = listFilesSafe(brokerRoot)
  for (let i = 0; i < names.length && result.processed < maxRequests; i++) {
    const name = names[i]
    if (!name.endsWith('.txt') || name.indexOf('.handled') >= 0 || name.indexOf('.failed') >= 0 || name.indexOf('.blocked') >= 0) {
      continue
    }
    result.scanned++
    const path = joinPath(brokerRoot, name)
    try {
      const fields = parseBrokerRequest(readTextFile(path))
      const source = fields['source'] ? fields['source'] : 'wine-ntdll'
      const backend = fields['backend'] ? fields['backend'] : ''
      const call = fields['call'] ? fields['call'] : 'NtCreateUserProcess'
      const pathField = fields['path'] ? cleanWineDebugString(fields['path']) : ''
      const target = brokerRequestTarget(fields)
      const returnName = fields['return_name'] ? fields['return_name'] : ''
      result.processed++
      if (isBrokerPreloaderPath(pathField)) {
        const message = `broker skipped preloader attempt ${name} path=${pathField}`
        emitLog('broker', message)
        result.messages.push(message)
        markBrokerRequest(path, 'handled', message)
        continue
      }
      if (target.length === 0 || target === '<none>') {
        const message = `emulation-limit: broker request ${name} has no image/cmd target source=${source} call=${call} return=${returnName}`
        emitLog('broker', message)
        result.blocked++
        result.messages.push(message)
        markBrokerRequest(path, 'blocked', message)
        continue
      }
      if (brokerRequestIsNestedExplorerDesktop(fields, target)) {
        const message = `broker skipped nested explorer desktop ${name} target=${target}`
        emitLog('broker', message)
        result.messages.push(message)
        markBrokerRequest(path, 'handled', message)
        continue
      }
      const childResult = brokerRequestIsWineLoaderExec(fields) ?
        await launchBrokerExecRequest(prefix, fields, name, backend, xcomponentId) :
        await launchWineProcess({
          kind: 'child',
          targetPath: target,
          targetIsWinePath: target.indexOf(':\\') > 0 || target.startsWith('\\\\'),
          prefixName: prefix.prefixName,
          args: brokerRequestArgs(fields, target),
          env: [
            'WINE_HMOS_INPROCESS_STRICT=0',
            `WINE_HMOS_PARENT_BACKEND=${backend}`,
            `WINE_HMOS_PARENT_BROKER_REQUEST=${name}`
          ],
          xcomponentId,
          shortLived: brokerRequestIsShortLived(fields)
        })
      const message = `broker dispatched ${name} target=${target} mode=${childResult.execMode} status=${childResult.status}`
      emitLog('broker', message)
      result.launched++
      result.messages.push(message)
      markBrokerRequest(path, 'handled', message)
    } catch (err) {
      const message = `broker request ${name} failed: ${errorMessage(err)}`
      emitLog('broker', message)
      result.failed++
      result.messages.push(message)
      markBrokerRequest(path, 'failed', message)
    }
  }
  return result
}

function launch(kind: string, options: LaunchOptions): LaunchSession {
  const winePath = runtimeWineLoaderPath()
  if (!fileExists(winePath)) {
    return failedLaunch(kind, options.targetPath, '', 'missing-wine-payload', `Wine guest loader SO not staged: ${winePath}`)
  }
  chmodExecutableIfPresent(winePath)
  if (!options.targetIsWinePath && !fileExists(options.targetPath)) {
    return failedLaunch(kind, options.targetPath, '', 'missing-target', `target executable not found: ${options.targetPath}`)
  }

  const prefix = createOrOpenPrefix(options.prefixName ? options.prefixName : 'default')
  ensureWineWin11Prefix(prefix.prefixPath)
  ensureWineHmosPrefix(prefix.prefixPath)
  ensureWineGraphicsDriverPrefix(prefix.prefixPath)
  const launchTargetPath = options.targetIsWinePath ? options.targetPath : stageLaunchTargetInPrefix(prefix, options.targetPath)
  const launchTargetWinePath = options.targetIsWinePath ? options.targetPath : winePathForHmosDrive(prefix, launchTargetPath)
  const launchOptions: LaunchOptions = {
    targetPath: launchTargetWinePath,
    targetIsWinePath: options.targetIsWinePath,
    prefixName: options.prefixName,
    args: options.args,
    workingDirectory: options.workingDirectory && options.workingDirectory.length > 0 ?
      options.workingDirectory :
      (options.targetIsWinePath ? prefixDriveCRoot(prefix) : parentDir(options.targetPath)),
    env: options.env,
    xcomponentId: options.xcomponentId
  }
  const commandLine = buildCommandLine(launchOptions)
  const launchRequest = buildLaunchRequest(launchOptions, prefix, commandLine)
  emitLog('process', `${kind} requested: ${commandLine}`)
  emitLog('box64', `dispatch via ${runtimeBox64ExecutablePath()}`)
  const nativeSession = nativeBridge.launchSession(launchRequest)
  const sessionId = `${kind}-${Date.now()}`
  const result: LaunchSession = {
    sessionId,
    kind,
    targetPath: launchTargetPath,
    prefixPath: prefix.prefixPath,
    status: nativeSession.status,
    commandLine,
    reason: nativeSession.reason,
    exitCode: nativeSession.exitCode
  }
  emitLog('process', `${kind} native result: ${result.status}, exit=${result.exitCode}, reason=${result.reason}`)
  emitState(sessionId, result.status, result.reason ? result.reason : 'session created')
  return result
}

export function launchDesktop(options: DesktopLaunchOptions = {}): LaunchSession {
  const desktopEnv = options.env ? options.env.concat(['WINE_HMOS_INPROCESS_STRICT=0']) : ['WINE_HMOS_INPROCESS_STRICT=0']
  return launch('desktop', {
    targetPath: 'C:\\windows\\explorer.exe',
    targetIsWinePath: true,
    prefixName: options.prefixName,
    args: options.args && options.args.length > 0 ? options.args : [
      '/desktop=shell,896x640'
    ],
    workingDirectory: options.workingDirectory,
    env: desktopEnv,
    xcomponentId: options.xcomponentId
  })
}

export function configureHostContext(context: common.UIAbilityContext): void {
  hostContext = context
  emitLog('runtime', 'host UIAbilityContext attached')
}

export function probeRuntime(): RuntimeProbe {
  const nativeProbe = nativeBridge.probeRuntime()
  const contextReady = hostContext !== undefined
  return {
    abi: nativeProbe.abi,
    nativeModule: nativeProbe.nativeModule,
    vulkanLinked: nativeProbe.vulkanLinked,
    vulkanProbeResult: nativeProbe.vulkanProbeResult,
    vulkanApiVersion: nativeProbe.vulkanApiVersion,
    runtimeReady: nativeProbe.runtimeReady,
    runtimeComponents: nativeProbe.runtimeComponents,
    hasHostContext: contextReady,
    rawfileReady: contextReady,
    jitPolicy: 'requested-by-entry-manifest',
    executableMemoryPolicy: 'requested-by-entry-manifest',
    xcomponentBridge: 'native-xcomponent-surface-id',
    stage: nativeProbe.stage
  }
}

async function stageRawfileTreeWithContexts(rawContext: common.Context, targetContext: common.Context, rawRoot: string, targetName: string): Promise<StageResult> {
  const cleanTarget = sanitizeName(targetName)
  const stageRoot = joinPath(targetContext.filesDir, STAGE_ROOT_DIR)
  const targetPath = joinPath(stageRoot, cleanTarget)
  const manifestPath = joinPath(targetPath, MANIFEST_NAME)
  ensureDir(targetPath)

  emitLog('staging', `${rawRoot}: scanning rawfile tree`)
  const rawFiles: IndexedRawfile[] = []
  const indexedRawFiles = await readRawfileIndex(rawContext, rawRoot)
  if (indexedRawFiles !== undefined) {
    for (let i = 0; i < indexedRawFiles.length; i++) {
      rawFiles.push(indexedRawFiles[i])
    }
    emitLog('staging', `${rawRoot}: ${rawFiles.length} indexed rawfile(s) queued`)
  } else {
    await collectRawFiles(rawContext, rawRoot, rawRoot, rawFiles)
    emitLog('staging', `${rawRoot}: ${rawFiles.length} rawfile(s) queued`)
  }

  const files: StagedFile[] = []
  let copiedCount = 0
  let skippedCount = 0
  let totalBytes = 0
  for (let i = 0; i < rawFiles.length; i++) {
    const rawItem = rawFiles[i]
    const rawPath = rawItem.rawPath
    const relativePath = rawPath.substring(rawRoot.length).replace(/^\/+/, '')
    const targetFile = joinPath(targetPath, relativePath)
    const forceOverwrite = shouldForceRefreshStagedFile(rawRoot, relativePath)
    if (i < 10 || (i + 1) % 250 === 1) {
      emitLog('staging', `${cleanTarget}: copying ${i + 1}/${rawFiles.length}: ${relativePath}`)
    }
    if (forceOverwrite) {
      emitLog('staging', `${cleanTarget}: refreshing ${relativePath}`)
    }
    const item = await copyRawFile(rawContext, rawPath, targetFile, rawItem.size, forceOverwrite)
    files.push(item)
    totalBytes += item.size
    if (item.copied) {
      copiedCount++
    } else {
      skippedCount++
    }
    if ((i + 1) % 500 === 0 || i + 1 === rawFiles.length) {
      emitLog('staging', `${cleanTarget}: staged ${i + 1}/${rawFiles.length}, bytes=${totalBytes}`)
    }
    if ((i + 1) % 25 === 0) {
      await yieldToEventLoop()
    }
  }

  const result: StageResult = {
    rawRoot,
    targetName: cleanTarget,
    targetPath,
    fileCount: files.length,
    copiedCount,
    skippedCount,
    totalBytes,
    manifestPath,
    files
  }
  const manifest = JSON.stringify(result)
  writeTextFile(manifestPath, manifest)
  emitLog('staging', `${cleanTarget}: copied=${copiedCount}, skipped=${skippedCount}, bytes=${totalBytes}`)
  return result
}

async function createRuntimeModuleContext(context: common.UIAbilityContext): Promise<common.Context | undefined> {
  try {
    const moduleContext = await Promise.race<common.Context>([
      application.createModuleContext(context, 'proton') as Promise<common.Context>,
      timeoutAfter<common.Context>(MODULE_CONTEXT_TIMEOUT_MS, `createModuleContext(proton) timed out after ${MODULE_CONTEXT_TIMEOUT_MS}ms`)
    ])
    emitLog('runtime', 'proton module context ready')
    return moduleContext
  } catch (err) {
    emitLog('runtime', `createModuleContext(proton) failed: ${errorMessage(err)}`)
    return undefined
  }
}

export async function stageRuntime(): Promise<StageResult> {
  emitLog('runtime', 'stageRuntime entered')
  const targetContext = requireContext()
  runtimeBox64Path = RUNTIME_BOX64_IN_PROCESS
  emitLog('box64', `runtime core ready: ${runtimeBox64Path}`)

  const moduleErrors: string[] = []
  const moduleContext = await createRuntimeModuleContext(targetContext)
  if (moduleContext) {
    try {
      const result = await stageRawfileTreeWithContexts(moduleContext, targetContext, RUNTIME_PROTON_RAW_ROOT, RUNTIME_PROTON_TARGET_NAME)
      runtimeProtonPath = result.targetPath
      const guestSoPaths: string[] = [
        runtimeWineLoaderPath(),
        joinPath(runtimeProtonPath, 'files/lib/wine/x86_64-unix/ntdll.so')
      ]
      for (let i = 0; i < guestSoPaths.length; i++) {
        emitLog('wine', fileExists(guestSoPaths[i]) ? `runtime guest SO ready: ${guestSoPaths[i]}` : `runtime guest SO missing: ${guestSoPaths[i]}`)
      }
      emitLog('wine', `runtime staged from proton module context: ${result.fileCount} files, wine-loader=${runtimeWineLoaderPath()}, server=${RUNTIME_WINE_SERVER_LIBRARY}`)
      return result
    } catch (err) {
      const message = errorMessage(err)
      moduleErrors.push(`proton module context => ${message}`)
      emitLog('runtime', `module rawfile staging failed, falling back: ${message}`)
    }
  } else {
    moduleErrors.push('proton module context => unavailable')
  }

  const cleanTarget = sanitizeName(RUNTIME_PROTON_TARGET_NAME)
  const targetPath = joinPath(joinPath(targetContext.filesDir, STAGE_ROOT_DIR), cleanTarget)
  const manifestPath = joinPath(targetPath, MANIFEST_NAME)
  ensureDir(targetPath)
  let nativeStage: NativeZipStageResult | undefined = undefined
  const dirErrors: string[] = []
  const zipErrors: string[] = []
  const rawDirs = runtimeRawDirCandidates(targetContext)
  for (let i = 0; i < rawDirs.length; i++) {
    emitLog('runtime', `trying expanded HSP rawfile dir: ${rawDirs[i]}`)
    const dirStage = nativeBridge.stageDirectoryRawfileTree(rawDirs[i], targetPath)
    if (dirStage.success) {
      nativeStage = dirStage
      emitLog('runtime', `staged runtime from expanded HSP dir: ${rawDirs[i]}`)
      break
    }
    dirErrors.push(`${rawDirs[i]} => ${dirStage.error}`)
  }
  if (!nativeStage) {
    const hspPaths = runtimeHspPathCandidates(targetContext)
    for (let i = 0; i < hspPaths.length; i++) {
      const hspPath = hspPaths[i]
      emitLog('runtime', `trying HSP zip rawfile: ${hspPath}`)
      const zipStage = nativeBridge.stageStoredZipRawfileTree(hspPath, `resources/rawfile/${RUNTIME_PROTON_RAW_ROOT}`, targetPath)
      if (zipStage.success) {
        nativeStage = zipStage
        emitLog('runtime', `staged runtime from HSP zip: ${hspPath}`)
        break
      }
      zipErrors.push(`${hspPath} => ${zipStage.error}`)
    }
  }
  if (!nativeStage || !nativeStage.success) {
    const nativeError = nativeStage ? nativeStage.error : 'no HSP zip candidate succeeded'
    throw new Error(`HSP runtime staging failed: ${nativeError}; moduleAttempts=${moduleErrors.join(' | ')}; dirAttempts=${dirErrors.join(' | ')}; zipAttempts=${zipErrors.join(' | ')}`)
  }
  const protonResult: StageResult = {
    rawRoot: RUNTIME_PROTON_RAW_ROOT,
    targetName: cleanTarget,
    targetPath,
    fileCount: nativeStage.fileCount,
    copiedCount: nativeStage.copiedCount,
    skippedCount: nativeStage.skippedCount,
    totalBytes: nativeStage.totalBytes,
    manifestPath,
    files: []
  }
  writeTextFile(manifestPath, JSON.stringify(protonResult))
  emitLog('staging', `${cleanTarget}: copied=${protonResult.copiedCount}, skipped=${protonResult.skippedCount}, bytes=${protonResult.totalBytes}`)
  runtimeProtonPath = protonResult.targetPath
  const guestSoPaths: string[] = [
    runtimeWineLoaderPath(),
    joinPath(runtimeProtonPath, 'files/lib/wine/x86_64-unix/ntdll.so')
  ]
  for (let i = 0; i < guestSoPaths.length; i++) {
    if (!fileExists(guestSoPaths[i])) {
      emitLog('wine', `runtime guest SO missing: ${guestSoPaths[i]}`)
      continue
    }
    emitLog('wine', `runtime guest SO ready: ${guestSoPaths[i]}`)
  }
  emitLog('wine', `runtime staged: ${protonResult.fileCount} files, wine-loader=${runtimeWineLoaderPath()}, server=${RUNTIME_WINE_SERVER_LIBRARY}`)
  return protonResult
}

export async function stageRawfileTree(rawRoot: string, targetName: string): Promise<StageResult> {
  const context = requireContext()
  return stageRawfileTreeWithContexts(context, context, rawRoot, targetName)
}

export function mountSurface(xcomponentId: string): SurfaceResult {
  const nativeResult = nativeBridge.mountSurface(xcomponentId)
  emitLog('vulkan', nativeResult.message)
  return {
    success: nativeResult.success,
    xcomponentId: nativeResult.xcomponentId,
    renderer: nativeResult.renderer,
    message: nativeResult.message,
    windowHandle: nativeResult.windowHandle,
    width: nativeResult.width,
    height: nativeResult.height
  }
}

export function queryGraphicsCapabilities(): GraphicsCapabilities {
  return nativeBridge.queryGraphicsCapabilities()
}

export function querySurfaceState(xcomponentId: string): SurfaceState {
  return nativeBridge.querySurfaceState(xcomponentId)
}

export function reportWinePresent(xcomponentId: string, source: string, success: boolean, width: number, height: number, frameNumber: number, message: string): NativePresentReport {
  return nativeBridge.reportWinePresent(xcomponentId, source, success ? 1 : 0, width, height, frameNumber, message)
}

export function renderSurfaceFrame(xcomponentId: string, framePath: string): NativeFrameResult {
  return nativeBridge.renderSurfaceFrame(xcomponentId, framePath)
}

export function createOrOpenPrefix(prefixName: string): PrefixResult {
  const context = requireContext()
  const cleanPrefix = sanitizeName(prefixName)
  const prefixRoot = joinPath(context.filesDir, PREFIX_ROOT_DIR)
  const prefixPath = joinPath(prefixRoot, cleanPrefix)
  let created = false
  try {
    fs.accessSync(prefixPath)
  } catch (_) {
    created = true
  }
  ensureDir(prefixPath)
  ensureDir(joinPath(prefixPath, 'drive_c'))
  ensureWineDosDevices(prefixPath)
  const alreadyInitialized = initializedPrefixNames.indexOf(cleanPrefix) >= 0
  if (created || !alreadyInitialized) {
    ensureDefaultPrefixContents(prefixPath)
    ensureWineFontFiles(prefixPath)
    ensureWineWin11Prefix(prefixPath)
    ensureWineHmosPrefix(prefixPath)
    ensureWineGraphicsDriverPrefix(prefixPath)
    ensureWineDesktopShellPrefix(prefixPath)
    if (!alreadyInitialized) {
      initializedPrefixNames.push(cleanPrefix)
    }
    emitLog('wine', `${created ? 'created' : 'opened'} prefix ${cleanPrefix}`)
  } else {
    emitLog('wine', `opened prefix cached ${cleanPrefix}`)
  }
  return {
    prefixName: cleanPrefix,
    prefixPath,
    created
  }
}

function saveLaunchProfile(prefix: PrefixResult, profile: WineLaunchProfile): WineLaunchProfile {
  writeJsonFile(jsonPath(hmosProfileRoot(prefix), profile.profileId), profile)
  emitLog('profile', `saved ${profile.type} profile ${profile.profileId}: ${profile.winePath}`)
  return profile
}

function saveInstallRecord(prefix: PrefixResult, record: WineInstallRecord): WineInstallRecord {
  writeJsonFile(jsonPath(hmosInstallRecordRoot(prefix), record.recordId), record)
  emitLog('profile', `saved installer record ${record.recordId}: ${record.winePath}`)
  return record
}

function loadLaunchProfile(prefix: PrefixResult, profileId: string): WineLaunchProfile | undefined {
  const path = jsonPath(hmosProfileRoot(prefix), profileId)
  if (!fileExists(path)) {
    return undefined
  }
  return readJsonFile<WineLaunchProfile>(path)
}

function loadInstallRecord(prefix: PrefixResult, recordId: string): WineInstallRecord | undefined {
  const path = jsonPath(hmosInstallRecordRoot(prefix), recordId)
  if (!fileExists(path)) {
    return undefined
  }
  return readJsonFile<WineInstallRecord>(path)
}

function listPrefixes(): PrefixResult[] {
  const context = requireContext()
  const prefixRoot = joinPath(context.filesDir, PREFIX_ROOT_DIR)
  const names = listFilesSafe(prefixRoot)
  const prefixes: PrefixResult[] = []
  for (let i = 0; i < names.length; i++) {
    const path = joinPath(prefixRoot, names[i])
    if (isDirectoryPath(path)) {
      prefixes.push({
        prefixName: names[i],
        prefixPath: path,
        created: false
      })
    }
  }
  return prefixes
}

function findProfile(profileId: string): WineLaunchProfile | undefined {
  const prefixes = listPrefixes()
  for (let i = 0; i < prefixes.length; i++) {
    const profile = loadLaunchProfile(prefixes[i], profileId)
    if (profile !== undefined) {
      return profile
    }
  }
  return undefined
}

function findInstallRecord(recordId: string): WineInstallRecord | undefined {
  const prefixes = listPrefixes()
  for (let i = 0; i < prefixes.length; i++) {
    const record = loadInstallRecord(prefixes[i], recordId)
    if (record !== undefined) {
      return record
    }
  }
  return undefined
}

function copyDirectoryInto(sourceRoot: string, targetRoot: string): void {
  ensureDir(targetRoot)
  const result = nativeBridge.stageDirectoryRawfileTree(sourceRoot, targetRoot)
  if (!result.success) {
    throw new Error(result.error)
  }
  emitLog('profile', `directory imported ${sourceRoot} -> ${targetRoot}, files=${result.fileCount}, copied=${result.copiedCount}, skipped=${result.skippedCount}`)
}

function importHostPathToHmosDrive(sourcePath: string, targetRoot: string, copyDirectory: boolean, executableName?: string): string {
  if (isDirectoryPath(sourcePath)) {
    copyDirectoryInto(sourcePath, targetRoot)
    const exe = executableName && executableName.length > 0 ? joinPath(targetRoot, executableName) : findFirstExe(targetRoot)
    if (exe.length === 0) {
      throw new Error(`no executable found after importing directory: ${sourcePath}`)
    }
    return exe
  }
  if (!isRegularFilePath(sourcePath)) {
    throw new Error(`source path is not a file or directory: ${sourcePath}`)
  }
  if (copyDirectory) {
    copyDirectoryInto(parentDir(sourcePath), targetRoot)
    const exeName = executableName && executableName.length > 0 ? executableName : leafName(sourcePath)
    return joinPath(targetRoot, exeName)
  }
  ensureDir(targetRoot)
  const targetPath = joinPath(targetRoot, executableName && executableName.length > 0 ? executableName : leafName(sourcePath))
  fs.copyFileSync(sourcePath, targetPath)
  emitLog('profile', `file imported ${sourcePath} -> ${targetPath}`)
  return targetPath
}

export function importWineExecutable(request: ImportWineExecutableRequest): Promise<WineLaunchProfile> {
  const prefix = createOrOpenPrefix(request.prefixName)
  const displayName = request.profileName && request.profileName.length > 0 ? request.profileName : leafName(request.sourcePath)
  const profileId = profileIdFromName(displayName)
  const targetRoot = joinPath(hmosAppRoot(prefix), profileId)
  const hostExePath = importHostPathToHmosDrive(request.sourcePath, targetRoot, request.copyDirectory === true, request.executableName)
  const winePath = winePathForHmosDrive(prefix, hostExePath)
  const profile: WineLaunchProfile = {
    profileId,
    type: 'portable',
    prefixName: prefix.prefixName,
    displayName,
    winePath,
    hostPath: hostExePath,
    workingDirectory: winePathForHmosDrive(prefix, parentDir(hostExePath)),
    args: [],
    env: [],
    createdAt: nowText()
  }
  return Promise.resolve(saveLaunchProfile(prefix, profile))
}

function detectInstallerType(path: string, requested?: string): string {
  if (requested && requested.length > 0) {
    return requested.toLowerCase()
  }
  const lower = lowerName(path)
  if (lower.endsWith('.msi')) {
    return 'msi'
  }
  return 'exe'
}

export function importWineInstaller(request: ImportWineInstallerRequest): Promise<WineInstallRecord> {
  const prefix = createOrOpenPrefix(request.prefixName)
  const displayName = request.profileName && request.profileName.length > 0 ? request.profileName : leafName(request.sourcePath)
  const recordId = profileIdFromName(displayName)
  const targetRoot = joinPath(hmosInstallerRoot(prefix), recordId)
  const stagedPath = importHostPathToHmosDrive(request.sourcePath, targetRoot, false, leafName(request.sourcePath))
  const winePath = winePathForHmosDrive(prefix, stagedPath)
  const record: WineInstallRecord = {
    recordId,
    prefixName: prefix.prefixName,
    displayName,
    installerType: detectInstallerType(stagedPath, request.installerType),
    sourcePath: request.sourcePath,
    stagedPath,
    winePath,
    args: request.args ? request.args : [],
    status: 'imported',
    createdAt: nowText(),
    discoveredProfiles: []
  }
  return Promise.resolve(saveInstallRecord(prefix, record))
}

export function listWineLaunchProfiles(prefixName: string): WineLaunchProfile[] {
  const prefix = createOrOpenPrefix(prefixName)
  const paths = listFilesSafe(hmosProfileRoot(prefix))
  const profiles: WineLaunchProfile[] = []
  for (let i = 0; i < paths.length; i++) {
    if (!paths[i].endsWith('.json')) {
      continue
    }
    try {
      profiles.push(readJsonFile<WineLaunchProfile>(joinPath(hmosProfileRoot(prefix), paths[i])))
    } catch (err) {
      emitLog('profile', `profile read failed ${paths[i]}: ${errorMessage(err)}`)
    }
  }
  return profiles
}

function existingProfileHostPaths(prefixName: string): string[] {
  const profiles = listWineLaunchProfiles(prefixName)
  const paths: string[] = []
  for (let i = 0; i < profiles.length; i++) {
    paths.push(profiles[i].hostPath)
  }
  return paths
}

function containsPath(paths: string[], value: string): boolean {
  for (let i = 0; i < paths.length; i++) {
    if (paths[i] === value) {
      return true
    }
  }
  return false
}

function discoverExeCandidates(root: string, out: string[], maxDepth: number): void {
  if (maxDepth < 0 || !isDirectoryPath(root) || out.length >= 64) {
    return
  }
  const names = listFilesSafe(root)
  for (let i = 0; i < names.length && out.length < 64; i++) {
    const child = joinPath(root, names[i])
    if (isRegularFilePath(child) && lowerName(child).endsWith('.exe')) {
      out.push(child)
    } else if (isDirectoryPath(child)) {
      discoverExeCandidates(child, out, maxDepth - 1)
    }
  }
}

export function discoverInstalledApps(prefixName: string): WineLaunchProfile[] {
  const prefix = createOrOpenPrefix(prefixName)
  const existing = existingProfileHostPaths(prefix.prefixName)
  const candidates: string[] = []
  discoverExeCandidates(joinPath(prefixDriveCRoot(prefix), 'Program Files'), candidates, 4)
  discoverExeCandidates(joinPath(prefixDriveCRoot(prefix), 'Program Files (x86)'), candidates, 4)
  discoverExeCandidates(joinPath(prefixDriveCRoot(prefix), 'users'), candidates, 5)

  const created: WineLaunchProfile[] = []
  for (let i = 0; i < candidates.length; i++) {
    const hostPath = candidates[i]
    if (containsPath(existing, hostPath)) {
      continue
    }
    const displayName = stripExtension(leafName(hostPath))
    const profileId = profileIdFromName(displayName)
    const profile: WineLaunchProfile = {
      profileId,
      type: 'installed',
      prefixName: prefix.prefixName,
      displayName,
      winePath: winePathForPrefixDriveC(prefix, hostPath),
      hostPath,
      workingDirectory: winePathForPrefixDriveC(prefix, parentDir(hostPath)),
      args: [],
      env: [],
      createdAt: nowText()
    }
    created.push(saveLaunchProfile(prefix, profile))
  }
  emitLog('profile', `installed app discovery prefix=${prefix.prefixName} candidates=${candidates.length} new=${created.length}`)
  return listWineLaunchProfiles(prefix.prefixName)
}

async function launchWineProcessSession(request: WineProcessRequest): Promise<LaunchSession> {
  const result = await launchWineProcess(request)
  if (result.session) {
    return result.session
  }
  return failedLaunch(request.kind, request.targetPath, '', result.status, result.reason)
}

export async function launchInstaller(recordId: string, options: LaunchProfileOptions = {}): Promise<LaunchSession> {
  const record = findInstallRecord(recordId)
  if (record === undefined) {
    return failedLaunch('installer', recordId, '', 'missing-installer-record', `installer record not found: ${recordId}`)
  }
  const env = options.envOverride ? options.envOverride.slice() : []
  env.push(`WINE_HMOS_INSTALL_RECORD=${record.recordId}`)
  const session = record.installerType === 'msi' ?
    await launchWineProcessSession({
      kind: 'installer',
      targetPath: 'C:\\windows\\system32\\msiexec.exe',
      targetIsWinePath: true,
      prefixName: record.prefixName,
      args: ['/i', record.winePath].concat(options.argsOverride ? options.argsOverride : record.args),
      workingDirectory: 'C:\\windows\\system32',
      env,
      xcomponentId: options.xcomponentId
    }) :
    await launchWineProcessSession({
      kind: 'installer',
      targetPath: record.stagedPath,
      prefixName: record.prefixName,
      args: options.argsOverride ? options.argsOverride : record.args,
      workingDirectory: parentDir(record.stagedPath),
      env,
      xcomponentId: options.xcomponentId
    })
  record.status = session.status
  record.discoveredProfiles = discoverInstalledApps(record.prefixName)
  const prefix = createOrOpenPrefix(record.prefixName)
  saveInstallRecord(prefix, record)
  return session
}

export async function launchProfile(profileId: string, options: LaunchProfileOptions = {}): Promise<LaunchSession> {
  const profile = findProfile(profileId)
  if (profile === undefined) {
    return failedLaunch('profile', profileId, '', 'missing-profile', `launch profile not found: ${profileId}`)
  }
  return await launchWineProcessSession({
    kind: 'profile',
    targetPath: profile.winePath,
    targetIsWinePath: true,
    prefixName: profile.prefixName,
    args: options.argsOverride ? options.argsOverride : profile.args,
    workingDirectory: profile.workingDirectory,
    env: options.envOverride ? profile.env.concat(options.envOverride) : profile.env,
    xcomponentId: options.xcomponentId
  })
}

export function launchLauncher(options: LaunchOptions): LaunchSession {
  return launch('launcher', options)
}

export function launchGame(options: LaunchOptions): LaunchSession {
  return launch('game', options)
}

export function notifyWineSurfaceResize(windowId: string, width: number, height: number): void {
  nativeBridge.notifyWineSurfaceResize(windowId, width, height)
}

export function resetSurfaceBridge(prefixName: string, xcomponentId: string): void {
  const prefix = createOrOpenPrefix(prefixName)
  const bridgeRoot = prefixBridgeRoot(prefix)
  ensureDir(bridgeRoot)
  const framePath = joinPath(bridgeRoot, hmosFrameFileName(xcomponentId))
  const inputPath = joinPath(bridgeRoot, hmosInputFileName(xcomponentId))
  nativeBridge.clearSurfaceFrameCache(xcomponentId)
  const frameRemoved = removeFileIfPresent(framePath)
  const inputRemoved = removeFileIfPresent(inputPath)
  emitLog('surface', `surface bridge reset prefix=${prefix.prefixName} frame=${frameRemoved ? 'removed' : 'empty'} input=${inputRemoved ? 'removed' : 'empty'}`)
}

export function readExplorerStatus(prefixName: string): string {
  const prefix = existingPrefixResult(prefixName)
  const path = joinPath(prefixBridgeRoot(prefix), 'hmos-explorer-status.txt')
  if (!fileExists(path)) {
    return ''
  }
  return readTextFile(path)
}

export function injectKeyEvent(xcomponentId: string, action: string, keyCode: number, modifiers: number, source: string, deviceId: number, timestamp: number): NativeInputBridgeResult {
  const result = nativeBridge.injectKeyEvent(xcomponentId, action, keyCode, modifiers, source, deviceId, timestamp)
  emitLog('input', `ark key bridge ${result.success ? 'ok' : 'failed'} action=${action} key=${keyCode} surface=${xcomponentId} seq=${result.sequence}: ${result.message}`)
  return result
}

export function consumeHandwritingRequest(): WineHandwritingAnchorRequest {
  return nativeBridge.consumeHandwritingRequest()
}

export function showWineHandwritingAnchor(sessionId: string, hwnd: string, rect: WineRect, text: string, selection: WineTextSelection): void {
  nativeBridge.showWineHandwritingAnchor(sessionId, hwnd, JSON.stringify(rect), text, JSON.stringify(selection))
}

export function hideWineHandwritingAnchor(sessionId: string, reason: string): void {
  nativeBridge.hideWineHandwritingAnchor(sessionId, reason)
}

export function commitWineImeText(sessionId: string, hwnd: string, text: string, selection: WineTextSelection, compositionState: string): void {
  nativeBridge.commitWineImeText(sessionId, hwnd, text, JSON.stringify(selection), compositionState)
}

export function enumerateControllers(): ControllerDevice[] {
  return nativeBridge.enumerateControllers()
}

export function getControllerState(deviceId: number): ControllerState {
  return nativeBridge.getControllerState(deviceId)
}

export function sendControllerOutput(deviceId: number, output: ControllerOutput): void {
  nativeBridge.sendControllerOutput(deviceId, JSON.stringify(output))
}

export function stop(sessionId: string): void {
  nativeBridge.stopSession(sessionId)
  emitLog('process', `stop requested: ${sessionId}`)
  emitState(sessionId, 'stopped', 'stop requested')
}

export function onLog(callback: (entry: ProtonLogEntry) => void): () => void {
  logCallbacks.push(callback)
  return (): void => {
    const index = logCallbacks.indexOf(callback)
    if (index >= 0) {
      logCallbacks.splice(index, 1)
    }
  }
}

export function onState(callback: (state: ProtonState) => void): () => void {
  stateCallbacks.push(callback)
  return (): void => {
    const index = stateCallbacks.indexOf(callback)
    if (index >= 0) {
      stateCallbacks.splice(index, 1)
    }
  }
}
