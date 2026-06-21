# Runtime Architecture and Source Guide

这份文档给两类人看：

- 想知道 Aetherium Lite 到底怎么把 Wine/Proton 放进 HarmonyOS 的朋友。
- clone 仓库后想把 Proton、Wine、Box64、DXVK、vkd3d-proton 一起拉下来的开发者。

这不是法律意见；真正发二进制包前还要按最终 runtime payload 再做一次 license audit。

## 一句话原理

Aetherium Lite 是 HarmonyOS App + HSP runtime bridge。ArkUI 负责 Ability、XComponent、输入入口和少量系统能力；Wine/Proton/Box64 走 native shared object 方式被加载进 HarmonyOS 应用侧 runtime，而不是依赖 X11、Wayland 或 HNP。

当前主线更像这样：

```text
HarmonyOS launcher
  -> entry HAP
      -> WineFullWindowsDesktopExperienceAbility / WineStandaloneWindowAbility
      -> ArkUI XComponent surface and input entry
      -> proton HSP
          -> libproton.so NAPI bridge
          -> libproton_hmos_runtime.so runtime bridge
          -> libbox64_hmos.so adapter
          -> libbox64_hmos_core.so in-process Box64 payload
          -> libwine_hmos_server.so optional in-process wineserver bridge
          -> staged Proton/Wine runtime payload in app sandbox
              -> Windows EXE through Wine
              -> frame/input bridge back to XComponent
```

## In-process SO 是什么意思

这里的 in-process 指的是 HarmonyOS native bridge 会用共享库方式加载自己的 runtime 组件，例如 Box64 adapter/core、runtime bridge、wineserver bridge。它不是传统 Linux 桌面上启动一个完整外部 Wine 环境，也不是通过 HNP 挂一个外部 rootfs。

这带来两个后果：

1. 调试和启动更轻，平板/2in1 上更容易避开 HNP 路径。
2. license 合规更敏感，因为 LGPL 组件如果被打进同一个分发包，需要让用户拿到对应源码、修改说明，并保留替换或重建 LGPL 组件的路径。

所以 App 代码可以 MIT，但 runtime 不能被我们重新标成 MIT。

## 为什么 App 仓库不直接提交 runtime

这些东西不进 `aetherium-lite-app` git 历史：

- `proton/src/main/resources/rawfile/runtime/proton/`
- `proton/src/main/libs/arm64-v8a/*.so`
- `entry/src/main/cpp/*_patch_blob.inc`
- `entry/src/main/resources/rawfile/win32-smoke/*.exe`
- `entry/src/main/resources/rawfile/win32-smoke/*.dll`
- `.hap/.hsp/.app/.har`
- 截图、HiLog 文本、UI dump JSON、临时构建目录

原因很简单：

- Proton runtime 很大，GitHub 不适合直接放进源码仓。
- Wine/vkd3d-proton 是 LGPL，二进制分发必须带对应源码和 notice。
- 游戏、启动器、安装器属于用户自己的 payload，不能混进公开仓库。
- 签名证书、profile、keystore、密码不能公开。

## clone 后怎么把 runtime 源码拉下来

默认拉取 manifest 里记录的 verified commit：

```bash
git clone https://github.com/AetheriumSimulator/aetherium-lite-app.git
cd aetherium-lite-app
scripts/proton-runtime/bootstrap_runtime_sources.sh
```

如果在 WSL 里需要代理：

```bash
PROTON_RUNTIME_PROXY=http://172.21.16.1:7897 scripts/proton-runtime/bootstrap_runtime_sources.sh
```

如果要连 Proton 子模块也完整拉下来：

```bash
PROTON_RUNTIME_FETCH_SUBMODULES=1 scripts/proton-runtime/bootstrap_runtime_sources.sh
```

如果你想追上游分支最新，而不是使用当前项目记录的 verified commit：

```bash
PROTON_RUNTIME_PINNED=0 scripts/proton-runtime/bootstrap_runtime_sources.sh
```

如果只运行 `scripts/proton-runtime/fetch_sources.sh`，它只会拉原始上游仓库的 pinned commits，不会自动套 Aetherium patch。完整复现路径是 `bootstrap_runtime_sources.sh`：先同步 runtime recipe 仓库，再拉上游源码，再应用 `source-patches`。

源码会进入：

```text
third_party/proton-runtime/src/proton
third_party/proton-runtime/src/box64
third_party/proton-runtime/src/wine
third_party/proton-runtime/src/dxvk
third_party/proton-runtime/src/vkd3d-proton
```

这些目录被 `.gitignore` 忽略，属于本地 checkout，不会提交到 App 仓库。

这里有一个很重要的对应关系：

- `src/box64/src/wrapped/wrappedlibc.c` 来自 Box64 上游 checkout，本来就不在 App 仓库里。
- `src/box64/src/hmos_inprocess.c` 是 Aetherium 的 Box64 source patch 新增文件，也不在 App 仓库里直接提交。
- `scripts/proton-runtime/bootstrap_runtime_sources.sh` 会从 runtime recipe 仓库同步 `source-patches`，再把这些 patch 应用到本地上游 checkout。
- `scripts/proton-runtime/ensure_runtime_sources.sh all` 可以检查并补齐这些 HMOS 对应源码；如果缺 patch，它会先尝试同步 runtime recipe。

所以 clone `aetherium-lite-app` 以后看到 `third_party/proton-runtime/src` 下面只有占位文件是正常的，不是源码丢了。真正的完整源码树是 fetch upstream + apply Aetherium source patches 之后生成的。

## 这些上游源码自带 LICENSE 吗

是的。当前本地验证到的顶层 license/notice 文件包括：

| Component | Local license files | License family |
| --- | --- | --- |
| Proton | `LICENSE`, `LICENSE.proton` | Proton top-level BSD-style plus bundled third-party licenses |
| Box64 | `LICENSE` | MIT |
| Wine | `LICENSE`, `COPYING.LIB`, `AUTHORS` | LGPL-2.1-or-later |
| DXVK | `LICENSE` | zlib/libpng style |
| vkd3d-proton | `LICENSE`, `COPYING`, `AUTHORS` | LGPL-2.1 |

注意：Proton 的最终 redist payload 里还可能包含 wine-mono、wine-gecko、GStreamer、字体、OpenVR、FAudio 等更多组件。发布 runtime 二进制时要对最终 payload 再生成一份完整 `NOTICE`，不能只看这五个顶层仓库。

## 要建几个库

最少两个：

1. `aetherium-lite-app`
   - 当前这个仓库。
   - 许可证：MIT。
   - 放 HarmonyOS App/HSP 壳、ArkTS UI、native bridge、fetch/build 脚本、patch 元数据、文档、smoke-test 源码。
   - 不放 runtime 二进制、不放上游源码 checkout、不放游戏资源。

2. `aetherium-wine-runtime`
   - 当前使用仓库: https://github.com/caidingding233/aetherium-lite-runtime-using-wine-version-not-the-qemu-emulator-version
   - 许可证：mixed，不要写成单一 MIT。
   - 放 Wine/Proton/Box64/DXVK/vkd3d-proton 的精确 source refs、HarmonyOS patches、构建说明、对应源码归档、runtime release notes。
   - 如果发布修改过的 Wine 或 vkd3d-proton 二进制，这个仓库负责满足 LGPL 的对应源码要求。

可选第三个不是必须：

- `aetherium-runtime-releases` 或者直接用 `aetherium-wine-runtime` 的 GitHub Releases。
- 用来放构建好的 runtime 包、HSP、校验和、NOTICE bundle。
- 不建议把多 GB runtime 直接塞进 git commit 历史。

DualSense/vDS 后面可以先放 App 仓文档和实验代码；等它变成独立 HidDdk/vDS protocol bridge，再考虑单独仓库。

## 二进制发布前 checklist

- 保留 App 源码 MIT LICENSE。
- runtime release 附带第三方 license bundle。
- 发布 LGPL 组件的对应源码、patch 和构建说明。
- 说明用户如何替换或重建 LGPL runtime 组件。
- 不把签名材料、账号数据、游戏资源、商业安装器打包进公开 release。
- 给每个 release 写清楚对应的 Proton/Wine/Box64/DXVK/vkd3d-proton commit。
