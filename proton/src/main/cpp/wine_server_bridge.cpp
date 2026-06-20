#include <cerrno>
#include <atomic>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <pthread.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#define LOG_DOMAIN 0x2330
#define LOG_TAG "WineHmosServer"
#include "hilog/log.h"

namespace {
std::mutex gServerMutex;
bool gStarted = false;
std::string gPrefixPath;
std::string gRuntimeRoot;
std::atomic<bool> gNativeServerThreadActive(false);
std::atomic<int> gNativeServerExitCode(0);
constexpr int kFakeWineServerPid = 424242;

#ifdef WINE_HMOS_SERVER_STUB
extern "C" int wine_hmos_wineserver_main(int, char **)
{
    OH_LOG_ERROR(LOG_APP, "Wine native wineserver source is not bundled in this checkout");
    return ENOSYS;
}
#else
extern "C" int wine_hmos_wineserver_main(int argc, char **argv);
#endif

std::string BuildWineServerSocketPath()
{
    if (gPrefixPath.empty()) {
        return {};
    }

    struct stat st {};
    if (stat(gPrefixPath.c_str(), &st) != 0) {
        OH_LOG_WARN(LOG_APP, "Wine in-process server cannot stat prefix=%{public}s errno=%{public}d",
            gPrefixPath.c_str(), errno);
        return {};
    }

    char socketPath[512];
    int written = std::snprintf(socketPath, sizeof(socketPath), "%s/.wineserver/server-%llx-%llx/socket",
        gPrefixPath.c_str(),
        static_cast<unsigned long long>(st.st_dev),
        static_cast<unsigned long long>(st.st_ino));
    if (written <= 0 || static_cast<size_t>(written) >= sizeof(socketPath)) {
        OH_LOG_WARN(LOG_APP, "Wine in-process server socket path overflow prefix=%{public}s", gPrefixPath.c_str());
        return {};
    }
    return socketPath;
}

void *WineServerThreadMain(void *)
{
    char arg0[] = "wineserver";
    char arg1[] = "-f";
    char *argv[] = {arg0, arg1, nullptr};

    OH_LOG_INFO(LOG_APP, "Wine native wineserver thread entering prefix=%{public}s",
        gPrefixPath.empty() ? "<unset>" : gPrefixPath.c_str());
    int code = wine_hmos_wineserver_main(2, argv);
    gNativeServerExitCode.store(code);
    gNativeServerThreadActive.store(false);
    OH_LOG_WARN(LOG_APP, "Wine native wineserver thread returned code=%{public}d", code);
    return reinterpret_cast<void *>(static_cast<intptr_t>(code));
}

int WaitForWineServerSocketLocked()
{
    std::string socketPath = BuildWineServerSocketPath();
    if (socketPath.empty()) {
        return 0;
    }

    for (int i = 0; i < 40; ++i) {
        struct stat st {};
        if (stat(socketPath.c_str(), &st) == 0) {
            OH_LOG_INFO(LOG_APP, "Wine native wineserver socket ready path=%{public}s", socketPath.c_str());
            return 0;
        }
        if (!gNativeServerThreadActive.load()) {
            int exitCode = gNativeServerExitCode.load();
            OH_LOG_ERROR(LOG_APP, "Wine native wineserver exited before socket path=%{public}s code=%{public}d",
                socketPath.c_str(), exitCode);
            return ECHILD;
        }
        usleep(50000);
    }

    OH_LOG_WARN(LOG_APP, "Wine native wineserver socket not ready yet path=%{public}s", socketPath.c_str());
    return 0;
}

int EnsureNativeWineServerThreadLocked()
{
    if (gNativeServerThreadActive.load()) {
        return 0;
    }
    if (gPrefixPath.empty()) {
        OH_LOG_ERROR(LOG_APP, "Wine native wineserver start rejected: prefix is unset");
        return EINVAL;
    }

    setenv("WINEPREFIX", gPrefixPath.c_str(), 1);
    if (!gRuntimeRoot.empty()) {
        setenv("WINE_HMOS_RUNTIME_ROOT", gRuntimeRoot.c_str(), 1);
    }

    pthread_t thread {};
    gNativeServerExitCode.store(0);
    gNativeServerThreadActive.store(true);
    int rc = pthread_create(&thread, nullptr, WineServerThreadMain, nullptr);
    if (rc != 0) {
        gNativeServerThreadActive.store(false);
        OH_LOG_ERROR(LOG_APP, "Wine native wineserver pthread_create failed code=%{public}d", rc);
        return rc;
    }
    pthread_detach(thread);
    return WaitForWineServerSocketLocked();
}
}

extern "C" const char *wine_hmos_server_process_model()
{
    return "in-process-native-wineserver-thread";
}

extern "C" __attribute__((noreturn)) void wine_hmos_server_exit(int status)
{
    gNativeServerExitCode.store(status);
    gNativeServerThreadActive.store(false);
    OH_LOG_WARN(LOG_APP, "Wine native wineserver thread exit requested status=%{public}d", status);
    pthread_exit(reinterpret_cast<void *>(static_cast<intptr_t>(status)));
    __builtin_unreachable();
}

extern "C" int wine_hmos_server_start(const char *prefix_path, const char *runtime_root)
{
    if (prefix_path == nullptr || prefix_path[0] == '\0') {
        OH_LOG_ERROR(LOG_APP, "Wine in-process server start rejected: empty prefix");
        return EINVAL;
    }
    if (runtime_root == nullptr || runtime_root[0] == '\0') {
        OH_LOG_ERROR(LOG_APP, "Wine in-process server start rejected: empty runtime root");
        return EINVAL;
    }

    std::lock_guard<std::mutex> lock(gServerMutex);
    gPrefixPath = prefix_path;
    gRuntimeRoot = runtime_root;
    if (!gStarted) {
        gStarted = true;
        OH_LOG_INFO(LOG_APP, "Wine in-process control plane started prefix=%{public}s runtime=%{public}s",
            gPrefixPath.c_str(), gRuntimeRoot.c_str());
    } else {
        OH_LOG_INFO(LOG_APP, "Wine in-process control plane reused prefix=%{public}s runtime=%{public}s",
            gPrefixPath.c_str(), gRuntimeRoot.c_str());
    }
    return 0;
}

extern "C" void wine_hmos_server_stop()
{
    std::lock_guard<std::mutex> lock(gServerMutex);
    if (!gStarted) {
        return;
    }
    OH_LOG_INFO(LOG_APP, "Wine in-process control plane stopped prefix=%{public}s", gPrefixPath.c_str());
    gStarted = false;
    gPrefixPath.clear();
    gRuntimeRoot.clear();
}

extern "C" int wine_hmos_server_spawn_wineserver(const char *path, int *pid_out)
{
    if (pid_out != nullptr) {
        *pid_out = -1;
    }

    std::lock_guard<std::mutex> lock(gServerMutex);
    const char *fakeSpawn = std::getenv("WINE_HMOS_FAKE_WINESERVER");
    if (fakeSpawn != nullptr && std::strcmp(fakeSpawn, "1") == 0) {
        if (pid_out != nullptr) {
            *pid_out = kFakeWineServerPid;
        }
        OH_LOG_WARN(LOG_APP,
            "Wine in-process wineserver fake-spawn enabled path=%{public}s prefix=%{public}s runtime=%{public}s pid=%{public}d",
            path != nullptr ? path : "<null>",
            gPrefixPath.empty() ? "<unset>" : gPrefixPath.c_str(),
            gRuntimeRoot.empty() ? "<unset>" : gRuntimeRoot.c_str(),
            kFakeWineServerPid);
        return 0;
    }

    int rc = EnsureNativeWineServerThreadLocked();
    if (rc != 0) {
        if (pid_out != nullptr) {
            *pid_out = -1;
        }
        OH_LOG_ERROR(LOG_APP,
            "Wine native wineserver start failed path=%{public}s prefix=%{public}s runtime=%{public}s code=%{public}d",
            path != nullptr ? path : "<null>",
            gPrefixPath.empty() ? "<unset>" : gPrefixPath.c_str(),
            gRuntimeRoot.empty() ? "<unset>" : gRuntimeRoot.c_str(),
            rc);
        return rc;
    }

    if (pid_out != nullptr) {
        *pid_out = kFakeWineServerPid;
    }
    OH_LOG_INFO(LOG_APP,
        "Wine native wineserver spawn handled path=%{public}s prefix=%{public}s runtime=%{public}s pid=%{public}d",
        path != nullptr ? path : "<null>",
        gPrefixPath.empty() ? "<unset>" : gPrefixPath.c_str(),
        gRuntimeRoot.empty() ? "<unset>" : gRuntimeRoot.c_str(),
        kFakeWineServerPid);
    return 0;
}
