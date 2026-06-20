import promptAction from '@ohos.promptAction'
import common from '@ohos.app.ability.common'
import * as Proton from 'proton'
import { consumeAutoStageRuntime } from '../AutoStage'
import {
  defaultFullWineDesktopRequest,
  defaultStandaloneWineWindowRequest,
  WineWindowRequest
} from '../WineWindowLaunch'
import {
  launchFullWineDesktop,
  launchStandaloneWineWindow
} from '../WineAbilityRouting'

const AUTO_STAGE_RUNTIME_FOR_POC: boolean = false

@Entry
@Component
struct Index {
  private readonly surfaceId: string = 'proton_main_surface'
  private readonly launcherRawRoot: string = 'mihoyo-launcher'
  private readonly gameRawRoot: string = 'genshin-impact-game'
  private readonly smokeRawRoot: string = 'win32-smoke'
  private readonly launcherTargetName: string = 'mihoyo-launcher'
  private readonly gameTargetName: string = 'genshin-impact-game'
  private readonly smokeTargetName: string = 'win32-smoke'
  private logUnsubscribe?: () => void
  private stateUnsubscribe?: () => void

  @State private probeText: string = '待探测'
  @State private prefixPath: string = ''
  @State private runtimeStagePath: string = ''
  @State private launcherStagePath: string = ''
  @State private gameStagePath: string = ''
  @State private smokeStagePath: string = ''
  @State private activeSessionId: string = ''
  @State private sessionState: string = '空闲'
  @State private isBusy: boolean = false
  @State private logs: Proton.ProtonLogEntry[] = []
  private autoStageStarted: boolean = false

  aboutToAppear(): void {
    this.logUnsubscribe = Proton.onLog((entry: Proton.ProtonLogEntry): void => {
      const next = this.logs.concat([entry])
      this.logs = next.length > 160 ? next.slice(next.length - 160) : next
    })
    this.stateUnsubscribe = Proton.onState((state: Proton.ProtonState): void => {
      this.activeSessionId = state.sessionId
      this.sessionState = `${state.state}: ${state.message}`
    })
    this.runProbe()
    setTimeout(() => {
      if ((AUTO_STAGE_RUNTIME_FOR_POC || consumeAutoStageRuntime()) && !this.autoStageStarted) {
        this.autoStageStarted = true
        this.addLocalLog('runtime', 'autoStageRuntime requested')
        void this.stageRuntime()
      }
    }, 800)
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
  }

  private addLocalLog(tag: string, message: string): void {
    const entry: Proton.ProtonLogEntry = {
      time: new Date().toISOString(),
      tag,
      message
    }
    const next = this.logs.concat([entry])
    this.logs = next.length > 160 ? next.slice(next.length - 160) : next
  }

  private displayLogs(): Proton.ProtonLogEntry[] {
    const items = this.logs.slice()
    return items.reverse()
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

  private startFullWineDesktop(): void {
    const context = getContext(this) as common.UIAbilityContext
    const request = defaultFullWineDesktopRequest()
    launchFullWineDesktop(context, request).then((): void => {
      this.addLocalLog('process', `WineFullWindowsDesktopExperienceAbility requested: ${request.windowId}`)
      this.showToast('Wine desktop requested')
    }).catch((err: Error): void => {
      const message = err instanceof Error ? err.message : `${err}`
      this.addLocalLog('process', `Wine desktop failed: ${message}`)
      this.showToast(`Wine desktop failed: ${message}`)
    })
  }

  private startWineWindow(kind: string, label: string, rawRoot: string, targetName: string, executableName: string, prefixName: string): void {
    const context = getContext(this) as common.UIAbilityContext
    const request: WineWindowRequest = defaultStandaloneWineWindowRequest()
    request.windowId = `${kind}-${Date.now()}`
    request.kind = 'standalone-window'
    request.label = label
    request.rawRoot = rawRoot
    request.targetName = targetName
    request.executableName = executableName
    request.prefixName = prefixName
    request.autoLaunch = true
    launchStandaloneWineWindow(context, request).then((): void => {
      this.addLocalLog('process', `WineStandaloneWindowAbility requested: ${label} (${request.windowId})`)
      this.showToast(`${label} window requested`)
    }).catch((err: Error): void => {
      const message = err instanceof Error ? err.message : `${err}`
      this.addLocalLog('process', `WineStandaloneWindowAbility failed: ${message}`)
      this.showToast(`Wine window failed: ${message}`)
    })
  }

  private runProbe(): void {
    try {
      const probe = Proton.probeRuntime()
      const vk = probe.vulkanApiVersion > 0 ? `Vulkan ${probe.vulkanApiVersion}` : `vkResult ${probe.vulkanProbeResult}`
      const runtime = probe.runtimeReady ? 'runtime ready' : 'runtime missing'
      this.probeText = `${probe.abi} / ${vk} / ${runtime}`
      this.addLocalLog('probe', JSON.stringify(probe))
      for (let i = 0; i < probe.runtimeComponents.length; i++) {
        const item = probe.runtimeComponents[i]
        if (!item.available) {
          this.addLocalLog('probe', `${item.library}: ${item.error}`)
        }
      }
    } catch (err) {
      const message = err instanceof Error ? err.message : `${err}`
      this.probeText = `失败: ${message}`
      this.addLocalLog('probe', message)
    }
  }

  private mountSurface(): void {
    const result = Proton.mountSurface(this.surfaceId)
    this.addLocalLog('surface', `${result.renderer}: ${result.message}`)
    this.showToast(result.success ? 'Surface 已挂载' : 'Surface 挂载失败')
  }

  private ensurePrefix(prefixName: string = 'genshin-cn'): string {
    const prefix = Proton.createOrOpenPrefix(prefixName)
    this.prefixPath = prefix.prefixPath
    this.addLocalLog('wine', `${prefix.created ? '创建' : '打开'} prefix: ${prefix.prefixPath}`)
    return prefix.prefixPath
  }

  private async stageLauncher(): Promise<void> {
    await this.stageTree(this.launcherRawRoot, this.launcherTargetName, true)
  }

  private async stageGame(): Promise<void> {
    await this.stageTree(this.gameRawRoot, this.gameTargetName, false)
  }

  private async stageSmoke(): Promise<void> {
    await this.stageTree(this.smokeRawRoot, this.smokeTargetName, false)
  }

  private async stageRuntime(): Promise<void> {
    if (this.isBusy) {
      return
    }
    this.isBusy = true
    try {
      const result = await Proton.stageRuntime()
      this.runtimeStagePath = result.targetPath
      this.addLocalLog('box64', `runtime: ${result.fileCount} files, copied ${result.copiedCount}, skipped ${result.skippedCount}`)
      this.showToast('Runtime staged')
      this.runProbe()
    } catch (err) {
      const message = err instanceof Error ? err.message : `${err}`
      this.addLocalLog('box64', message)
      this.showToast(`Runtime 搬运失败: ${message}`)
    } finally {
      this.isBusy = false
    }
  }

  private async ensureRuntimeStaged(): Promise<void> {
    if (this.runtimeStagePath.length > 0) {
      return
    }
    await this.stageRuntime()
    if (this.runtimeStagePath.length === 0) {
      throw new Error('Runtime 未完成 staging')
    }
  }

  private async stageTree(rawRoot: string, targetName: string, launcher: boolean): Promise<void> {
    if (this.isBusy) {
      return
    }
    this.isBusy = true
    try {
      const result = await Proton.stageRawfileTree(rawRoot, targetName)
      if (targetName === this.smokeTargetName) {
        this.smokeStagePath = result.targetPath
      } else if (launcher) {
        this.launcherStagePath = result.targetPath
      } else {
        this.gameStagePath = result.targetPath
      }
      this.addLocalLog('staging', `${targetName}: ${result.fileCount} files, copied ${result.copiedCount}, skipped ${result.skippedCount}`)
      this.showToast(`${targetName} staged`)
    } catch (err) {
      const message = err instanceof Error ? err.message : `${err}`
      this.addLocalLog('staging', message)
      this.showToast(`Staging 失败: ${message}`)
    } finally {
      this.isBusy = false
    }
  }

  private launcherExePath(): string {
    return this.launcherStagePath.length > 0 ? `${this.launcherStagePath}/launcher.exe` : 'mihoyo-launcher/launcher.exe'
  }

  private gameExePath(): string {
    return this.gameStagePath.length > 0 ? `${this.gameStagePath}/YuanShen.exe` : 'genshin-impact-game/YuanShen.exe'
  }

  private smokeExePath(): string {
    return this.smokeStagePath.length > 0 ? `${this.smokeStagePath}/ProtonSmokeWin32.exe` : 'win32-smoke/ProtonSmokeWin32.exe'
  }

  private tinyGameExePath(): string {
    return this.smokeStagePath.length > 0 ? `${this.smokeStagePath}/ProtonTinyGame.exe` : 'win32-smoke/ProtonTinyGame.exe'
  }

  private async launchSmoke(): Promise<void> {
    if (this.isBusy) {
      return
    }
    try {
      await this.ensureRuntimeStaged()
      if (this.smokeStagePath.length === 0) {
        await this.stageSmoke()
      }
      if (this.smokeStagePath.length === 0) {
        throw new Error('Win32 Smoke 未完成 staging')
      }
      this.ensurePrefix('smoke-win11')
      const session = Proton.launchGame({
        targetPath: this.smokeExePath(),
        prefixName: 'smoke-win11',
        xcomponentId: this.surfaceId
      })
      this.activeSessionId = session.sessionId
      this.sessionState = `${session.status}: ${session.reason ? session.reason : session.commandLine}`
      this.addLocalLog('process', `smoke session ${session.sessionId}`)
    } catch (err) {
      const message = err instanceof Error ? err.message : `${err}`
      this.addLocalLog('process', message)
      this.showToast(`Smoke 启动失败: ${message}`)
    }
  }

  private async launchTinyGame(): Promise<void> {
    if (this.isBusy) {
      return
    }
    try {
      await this.ensureRuntimeStaged()
      if (this.smokeStagePath.length === 0) {
        await this.stageSmoke()
      }
      if (this.smokeStagePath.length === 0) {
        throw new Error('Win32 Tiny Game 未完成 staging')
      }
      this.ensurePrefix('tiny-game-win11')
      const session = Proton.launchGame({
        targetPath: this.tinyGameExePath(),
        prefixName: 'tiny-game-win11',
        xcomponentId: this.surfaceId
      })
      this.activeSessionId = session.sessionId
      this.sessionState = `${session.status}: ${session.reason ? session.reason : session.commandLine}`
      this.addLocalLog('process', `tiny game session ${session.sessionId}`)
    } catch (err) {
      const message = err instanceof Error ? err.message : `${err}`
      this.addLocalLog('process', message)
      this.showToast(`Tiny Game 启动失败: ${message}`)
    }
  }

  private async launchLauncher(): Promise<void> {
    if (this.isBusy) {
      return
    }
    try {
      await this.ensureRuntimeStaged()
      if (this.launcherStagePath.length === 0) {
        await this.stageLauncher()
      }
      if (this.launcherStagePath.length === 0) {
        throw new Error('米哈游启动器未完成 staging')
      }
      this.ensurePrefix()
      const session = Proton.launchLauncher({
        targetPath: this.launcherExePath(),
        prefixName: 'genshin-cn',
        xcomponentId: this.surfaceId
      })
      this.activeSessionId = session.sessionId
      this.sessionState = `${session.status}: ${session.reason ? session.reason : session.commandLine}`
      this.addLocalLog('process', `launcher session ${session.sessionId}`)
    } catch (err) {
      const message = err instanceof Error ? err.message : `${err}`
      this.addLocalLog('process', message)
      this.showToast(`启动器启动失败: ${message}`)
    }
  }

  private async launchGame(): Promise<void> {
    if (this.isBusy) {
      return
    }
    try {
      await this.ensureRuntimeStaged()
      if (this.gameStagePath.length === 0) {
        await this.stageGame()
      }
      if (this.gameStagePath.length === 0) {
        throw new Error('原神目录未完成 staging')
      }
      this.ensurePrefix()
      const session = Proton.launchGame({
        targetPath: this.gameExePath(),
        prefixName: 'genshin-cn',
        xcomponentId: this.surfaceId
      })
      this.activeSessionId = session.sessionId
      this.sessionState = `${session.status}: ${session.reason ? session.reason : session.commandLine}`
      this.addLocalLog('process', `game session ${session.sessionId}`)
    } catch (err) {
      const message = err instanceof Error ? err.message : `${err}`
      this.addLocalLog('process', message)
      this.showToast(`原神启动失败: ${message}`)
    }
  }

  private stopActive(): void {
    if (this.activeSessionId.length === 0) {
      this.showToast('没有活动会话')
      return
    }
    Proton.stop(this.activeSessionId)
  }

  build() {
    Column() {
      Row() {
        Column() {
          Text('给脑壳一棒')
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor('#101820')
          Text('Windows 原神 / 米哈游启动器 Proton.Hsp PoC')
            .fontSize(13)
            .fontColor('#52616B')
            .margin({ top: 4 })
        }
        .layoutWeight(1)

        Button('探测')
          .height(36)
          .fontSize(13)
          .backgroundColor('#2F6F73')
          .onClick(() => this.runProbe())
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 18, bottom: 12 })

      Grid() {
        GridItem() {
          this.StatusCell('Runtime', this.probeText, '#2F6F73')
        }
        GridItem() {
          this.StatusCell('Payload', this.runtimeStagePath.length > 0 ? this.runtimeStagePath : '未搬运', '#44546A')
        }
        GridItem() {
          this.StatusCell('Prefix', this.prefixPath.length > 0 ? this.prefixPath : '未创建', '#7A5C00')
        }
        GridItem() {
          this.StatusCell('Session', this.sessionState, '#7C3AED')
        }
      }
      .columnsTemplate('1fr 1fr 1fr 1fr')
      .columnsGap(10)
      .rowsGap(10)
      .height(86)
      .padding({ left: 20, right: 20 })

      Row() {
        Column() {
          XComponent({
            id: this.surfaceId,
            type: XComponentType.SURFACE,
            libraryname: 'proton'
          })
            .width('100%')
            .height('100%')
            .backgroundColor('#0B0F14')
            .borderRadius(8)
            .onLoad(() => this.mountSurface())
        }
        .layoutWeight(1)
        .height('100%')

        Column() {
          this.ActionButton('挂载画面', () => this.mountSurface(), '#2F6F73')
          this.ActionButton('搬 Runtime', () => {
            void this.stageRuntime()
          }, '#44546A')
          this.ActionButton('创建 Prefix', () => this.ensurePrefix(), '#7A5C00')
          this.ActionButton('Wine Desktop', () => this.startFullWineDesktop(), '#1D4ED8')
          this.ActionButton('搬 Smoke', () => {
            void this.stageSmoke()
          }, '#44546A')
          this.ActionButton('启动 Smoke', () => {
            this.startWineWindow('smoke', 'Smoke', this.smokeRawRoot, this.smokeTargetName, 'ProtonSmokeWin32.exe', 'smoke-win11')
          }, '#0F766E')
          this.ActionButton('启动 Tiny Game', () => {
            this.startWineWindow('tiny-game', 'Tiny Game', this.smokeRawRoot, this.smokeTargetName, 'ProtonTinyGame.exe', 'tiny-game-win11')
          }, '#166534')
          this.ActionButton('D3D11 Smoke', () => {
            this.startWineWindow('d3d11-smoke', 'D3D11 Smoke', this.smokeRawRoot, this.smokeTargetName, 'ProtonD3D11Smoke.exe', 'd3d11-smoke-win11')
          }, '#4F46E5')
          this.ActionButton('搬启动器', () => {
            void this.stageLauncher()
          }, '#44546A')
          this.ActionButton('搬原神', () => {
            void this.stageGame()
          }, '#44546A')
          this.ActionButton('启动启动器', () => {
            this.startWineWindow('launcher', 'Launcher', this.launcherRawRoot, this.launcherTargetName, 'launcher.exe', 'genshin-cn')
          }, '#155E75')
          this.ActionButton('启动 YuanShen.exe', () => {
            this.startWineWindow('genshin', 'YuanShen.exe', this.gameRawRoot, this.gameTargetName, 'YuanShen.exe', 'genshin-cn')
          }, '#14532D')
          this.ActionButton('停止', () => this.stopActive(), '#8A1C1C')
        }
        .width(176)
        .height('100%')
        .padding({ left: 12 })
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 20, right: 20, top: 12, bottom: 12 })

      Column() {
        Row() {
          Text('Runtime Log')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#172026')
          Blank()
          Text(this.isBusy ? 'staging...' : `${this.logs.length} lines`)
            .fontSize(12)
            .fontColor('#60717A')
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: 8 })

        List() {
          ForEach(this.displayLogs(), (item: Proton.ProtonLogEntry) => {
            ListItem() {
              Row() {
                Text(item.tag)
                  .width(84)
                  .fontSize(12)
                  .fontColor('#2F6F73')
                  .fontWeight(FontWeight.Medium)
                Text(item.message)
                  .layoutWeight(1)
                  .fontSize(12)
                  .fontColor('#1F2933')
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            }
          }, (item: Proton.ProtonLogEntry) => `${item.time}-${item.tag}-${item.message}`)
        }
        .width('100%')
        .layoutWeight(1)
      }
      .height(178)
      .width('100%')
      .backgroundColor('#F8FAF9')
      .border({ width: 1, color: '#D8E0E2' })
      .borderRadius(8)
      .margin({ left: 20, right: 20, bottom: 18 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#EEF2F1')
  }

  @Builder
  private StatusCell(label: string, value: string, color: string) {
    Column() {
      Text(label)
        .fontSize(12)
        .fontColor(color)
        .fontWeight(FontWeight.Medium)
      Text(value)
        .fontSize(13)
        .fontColor('#1F2933')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 6 })
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor('#F8FAF9')
    .border({ width: 1, color: '#D8E0E2' })
    .borderRadius(8)
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private ActionButton(label: string, action: () => void, color: string) {
    Button(label)
      .width('100%')
      .height(38)
      .fontSize(13)
      .backgroundColor(color)
      .fontColor('#FFFFFF')
      .borderRadius(6)
      .margin({ bottom: 8 })
      .enabled(!this.isBusy)
      .onClick(action)
  }
}
