#include <cerrno>
#include <cstring>
#include <dlfcn.h>
#include <string>
#include <unistd.h>
#include <vector>

#define LOG_DOMAIN 0x2330
#define LOG_TAG "Box64Adapter"
#include "hilog/log.h"

extern char **environ;

namespace {
constexpr int LAUNCH_OK = 0;
constexpr int LAUNCH_INVALID_REQUEST = 64;
constexpr int LAUNCH_UNSUPPORTED_PROCESS_MODEL = 65;
constexpr int LAUNCH_MISSING_BOX64_CORE = 127;
constexpr int LAUNCH_MISSING_BOX64_SYMBOL = 126;
constexpr int LAUNCH_WORKDIR_FAILED = 72;
constexpr const char *BOX64_CORE_LIBRARY = "libbox64_hmos_core.so";
constexpr const char *BOX64_CORE_SYMBOL = "box64_hmos_main";
constexpr const char *BOX64_CORE_CALL_SYMBOL = "box64_hmos_call_symbol";

using Box64MainFn = int (*)(int, const char **, char **);
using Box64CallSymbolFn = int (*)(int, const char **, char **, const char *);

struct LaunchRequest {
    std::string box64Path;
    std::string workdir;
    std::string commandLine;
    std::string entrySymbol;
    std::string prefixPath;
    std::vector<std::string> env;
};

std::string ErrorText(int code)
{
    return std::string(strerror(code));
}

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

void ApplyEnvelopeLine(LaunchRequest &request, const std::string &line)
{
    const size_t pos = line.find('=');
    if (pos == std::string::npos) {
        return;
    }

    const std::string key = line.substr(0, pos);
    const std::string value = line.substr(pos + 1);
    if (key == "box64") {
        request.box64Path = value;
    } else if (key == "workdir") {
        request.workdir = value;
    } else if (key == "cmd") {
        request.commandLine = value;
    } else if (key == "entry") {
        request.entrySymbol = value;
    } else if (key == "prefix") {
        request.prefixPath = value;
    } else if (key.rfind("env.", 0) == 0) {
        request.env.push_back(value);
    }
}

LaunchRequest ParseLaunchRequest(const char *text)
{
    LaunchRequest request;
    if (text == nullptr) {
        return request;
    }

    const std::string input(text);
    bool sawEnvelope = false;
    size_t start = 0;
    while (start <= input.size()) {
        const size_t end = input.find('\n', start);
        const std::string line = TrimLineEnding(input.substr(start, end == std::string::npos ? std::string::npos : end - start));
        if (line.find('=') != std::string::npos) {
            sawEnvelope = true;
            ApplyEnvelopeLine(request, line);
        }
        if (end == std::string::npos) {
            break;
        }
        start = end + 1;
    }

    if (!sawEnvelope) {
        request.commandLine = input;
    }
    return request;
}

std::vector<std::string> SplitCommandLine(const std::string &commandLine)
{
    std::vector<std::string> args;
    std::string current;
    bool inSingleQuote = false;
    bool inDoubleQuote = false;
    bool escaping = false;

    for (size_t i = 0; i < commandLine.size(); i++) {
        const char ch = commandLine[i];
        if (escaping) {
            current.push_back(ch);
            escaping = false;
            continue;
        }
        if (ch == '\\' && inDoubleQuote) {
            escaping = true;
            continue;
        }
        if (ch == '\'' && !inDoubleQuote) {
            inSingleQuote = !inSingleQuote;
            continue;
        }
        if (ch == '"' && !inSingleQuote) {
            inDoubleQuote = !inDoubleQuote;
            continue;
        }
        if ((ch == ' ' || ch == '\t') && !inSingleQuote && !inDoubleQuote) {
            if (!current.empty()) {
                args.push_back(current);
                current.clear();
            }
            continue;
        }
        current.push_back(ch);
    }

    if (escaping) {
        current.push_back('\\');
    }
    if (!current.empty()) {
        args.push_back(current);
    }
    return args;
}

std::vector<const char *> BuildArgv(const std::vector<std::string> &items)
{
    std::vector<const char *> argv;
    argv.reserve(items.size() + 1);
    for (size_t i = 0; i < items.size(); i++) {
        argv.push_back(items[i].c_str());
    }
    argv.push_back(nullptr);
    return argv;
}

std::vector<char *> BuildEnvp()
{
    std::vector<char *> envp;
    for (char **item = environ; item != nullptr && *item != nullptr; item++) {
        envp.push_back(*item);
    }
    envp.push_back(nullptr);
    return envp;
}

bool IsSharedObjectPath(const std::string &path)
{
    const size_t query = path.find('?');
    const std::string clean = query == std::string::npos ? path : path.substr(0, query);
    return clean.size() >= 3 && clean.rfind(".so") == clean.size() - 3;
}

void ApplyEnvironmentOverrides(const std::vector<std::string> &overrides)
{
    for (size_t i = 0; i < overrides.size(); i++) {
        const size_t pos = overrides[i].find('=');
        if (pos == std::string::npos) {
            continue;
        }
        const std::string key = overrides[i].substr(0, pos);
        const std::string value = overrides[i].substr(pos + 1);
        if (setenv(key.c_str(), value.c_str(), 1) != 0) {
            const int code = errno;
            OH_LOG_WARN(LOG_APP, "setenv failed key=%{public}s error=%{public}s", key.c_str(), ErrorText(code).c_str());
        }
    }
}

int ChangeWorkdir(const std::string &workdir, std::string &previous)
{
    if (workdir.empty()) {
        return LAUNCH_OK;
    }

    char buffer[4096] = { 0 };
    if (getcwd(buffer, sizeof(buffer)) != nullptr) {
        previous = buffer;
    }

    if (chdir(workdir.c_str()) != 0) {
        const int code = errno;
        OH_LOG_ERROR(LOG_APP, "chdir failed workdir=%{public}s error=%{public}s", workdir.c_str(), ErrorText(code).c_str());
        return code == 0 ? LAUNCH_WORKDIR_FAILED : code;
    }
    return LAUNCH_OK;
}

void RestoreWorkdir(const std::string &previous)
{
    if (!previous.empty() && chdir(previous.c_str()) != 0) {
        const int code = errno;
        OH_LOG_WARN(LOG_APP, "restore cwd failed error=%{public}s", ErrorText(code).c_str());
    }
}

int LaunchBox64InProcess(const LaunchRequest &request)
{
    if (request.commandLine.empty()) {
        OH_LOG_ERROR(LOG_APP, "Box64 command line is empty");
        return LAUNCH_INVALID_REQUEST;
    }

    std::vector<std::string> childArgs = SplitCommandLine(request.commandLine);
    if (childArgs.empty()) {
        OH_LOG_ERROR(LOG_APP, "Box64 command line produced no argv");
        return LAUNCH_INVALID_REQUEST;
    }
    if (!request.entrySymbol.empty() && !IsSharedObjectPath(childArgs[0])) {
        OH_LOG_ERROR(LOG_APP, "HMOS in-process mode requires a guest SO entry, got %{public}s", childArgs[0].c_str());
        return LAUNCH_UNSUPPORTED_PROCESS_MODEL;
    }

    std::vector<std::string> argvItems;
    argvItems.reserve(childArgs.size() + 1);
    argvItems.push_back("box64-hmos-inprocess");
    for (size_t i = 0; i < childArgs.size(); i++) {
        argvItems.push_back(childArgs[i]);
    }
    std::vector<const char *> argv = BuildArgv(argvItems);

    ApplyEnvironmentOverrides(request.env);
    std::vector<char *> envp = BuildEnvp();

    std::string previousWorkdir;
    const int cwdCode = ChangeWorkdir(request.workdir, previousWorkdir);
    if (cwdCode != LAUNCH_OK) {
        return cwdCode;
    }

    dlerror();
    void *core = dlopen(BOX64_CORE_LIBRARY, RTLD_NOW | RTLD_LOCAL);
    if (core == nullptr) {
        RestoreWorkdir(previousWorkdir);
        OH_LOG_ERROR(LOG_APP, "Box64 in-process core missing: %{public}s", LastDlError().c_str());
        return LAUNCH_MISSING_BOX64_CORE;
    }

    dlerror();
    Box64MainFn mainFn = nullptr;
    Box64CallSymbolFn callSymbolFn = nullptr;
    if (request.entrySymbol.empty()) {
        mainFn = reinterpret_cast<Box64MainFn>(dlsym(core, BOX64_CORE_SYMBOL));
    } else {
        callSymbolFn = reinterpret_cast<Box64CallSymbolFn>(dlsym(core, BOX64_CORE_CALL_SYMBOL));
    }
    if (mainFn == nullptr && callSymbolFn == nullptr) {
        const std::string error = LastDlError();
        dlclose(core);
        RestoreWorkdir(previousWorkdir);
        OH_LOG_ERROR(LOG_APP, "Box64 in-process symbol missing: %{public}s", error.c_str());
        return LAUNCH_MISSING_BOX64_SYMBOL;
    }

    OH_LOG_INFO(LOG_APP, "entering Box64 in-process argc=%{public}d env_count=%{public}d entry=%{public}s workdir=%{public}s prefix=%{public}s",
        static_cast<int>(argvItems.size()), static_cast<int>(request.env.size()),
        request.entrySymbol.empty() ? "<elf-entry>" : request.entrySymbol.c_str(),
        request.workdir.c_str(), request.prefixPath.c_str());
    const int rc = request.entrySymbol.empty() ?
        mainFn(static_cast<int>(argvItems.size()), argv.data(), envp.data()) :
        callSymbolFn(static_cast<int>(argvItems.size()), argv.data(), envp.data(), request.entrySymbol.c_str());
    dlclose(core);
    RestoreWorkdir(previousWorkdir);
    OH_LOG_INFO(LOG_APP, "Box64 in-process returned rc=%{public}d", rc);
    return rc;
}
}

extern "C" int box64_hmos_launch(const char *launch_request)
{
    const LaunchRequest request = ParseLaunchRequest(launch_request);
    return LaunchBox64InProcess(request);
}

extern "C" const char *box64_hmos_adapter_process_model()
{
    return "in-process-so-adapter";
}
