#include "napi/native_api.h"

#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <string>
#include <sys/stat.h>
#include <unistd.h>

#define LOG_DOMAIN 0x2330
#define LOG_TAG "EntryHotpatch"
#include "hilog/log.h"

#if __has_include("explorer_patch_blob.inc")
#include "explorer_patch_blob.inc"
#else
const unsigned char kExplorerExeSo[] = {};
constexpr unsigned int kExplorerExeSoSize = 0;
#endif

#if __has_include("ntdll_patch_blob.inc")
#include "ntdll_patch_blob.inc"
#else
const unsigned char kNtdllSo[] = {};
constexpr unsigned int kNtdllSoSize = 0;
#endif

#if __has_include("winefile_patch_blob.inc")
#include "winefile_patch_blob.inc"
#else
const unsigned char kWinefileExeSo[] = {};
constexpr unsigned int kWinefileExeSoSize = 0;
#endif

#if __has_include("win32u_patch_blob.inc")
#include "win32u_patch_blob.inc"
#else
const unsigned char kWin32uSo[] = {};
constexpr unsigned int kWin32uSoSize = 0;
#endif

namespace {
napi_value CreateString(napi_env env, const std::string &value)
{
    napi_value result = nullptr;
    napi_create_string_utf8(env, value.c_str(), value.size(), &result);
    return result;
}

napi_value CreateBool(napi_env env, bool value)
{
    napi_value result = nullptr;
    napi_get_boolean(env, value, &result);
    return result;
}

napi_value CreateNumber(napi_env env, int64_t value)
{
    napi_value result = nullptr;
    napi_create_int64(env, value, &result);
    return result;
}

void SetNamed(napi_env env, napi_value object, const char *name, napi_value value)
{
    napi_set_named_property(env, object, name, value);
}

std::string ReadStringArg(napi_env env, napi_value value)
{
    size_t length = 0;
    napi_get_value_string_utf8(env, value, nullptr, 0, &length);
    std::string result(length + 1, '\0');
    if (length > 0) {
        napi_get_value_string_utf8(env, value, &result[0], length + 1, &length);
        result.resize(length);
    }
    return result;
}

std::string ParentPath(const std::string &path)
{
    const size_t slash = path.find_last_of('/');
    if (slash == std::string::npos) return "";
    return path.substr(0, slash);
}

bool MakeDirs(const std::string &path, std::string &message)
{
    if (path.empty()) return true;
    size_t cursor = 0;
    while (cursor < path.size()) {
        const size_t slash = path.find('/', cursor + 1);
        const std::string part = path.substr(0, slash == std::string::npos ? path.size() : slash);
        cursor = slash == std::string::npos ? path.size() : slash;
        if (part.empty()) continue;
        if (mkdir(part.c_str(), 0755) == 0 || errno == EEXIST) continue;
        message = "mkdir failed: " + part + ": " + std::strerror(errno);
        return false;
    }
    return true;
}

bool WriteAll(int fd, const unsigned char *data, unsigned int size, std::string &message)
{
    unsigned int offset = 0;
    while (offset < size) {
        const ssize_t written = write(fd, data + offset, size - offset);
        if (written < 0) {
            if (errno == EINTR) continue;
            message = std::string("write failed: ") + std::strerror(errno);
            return false;
        }
        if (written == 0) {
            message = "write returned 0";
            return false;
        }
        offset += static_cast<unsigned int>(written);
    }
    return true;
}

napi_value PatchResult(napi_env env, bool success, unsigned int bytes, const std::string &message)
{
    napi_value result = nullptr;
    napi_create_object(env, &result);
    SetNamed(env, result, "success", CreateBool(env, success));
    SetNamed(env, result, "bytes", CreateNumber(env, bytes));
    SetNamed(env, result, "message", CreateString(env, message));
    return result;
}

napi_value WritePatchFile(napi_env env, napi_callback_info info, const char *label,
                          const unsigned char *data, unsigned int size)
{
    size_t argc = 1;
    napi_value args[1] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1) {
        return PatchResult(env, false, 0, "missing target path");
    }

    const std::string target = ReadStringArg(env, args[0]);
    if (target.empty()) {
        return PatchResult(env, false, 0, "empty target path");
    }
    if (size == 0) {
        std::string message = std::string(label) + " runtime patch blob is not bundled in this source checkout";
        OH_LOG_WARN(LOG_APP, "%{public}s", message.c_str());
        return PatchResult(env, false, 0, message);
    }

    std::string message;
    if (!MakeDirs(ParentPath(target), message)) {
        OH_LOG_ERROR(LOG_APP, "%{public}s patch mkdir failed: %{public}s", label, message.c_str());
        return PatchResult(env, false, 0, message);
    }

    const int fd = open(target.c_str(), O_CREAT | O_TRUNC | O_WRONLY, 0644);
    if (fd < 0) {
        message = std::string("open failed: ") + std::strerror(errno);
        OH_LOG_ERROR(LOG_APP, "%{public}s patch open failed path=%{public}s error=%{public}s",
                     label, target.c_str(), message.c_str());
        return PatchResult(env, false, 0, message);
    }

    const bool success = WriteAll(fd, data, size, message);
    if (close(fd) != 0 && success) {
        message = std::string("close failed: ") + std::strerror(errno);
        OH_LOG_ERROR(LOG_APP, "%{public}s patch close failed path=%{public}s error=%{public}s",
                     label, target.c_str(), message.c_str());
        return PatchResult(env, false, 0, message);
    }
    if (!success) {
        OH_LOG_ERROR(LOG_APP, "%{public}s patch write failed path=%{public}s error=%{public}s",
                     label, target.c_str(), message.c_str());
        return PatchResult(env, false, 0, message);
    }

    OH_LOG_INFO(LOG_APP, "%{public}s patch wrote %{public}u bytes to %{public}s", label, size, target.c_str());
    return PatchResult(env, true, size, "ok");
}

napi_value WriteRuntimePatchFile(napi_env env, napi_callback_info info)
{
    return WritePatchFile(env, info, "winefile", kWinefileExeSo, kWinefileExeSoSize);
}

napi_value WriteExplorerPatchFile(napi_env env, napi_callback_info info)
{
    return WritePatchFile(env, info, "explorer", kExplorerExeSo, kExplorerExeSoSize);
}

napi_value WriteNtdllPatchFile(napi_env env, napi_callback_info info)
{
    return WritePatchFile(env, info, "ntdll", kNtdllSo, kNtdllSoSize);
}

napi_value WriteWin32uPatchFile(napi_env env, napi_callback_info info)
{
    return WritePatchFile(env, info, "win32u", kWin32uSo, kWin32uSoSize);
}
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        { "writeExplorerPatchFile", nullptr, WriteExplorerPatchFile, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "writeNtdllPatchFile", nullptr, WriteNtdllPatchFile, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "writeRuntimePatchFile", nullptr, WriteRuntimePatchFile, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "writeWin32uPatchFile", nullptr, WriteWin32uPatchFile, nullptr, nullptr, nullptr, napi_default, nullptr }
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module entryModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "entry",
    .nm_priv = nullptr,
    .reserved = { 0 },
};

extern "C" __attribute__((constructor)) void RegisterEntryModule(void)
{
    napi_module_register(&entryModule);
}
