# Build From Source

这份文档回答一个最常见的问题：我只是路过看到了这个 repo，想自己从源码编译，应该怎么拉、怎么打包？

## 先说结论

推荐入口不是直接跑 `fetch_sources.sh`，而是：

```bash
scripts/proton-runtime/bootstrap_runtime_sources.sh
```

它会做三件事：

1. 同步 Aetherium runtime recipe 仓库。
2. 拉 Proton、Box64、Wine、DXVK、vkd3d-proton 的原始上游 pinned commits。
3. 套用 Aetherium 的 source patches。

所以它不是下载一个“已经改好的巨大 fork”。正确模型是：

```text
original upstream source at pinned commit
  + Aetherium runtime recipe
  + Aetherium source patches
  = current Aetherium Lite runtime source tree
```

这样更利于复现、审计和 LGPL 对应源码合规。

## Clone

```bash
git clone https://github.com/AetheriumSimulator/aetherium-lite-app.git
cd aetherium-lite-app
```

## Fetch Runtime Sources

普通情况：

```bash
scripts/proton-runtime/bootstrap_runtime_sources.sh
```

如果 WSL 需要代理：

```bash
PROTON_RUNTIME_PROXY=http://172.21.16.1:7897 scripts/proton-runtime/bootstrap_runtime_sources.sh
```

如果要连 Proton submodules 一起拉：

```bash
PROTON_RUNTIME_FETCH_SUBMODULES=1 scripts/proton-runtime/bootstrap_runtime_sources.sh
```

只想拉原始上游、不套 Aetherium patch：

```bash
scripts/proton-runtime/fetch_sources.sh
```

注意两个容易误会的文件：

- `third_party/proton-runtime/src/box64/src/wrapped/wrappedlibc.c` 是 Box64 上游源码，只有跑完 `fetch_sources.sh` 或 `bootstrap_runtime_sources.sh` 才会出现。
- `third_party/proton-runtime/src/box64/src/hmos_inprocess.c` 是 Aetherium 对 Box64 的 HMOS in-process 入口，不在 Box64 上游，跑 `bootstrap_runtime_sources.sh` 后由 runtime recipe 仓库里的 `source-patches/box64/0001-hmos-local-working-tree.patch` 生成。

如果已经拉了上游源码但 HMOS patch 结果不完整，可以单独补一次：

```bash
scripts/proton-runtime/ensure_runtime_sources.sh box64
```

## Build Runtime Payload

Box64 in-process payload：

```bash
scripts/proton-runtime/configure_box64_hmos.sh
scripts/proton-runtime/build_box64_hmos.sh
scripts/proton-runtime/install_box64_payload.sh
```

Proton/Wine redist payload 需要 Proton SDK 容器环境：

```bash
scripts/proton-runtime/configure_proton_redist.sh
scripts/proton-runtime/build_proton_redist.sh
scripts/proton-runtime/install_proton_redist_payload.sh
```

小型 Win32 smoke test：

```bash
scripts/proton-runtime/build_win32_smoke.sh
```

## Build HarmonyOS Packages

公开仓库不带签名材料。先在 DevEco Studio 里给项目配置自己的 HarmonyOS signing config，或者用你自己的 CI secrets。

然后打 HSP/HAP：

```powershell
& "C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat" --mode module -p module=proton assembleHsp
& "C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat" --mode module -p module=entry assembleHap
```

如果没有配置签名，源码仍然可以编译到一定阶段，但安装到真机前必须用自己的签名配置生成可安装 HAP。

## What Gets Downloaded

`bootstrap_runtime_sources.sh` 会把上游源码放在：

```text
third_party/proton-runtime/src/proton
third_party/proton-runtime/src/box64
third_party/proton-runtime/src/wine
third_party/proton-runtime/src/dxvk
third_party/proton-runtime/src/vkd3d-proton
```

这些目录被 `.gitignore` 忽略，不会被提交到 App 仓库。

runtime recipe 仓库在本地缓存到：

```text
.tmp/proton-runtime-recipe
```

它包含 manifest、license copies 和 Aetherium source patches。
