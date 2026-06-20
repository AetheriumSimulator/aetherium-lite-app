#include "runtime_bridge.h"

#include <cerrno>
#include <dlfcn.h>
#include <string>

#define LOG_DOMAIN 0x2330
#define LOG_TAG "ProtonRuntime"
#include "hilog/log.h"

namespace {
constexpr int RUNTIME_OK = 0;
constexpr int RUNTIME_INVALID_COMMAND = 64;
constexpr int RUNTIME_MISSING_BOX64 = 127;
constexpr int RUNTIME_MISSING_SYMBOL = 126;
constexpr int RUNTIME_WINE_SERVER_FAILED = 125;

struct LaunchEnvelope {
    std::string prefixPath;
    std::string runtimeRoot;
};

void *gWineServerHandle = nullptr;

std::string LastDlError()
{
    const char *error = dlerror();
    if (error == nullptr) {
        return "unknown dlopen error";
    }
    return error;
}

std::string TrimLineEnding(const std::string &line)
{
    if (!line.empty() && line[line.size() - 1] == '\r') {
        return line.substr(0, line.size() - 1);
    }
    return line;
}

void ApplyEnvelopeLine(LaunchEnvelope &envelope, const std::string &line)
{
    const size_t pos = line.find('=');
    if (pos == std::string::npos) {
        return;
    }

    const std::string key = line.substr(0, pos);
    const std::string value = line.substr(pos + 1);
    if (key == "prefix") {
        envelope.prefixPath = value;
    } else if (key == "runtime") {
        envelope.runtimeRoot = value;
    }
}

LaunchEnvelope ParseLaunchEnvelope(const char *text)
{
    LaunchEnvelope envelope;
    if (text == nullptr) {
        return envelope;
    }

    const std::string input(text);
    size_t start = 0;
    while (start <= input.size()) {
        const size_t end = input.find('\n', start);
        ApplyEnvelopeLine(envelope, TrimLineEnding(input.substr(start, end == std::string::npos ? std::string::npos : end - start)));
        if (end == std::string::npos) {
            break;
        }
        start = end + 1;
    }
    return envelope;
}

int StartWineServerControlPlane(const LaunchEnvelope &envelope)
{
    dlerror();
    if (gWineServerHandle == nullptr) {
        gWineServerHandle = dlopen("libwine_hmos_server.so", RTLD_NOW | RTLD_GLOBAL);
    }
    void *server = gWineServerHandle;
    if (server == nullptr) {
        const std::string error = LastDlError();
        OH_LOG_ERROR(LOG_APP, "Wine in-process server library missing: %{public}s", error.c_str());
        return RUNTIME_WINE_SERVER_FAILED;
    }

    using StartFn = int (*)(const char *, const char *);
    dlerror();
    auto start = reinterpret_cast<StartFn>(dlsym(server, "wine_hmos_server_start"));
    if (start == nullptr) {
        const std::string error = LastDlError();
        OH_LOG_ERROR(LOG_APP, "Wine in-process server symbol missing: %{public}s", error.c_str());
        return RUNTIME_MISSING_SYMBOL;
    }

    const int code = start(envelope.prefixPath.c_str(), envelope.runtimeRoot.c_str());
    if (code != 0) {
        OH_LOG_ERROR(LOG_APP, "Wine in-process server start failed code=%{public}d", code);
        return code == 0 ? RUNTIME_WINE_SERVER_FAILED : code;
    }
    return 0;
}
}

extern "C" int proton_hmos_launch(const char *command_line)
{
    if (command_line == nullptr || command_line[0] == '\0') {
        OH_LOG_ERROR(LOG_APP, "empty Proton launch command");
        return RUNTIME_INVALID_COMMAND;
    }

    OH_LOG_INFO(LOG_APP, "launch request: %{public}s", command_line);

    const LaunchEnvelope envelope = ParseLaunchEnvelope(command_line);
    const int serverCode = StartWineServerControlPlane(envelope);
    if (serverCode != 0) {
        return serverCode;
    }

    dlerror();
    void *box64 = dlopen("libbox64_hmos.so", RTLD_NOW | RTLD_LOCAL);
    if (box64 == nullptr) {
        const std::string error = LastDlError();
        OH_LOG_ERROR(LOG_APP, "Box64 adapter missing: %{public}s", error.c_str());
        return RUNTIME_MISSING_BOX64;
    }

    using Box64LaunchFn = int (*)(const char *);
    dlerror();
    auto launch = reinterpret_cast<Box64LaunchFn>(dlsym(box64, "box64_hmos_launch"));
    if (launch == nullptr) {
        const std::string error = LastDlError();
        OH_LOG_ERROR(LOG_APP, "Box64 adapter symbol missing: %{public}s", error.c_str());
        dlclose(box64);
        return RUNTIME_MISSING_SYMBOL;
    }

    const int code = launch(command_line);
    dlclose(box64);
    return code == 0 ? RUNTIME_OK : code;
}

extern "C" int proton_hmos_launch_child(const char *command_line)
{
    OH_LOG_INFO(LOG_APP, "launch child request received");
    return proton_hmos_launch(command_line);
}

extern "C" const char *proton_hmos_process_model()
{
    return "in-process-so-dispatch";
}
