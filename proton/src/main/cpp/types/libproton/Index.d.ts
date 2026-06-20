export interface NativeRuntimeComponent {
  name: string;
  library: string;
  available: boolean;
  error: string;
}

export interface NativeRuntimeProbe {
  nativeModule: string;
  abi: string;
  vulkanLinked: boolean;
  vulkanProbeResult: number;
  vulkanApiVersion: number;
  runtimeReady: boolean;
  runtimeComponents: NativeRuntimeComponent[];
  stage: string;
}

export interface NativeGraphicsCapabilities {
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

export interface NativeSurfaceResult {
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

export interface NativeSurfaceState {
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

export interface NativeFrameResult {
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

export interface NativeLaunchSession {
  sessionId: string;
  status: string;
  reason: string;
  exitCode?: number;
}

export interface NativeChmodResult {
  path: string;
  success: boolean;
  errnoCode: number;
  message: string;
}

export interface NativeInputBridgeResult {
  success: boolean;
  xcomponentId: string;
  message: string;
  inputPath: string;
  sequence: number;
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

export const probeRuntime: () => NativeRuntimeProbe;
export const mountSurface: (xcomponentId: string) => NativeSurfaceResult;
export const queryGraphicsCapabilities: () => NativeGraphicsCapabilities;
export const querySurfaceState: (xcomponentId: string) => NativeSurfaceState;
export const reportWinePresent: (xcomponentId: string, source: string, success: number, width: number, height: number, frameNumber: number, message: string) => { success: boolean; xcomponentId: string; message: string };
export const renderSurfaceFrame: (xcomponentId: string, framePath: string) => NativeFrameResult;
export const notifyWineSurfaceResize: (windowId: string, width: number, height: number) => void;
export const injectKeyEvent: (xcomponentId: string, action: string, keyCode: number, modifiers: number, source: string, deviceId: number, timestamp: number) => NativeInputBridgeResult;
export const consumeHandwritingRequest: () => WineHandwritingAnchorRequest;
export const showWineHandwritingAnchor: (sessionId: string, hwnd: string, rect: string, text: string, selection: string) => void;
export const hideWineHandwritingAnchor: (sessionId: string, reason: string) => void;
export const commitWineImeText: (sessionId: string, hwnd: string, text: string, selection: string, compositionState: string) => void;
export const enumerateControllers: () => ControllerDevice[];
export const getControllerState: (deviceId: number) => ControllerState;
export const sendControllerOutput: (deviceId: number, output: string) => void;
export const launchSession: (launchRequest: string) => NativeLaunchSession;
export const launchSessionInCurrentProcess: (launchRequest: string) => NativeLaunchSession;
export const chmodExecutable: (path: string) => NativeChmodResult;
export const stopSession: (sessionId: string) => void;
