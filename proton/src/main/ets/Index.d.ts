import common from '@ohos.app.ability.common';

export interface RuntimeComponent {
  name: string;
  library: string;
  available: boolean;
  error: string;
}

export interface RuntimeProbe {
  abi: string;
  nativeModule: string;
  vulkanLinked: boolean;
  vulkanProbeResult: number;
  vulkanApiVersion: number;
  runtimeReady: boolean;
  runtimeComponents: RuntimeComponent[];
  hasHostContext: boolean;
  rawfileReady: boolean;
  jitPolicy: string;
  executableMemoryPolicy: string;
  xcomponentBridge: string;
  stage: string;
}

export interface GraphicsCapabilities {
  nativeModule: string;
  abi: string;
  nativeWindow: boolean;
  cpuPresent: boolean;
  vulkanLinked: boolean;
  vulkanProbeResult: number;
  vulkanApiVersion: number;
  instanceExtensionResult: number;
  instanceExtensions: string[];
  hasKhrSurface: boolean;
  hasOhosSurface: boolean;
  hasArkUiVulkanSurface: boolean;
  instanceCreateResult: number;
  physicalDeviceResult: number;
  physicalDeviceCount: number;
  swapchainDeviceCount: number;
  hasSwapchain: boolean;
  presentBackend: string;
}

export interface StagedFile {
  rawPath: string;
  targetPath: string;
  size: number;
  hash: string;
  copied: boolean;
}

export interface StageResult {
  rawRoot: string;
  targetName: string;
  targetPath: string;
  fileCount: number;
  copiedCount: number;
  skippedCount: number;
  totalBytes: number;
  manifestPath: string;
  files: StagedFile[];
}

export interface SurfaceResult {
  success: boolean;
  xcomponentId: string;
  renderer: string;
  message: string;
  windowHandle?: string;
  width?: number;
  height?: number;
  generation?: number;
  nativeWindowConfigured?: boolean;
}

export interface SurfaceState {
  success: boolean;
  xcomponentId: string;
  renderer: string;
  surfaceReady: boolean;
  windowHandle: string;
  width: number;
  height: number;
  offsetX: number;
  offsetY: number;
  generation: number;
  destroyCount: number;
  nativeWindowConfigured: boolean;
  frameWidth: number;
  frameHeight: number;
  inputSequence: number;
  presentCount: number;
  presentFailCount: number;
  lastPresentMs: number;
  lastPresentSource: string;
  lastPresentMessage: string;
  lastPresentWidth: number;
  lastPresentHeight: number;
  lastPresentFrame: number;
}

export interface FrameResult {
  success: boolean;
  xcomponentId: string;
  framePath: string;
  source: string;
  message: string;
  width?: number;
  height?: number;
  frameNumber?: number;
  inputSequence?: number;
}

export interface NativeInputBridgeResult {
  success: boolean;
  xcomponentId: string;
  message: string;
  inputPath: string;
  sequence: number;
}

export interface NativePresentReport {
  success: boolean;
  xcomponentId: string;
  message: string;
}

export interface WineRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface WineTextSelection {
  start: number;
  end: number;
}

export interface WineHandwritingAnchorRequest {
  available: boolean;
  editable: boolean;
  reason: string;
  xcomponentId: string;
  sessionId?: string;
  hwnd?: string;
  x: number;
  y: number;
  width: number;
  height: number;
  text: string;
  selectionStart: number;
  selectionEnd: number;
}

export interface ControllerDevice {
  deviceId: number;
  name: string;
  source: string;
  dinputIndex: number;
  xinputIndex: number;
}

export interface ControllerState {
  deviceId: number;
  connected: boolean;
  buttons: Record<string, boolean>;
  axes: Record<string, number>;
}

export interface ControllerOutput {
  deviceId: number;
  lowFrequencyRumble?: number;
  highFrequencyRumble?: number;
  adaptiveTrigger?: string;
  hdHaptics?: string;
}

export interface PrefixResult {
  prefixName: string;
  prefixPath: string;
  created: boolean;
}

export interface LaunchOptions {
  targetPath: string;
  targetIsWinePath?: boolean;
  prefixName?: string;
  args?: string[];
  workingDirectory?: string;
  env?: string[];
  xcomponentId?: string;
}

export interface DesktopLaunchOptions {
  prefixName?: string;
  args?: string[];
  workingDirectory?: string;
  env?: string[];
  xcomponentId?: string;
}

export interface LaunchSession {
  sessionId: string;
  kind: string;
  targetPath: string;
  prefixPath: string;
  status: string;
  commandLine: string;
  reason?: string;
  exitCode?: number;
}

export enum ExecMode {
  NATIVE_CHILD_PROCESS = 'NATIVE_CHILD_PROCESS',
  WORKER_EMULATED_PROCESS = 'WORKER_EMULATED_PROCESS',
  TASKPOOL_EMULATED_PROCESS = 'TASKPOOL_EMULATED_PROCESS'
}

export interface ExecutionCapabilities {
  deviceType: string;
  sdkApiVersion: number;
  childProcessSyscap: boolean;
  nativeChildProcess: boolean;
  workerAvailable: boolean;
  taskpoolAvailable: boolean;
  selectedMode: ExecMode;
  reason: string;
}

export interface WineProcessRequest {
  kind: string;
  targetPath: string;
  targetIsWinePath?: boolean;
  prefixName?: string;
  args?: string[];
  workingDirectory?: string;
  env?: string[];
  xcomponentId?: string;
  preferBackend?: ExecMode;
  shortLived?: boolean;
}

export interface WineProcessResult {
  requestId: string;
  execMode: ExecMode;
  session?: LaunchSession;
  pid?: number;
  processSlotId?: number;
  status: string;
  reason: string;
}

export interface WineBrokerDrainResult {
  prefixName: string;
  brokerRoot: string;
  scanned: number;
  processed: number;
  launched: number;
  blocked: number;
  failed: number;
  messages: string[];
}

export interface ImportWineExecutableRequest {
  sourcePath: string;
  prefixName: string;
  profileName?: string;
  copyDirectory?: boolean;
  executableName?: string;
}

export interface ImportWineInstallerRequest {
  sourcePath: string;
  prefixName: string;
  installerType?: string;
  profileName?: string;
  args?: string[];
}

export interface LaunchProfileOptions {
  xcomponentId?: string;
  argsOverride?: string[];
  envOverride?: string[];
}

export interface WineLaunchProfile {
  profileId: string;
  type: string;
  prefixName: string;
  displayName: string;
  winePath: string;
  hostPath: string;
  workingDirectory: string;
  args: string[];
  env: string[];
  sourceRecordId?: string;
  createdAt: string;
}

export interface WineInstallRecord {
  recordId: string;
  prefixName: string;
  displayName: string;
  installerType: string;
  sourcePath: string;
  stagedPath: string;
  winePath: string;
  args: string[];
  status: string;
  createdAt: string;
  discoveredProfiles: WineLaunchProfile[];
}

export interface ProtonLogEntry {
  time: string;
  tag: string;
  message: string;
}

export interface ProtonState {
  sessionId: string;
  state: string;
  message: string;
}

export function configureHostContext(context: common.UIAbilityContext): void;
export function probeExecutionCapabilities(): ExecutionCapabilities;
export function selectWineExecMode(): ExecMode;
export function launchWineProcess(request: WineProcessRequest): Promise<WineProcessResult>;
export function drainWineProcessBroker(prefixName: string, xcomponentId?: string, maxRequests?: number): Promise<WineBrokerDrainResult>;
export function importWineExecutable(request: ImportWineExecutableRequest): Promise<WineLaunchProfile>;
export function importWineInstaller(request: ImportWineInstallerRequest): Promise<WineInstallRecord>;
export function listWineLaunchProfiles(prefixName: string): WineLaunchProfile[];
export function launchInstaller(recordId: string, options?: LaunchProfileOptions): Promise<LaunchSession>;
export function discoverInstalledApps(prefixName: string): WineLaunchProfile[];
export function launchProfile(profileId: string, options?: LaunchProfileOptions): Promise<LaunchSession>;
export function probeRuntime(): RuntimeProbe;
export function stageRawfileTree(rawRoot: string, targetName: string): Promise<StageResult>;
export function stageRuntime(): Promise<StageResult>;
export function mountSurface(xcomponentId: string): SurfaceResult;
export function queryGraphicsCapabilities(): GraphicsCapabilities;
export function querySurfaceState(xcomponentId: string): SurfaceState;
export function reportWinePresent(xcomponentId: string, source: string, success: boolean, width: number, height: number, frameNumber: number, message: string): NativePresentReport;
export function renderSurfaceFrame(xcomponentId: string, framePath: string): FrameResult;
export function createOrOpenPrefix(prefixName: string): PrefixResult;
export function launchLauncher(options: LaunchOptions): LaunchSession;
export function launchGame(options: LaunchOptions): LaunchSession;
export function launchDesktop(options?: DesktopLaunchOptions): LaunchSession;
export function notifyWineSurfaceResize(windowId: string, width: number, height: number): void;
export function resetSurfaceBridge(prefixName: string, xcomponentId: string): void;
export function readExplorerStatus(prefixName: string): string;
export function injectKeyEvent(xcomponentId: string, action: string, keyCode: number, modifiers: number, source: string, deviceId: number, timestamp: number): NativeInputBridgeResult;
export function consumeHandwritingRequest(): WineHandwritingAnchorRequest;
export function showWineHandwritingAnchor(sessionId: string, hwnd: string, rect: WineRect, text: string, selection: WineTextSelection): void;
export function hideWineHandwritingAnchor(sessionId: string, reason: string): void;
export function commitWineImeText(sessionId: string, hwnd: string, text: string, selection: WineTextSelection, compositionState: string): void;
export function enumerateControllers(): ControllerDevice[];
export function getControllerState(deviceId: number): ControllerState;
export function sendControllerOutput(deviceId: number, output: ControllerOutput): void;
export function stop(sessionId: string): void;
export function onLog(callback: (entry: ProtonLogEntry) => void): () => void;
export function onState(callback: (state: ProtonState) => void): () => void;
