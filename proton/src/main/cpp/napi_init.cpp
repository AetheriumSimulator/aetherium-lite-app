#include "napi/native_api.h"

#include <ace/xcomponent/native_interface_xcomponent.h>
#include <native_buffer/native_buffer.h>
#include <native_window/external_window.h>
#include <algorithm>
#include <cerrno>
#include <cstdlib>
#include <ctime>
#include <cstring>
#include <cstdint>
#include <cstdio>
#include <dlfcn.h>
#include <fcntl.h>
#include <dirent.h>
#include <mutex>
#include <string>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <thread>
#include <unordered_map>
#include <unistd.h>
#include <vector>

#define LOG_DOMAIN 0x2330
#define LOG_TAG "ProtonHsp"
#include "hilog/log.h"
#define VK_USE_PLATFORM_OHOS 1
#include "vulkan/vulkan.h"

namespace {
struct RuntimeComponent {
    const char *name;
    const char *library;
    const char *processModelSymbol;
};

struct LaunchChildResult {
    std::string status;
    std::string reason;
    int exitCode;
    bool hasExitCode;
};

struct HmosFrame {
    bool valid = false;
    uint32_t width = 0;
    uint32_t height = 0;
    uint32_t stride = 0;
    uint64_t frameNumber = 0;
    std::vector<uint8_t> pixels;
};

struct XComponentSurfaceRecord {
    OH_NativeXComponent *component = nullptr;
    void *window = nullptr;
    uint64_t width = 0;
    uint64_t height = 0;
    double offsetX = 0;
    double offsetY = 0;
    bool surfaceReady = false;
    int32_t lastSizeCode = OH_NATIVEXCOMPONENT_RESULT_FAILED;
    uint64_t renderCount = 0;
    uint32_t frameWidth = 0;
    uint32_t frameHeight = 0;
    uint64_t generation = 0;
    uint64_t destroyCount = 0;
    bool nativeWindowConfigured = false;
    uint64_t presentCount = 0;
    uint64_t presentFailCount = 0;
    int64_t lastPresentMs = 0;
    uint32_t lastPresentWidth = 0;
    uint32_t lastPresentHeight = 0;
    uint64_t lastPresentFrame = 0;
    std::string lastPresentSource;
    std::string lastPresentMessage;
    std::string inputPath;
    uint64_t inputSeq = 0;
    int64_t lastMoveInputMs = 0;
};

struct HandwritingRequest {
    bool available = false;
    bool editable = false;
    std::string reason;
    std::string xcomponentId;
    std::string sessionId;
    std::string hwnd;
    double x = 0;
    double y = 0;
    double width = 240;
    double height = 56;
    std::string text;
    int32_t selectionStart = 0;
    int32_t selectionEnd = 0;
};

constexpr RuntimeComponent RUNTIME_COMPONENTS[] = {
    { "proton-runtime", "libproton_hmos_runtime.so", "proton_hmos_process_model" },
    { "wine-inprocess-server", "libwine_hmos_server.so", "wine_hmos_server_process_model" },
    { "box64-adapter", "libbox64_hmos.so", "box64_hmos_adapter_process_model" },
    { "box64-inprocess", "libbox64_hmos_core.so", "box64_hmos_process_model" }
};

std::mutex g_surfaceMutex;
std::unordered_map<std::string, XComponentSurfaceRecord> g_surfaceRecords;
std::unordered_map<std::string, HmosFrame> g_lastSurfaceFrames;
uint64_t g_surfaceGeneration = 0;
std::mutex g_handwritingMutex;
HandwritingRequest g_handwritingRequest;
constexpr bool kVerboseXComponentLogs = false;
constexpr bool kTraceInputBridgeEvents = true;
constexpr int64_t kMoveInputMinIntervalMs = 12;

void OnSurfaceCreated(OH_NativeXComponent *component, void *window);
void OnSurfaceChanged(OH_NativeXComponent *component, void *window);
void OnSurfaceDestroyed(OH_NativeXComponent *component, void *window);
void DispatchTouchEvent(OH_NativeXComponent *component, void *window);
bool DispatchKeyEvent(OH_NativeXComponent *component, void *window);

OH_NativeXComponent_Callback g_xcomponentCallback = {
    OnSurfaceCreated,
    OnSurfaceChanged,
    OnSurfaceDestroyed,
    DispatchTouchEvent
};

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

napi_value CreateInt(napi_env env, int32_t value)
{
    napi_value result = nullptr;
    napi_create_int32(env, value, &result);
    return result;
}

napi_value CreateNumber(napi_env env, double value)
{
    napi_value result = nullptr;
    napi_create_double(env, value, &result);
    return result;
}

template <typename Integer>
napi_value CreateUint64AsNumber(napi_env env, Integer value)
{
    return CreateNumber(env, static_cast<double>(value));
}

void SetNamed(napi_env env, napi_value object, const char *name, napi_value value)
{
    napi_set_named_property(env, object, name, value);
}

napi_value CreateStringArray(napi_env env, const std::vector<std::string> &items)
{
    napi_value result = nullptr;
    napi_create_array_with_length(env, items.size(), &result);
    for (size_t i = 0; i < items.size(); i++) {
        napi_set_element(env, result, static_cast<uint32_t>(i), CreateString(env, items[i]));
    }
    return result;
}

std::string ReadStringArg(napi_env env, napi_value value)
{
    size_t len = 0;
    napi_get_value_string_utf8(env, value, nullptr, 0, &len);
    std::string temp(len + 1, '\0');
    napi_get_value_string_utf8(env, value, &temp[0], temp.size(), &len);
    return std::string(temp.c_str(), len);
}

std::string ParentPathOfFile(const std::string &path)
{
    const size_t slash = path.find_last_of('/');
    if (slash == std::string::npos) {
        return "";
    }
    return path.substr(0, slash);
}

std::string BaseNameOfFile(const std::string &path)
{
    const size_t slash = path.find_last_of('/');
    return slash == std::string::npos ? path : path.substr(slash + 1);
}

std::string DeriveInputPathFromFramePath(const std::string &framePath)
{
    if (framePath.empty()) {
        return "";
    }
    const std::string parent = ParentPathOfFile(framePath);
    const std::string name = BaseNameOfFile(framePath);
    const std::string framePrefix = "hmos-frame-";
    const std::string frameSuffix = ".bgra";
    if (name.rfind(framePrefix, 0) == 0 &&
        name.size() > framePrefix.size() + frameSuffix.size() &&
        name.compare(name.size() - frameSuffix.size(), frameSuffix.size(), frameSuffix) == 0) {
        const std::string token = name.substr(framePrefix.size(), name.size() - framePrefix.size() - frameSuffix.size());
        return parent.empty() ? std::string("hmos-input-") + token + ".txt" :
            parent + "/hmos-input-" + token + ".txt";
    }
    return framePath + ".input";
}

int32_t ReadIntArg(napi_env env, napi_value value)
{
    int32_t result = 0;
    napi_get_value_int32(env, value, &result);
    return result;
}

int64_t ReadInt64Arg(napi_env env, napi_value value)
{
    int64_t result = 0;
    napi_get_value_int64(env, value, &result);
    return result;
}

std::string HexPointer(const void *value)
{
    char buffer[32] = { 0 };
    snprintf(buffer, sizeof(buffer), "0x%llx", static_cast<unsigned long long>(reinterpret_cast<uintptr_t>(value)));
    return buffer;
}

int64_t MonotonicMillis()
{
    timespec ts = {};
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) {
        return 0;
    }
    return static_cast<int64_t>(ts.tv_sec) * 1000 + static_cast<int64_t>(ts.tv_nsec / 1000000);
}

bool HasString(const std::vector<std::string> &items, const char *value)
{
    for (const std::string &item : items) {
        if (item == value) {
            return true;
        }
    }
    return false;
}

std::vector<std::string> EnumerateVulkanInstanceExtensions(VkResult &result)
{
    std::vector<std::string> names;
    uint32_t count = 0;
    result = vkEnumerateInstanceExtensionProperties(nullptr, &count, nullptr);
    if (result != VK_SUCCESS || count == 0) {
        return names;
    }
    std::vector<VkExtensionProperties> props(count);
    result = vkEnumerateInstanceExtensionProperties(nullptr, &count, props.data());
    if (result != VK_SUCCESS && result != VK_INCOMPLETE) {
        names.clear();
        return names;
    }
    for (uint32_t i = 0; i < count; i++) {
        names.emplace_back(props[i].extensionName);
    }
    return names;
}

struct VulkanDeviceProbe {
    VkResult instanceResult = VK_SUCCESS;
    VkResult physicalDeviceResult = VK_SUCCESS;
    uint32_t physicalDeviceCount = 0;
    uint32_t swapchainDeviceCount = 0;
};

VulkanDeviceProbe ProbeVulkanDevices(const std::vector<std::string> &instanceExtensions)
{
    VulkanDeviceProbe probe;
    std::vector<const char *> enabledExtensions;
    if (HasString(instanceExtensions, VK_KHR_SURFACE_EXTENSION_NAME)) {
        enabledExtensions.push_back(VK_KHR_SURFACE_EXTENSION_NAME);
    }
    if (HasString(instanceExtensions, VK_OHOS_SURFACE_EXTENSION_NAME)) {
        enabledExtensions.push_back(VK_OHOS_SURFACE_EXTENSION_NAME);
    }

    VkApplicationInfo appInfo = {};
    appInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    appInfo.pApplicationName = "proton-hmos-capability-probe";
    appInfo.applicationVersion = 1;
    appInfo.pEngineName = "wineonarkui";
    appInfo.engineVersion = 1;
    appInfo.apiVersion = VK_API_VERSION_1_0;

    VkInstanceCreateInfo createInfo = {};
    createInfo.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    createInfo.pApplicationInfo = &appInfo;
    createInfo.enabledExtensionCount = static_cast<uint32_t>(enabledExtensions.size());
    createInfo.ppEnabledExtensionNames = enabledExtensions.empty() ? nullptr : enabledExtensions.data();

    VkInstance instance = VK_NULL_HANDLE;
    probe.instanceResult = vkCreateInstance(&createInfo, nullptr, &instance);
    if (probe.instanceResult != VK_SUCCESS) {
        return probe;
    }

    uint32_t deviceCount = 0;
    probe.physicalDeviceResult = vkEnumeratePhysicalDevices(instance, &deviceCount, nullptr);
    if (probe.physicalDeviceResult == VK_SUCCESS && deviceCount > 0) {
        std::vector<VkPhysicalDevice> devices(deviceCount);
        probe.physicalDeviceResult = vkEnumeratePhysicalDevices(instance, &deviceCount, devices.data());
        if (probe.physicalDeviceResult == VK_SUCCESS || probe.physicalDeviceResult == VK_INCOMPLETE) {
            probe.physicalDeviceCount = deviceCount;
            for (uint32_t i = 0; i < deviceCount; i++) {
                uint32_t extensionCount = 0;
                if (vkEnumerateDeviceExtensionProperties(devices[i], nullptr, &extensionCount, nullptr) != VK_SUCCESS ||
                    extensionCount == 0) {
                    continue;
                }
                std::vector<VkExtensionProperties> deviceExtensions(extensionCount);
                if (vkEnumerateDeviceExtensionProperties(devices[i], nullptr, &extensionCount,
                    deviceExtensions.data()) != VK_SUCCESS) {
                    continue;
                }
                for (uint32_t j = 0; j < extensionCount; j++) {
                    if (strcmp(deviceExtensions[j].extensionName, VK_KHR_SWAPCHAIN_EXTENSION_NAME) == 0) {
                        probe.swapchainDeviceCount++;
                        break;
                    }
                }
            }
        }
    }
    vkDestroyInstance(instance, nullptr);
    return probe;
}

const char *TouchTypeName(OH_NativeXComponent_TouchEventType type)
{
    switch (type) {
        case OH_NATIVEXCOMPONENT_DOWN:
            return "DOWN";
        case OH_NATIVEXCOMPONENT_UP:
            return "UP";
        case OH_NATIVEXCOMPONENT_MOVE:
            return "MOVE";
        case OH_NATIVEXCOMPONENT_CANCEL:
            return "CANCEL";
        default:
            return "UNKNOWN";
    }
}

const char *ToolTypeName(OH_NativeXComponent_TouchPointToolType tool)
{
    switch (tool) {
        case OH_NATIVEXCOMPONENT_TOOL_TYPE_FINGER:
            return "FINGER";
        case OH_NATIVEXCOMPONENT_TOOL_TYPE_PEN:
            return "PEN";
        case OH_NATIVEXCOMPONENT_TOOL_TYPE_RUBBER:
            return "RUBBER";
        case OH_NATIVEXCOMPONENT_TOOL_TYPE_BRUSH:
            return "BRUSH";
        case OH_NATIVEXCOMPONENT_TOOL_TYPE_PENCIL:
            return "PENCIL";
        case OH_NATIVEXCOMPONENT_TOOL_TYPE_AIRBRUSH:
            return "AIRBRUSH";
        case OH_NATIVEXCOMPONENT_TOOL_TYPE_MOUSE:
            return "MOUSE";
        case OH_NATIVEXCOMPONENT_TOOL_TYPE_LENS:
            return "LENS";
        default:
            return "UNKNOWN";
    }
}

const char *SourceTypeName(OH_NativeXComponent_EventSourceType source)
{
    switch (source) {
        case OH_NATIVEXCOMPONENT_SOURCE_TYPE_MOUSE:
            return "MOUSE";
        case OH_NATIVEXCOMPONENT_SOURCE_TYPE_TOUCHSCREEN:
            return "TOUCHSCREEN";
        case OH_NATIVEXCOMPONENT_SOURCE_TYPE_TOUCHPAD:
            return "TOUCHPAD";
        case OH_NATIVEXCOMPONENT_SOURCE_TYPE_JOYSTICK:
            return "JOYSTICK";
        case OH_NATIVEXCOMPONENT_SOURCE_TYPE_KEYBOARD:
            return "KEYBOARD";
        default:
            return "UNKNOWN";
    }
}

const char *KeyActionName(OH_NativeXComponent_KeyAction action)
{
    switch (action) {
        case OH_NATIVEXCOMPONENT_KEY_ACTION_DOWN:
            return "KEY_DOWN";
        case OH_NATIVEXCOMPONENT_KEY_ACTION_UP:
            return "KEY_UP";
        default:
            return "KEY_UNKNOWN";
    }
}

bool IsStylusTool(OH_NativeXComponent_TouchPointToolType tool)
{
    return tool == OH_NATIVEXCOMPONENT_TOOL_TYPE_PEN ||
           tool == OH_NATIVEXCOMPONENT_TOOL_TYPE_RUBBER ||
           tool == OH_NATIVEXCOMPONENT_TOOL_TYPE_BRUSH ||
           tool == OH_NATIVEXCOMPONENT_TOOL_TYPE_PENCIL ||
           tool == OH_NATIVEXCOMPONENT_TOOL_TYPE_AIRBRUSH;
}

uint32_t ReadLe32(const uint8_t *data)
{
    return static_cast<uint32_t>(data[0]) |
        (static_cast<uint32_t>(data[1]) << 8) |
        (static_cast<uint32_t>(data[2]) << 16) |
        (static_cast<uint32_t>(data[3]) << 24);
}

uint64_t ReadLe64(const uint8_t *data)
{
    uint64_t value = 0;
    for (int i = 7; i >= 0; i--) {
        value = (value << 8) | data[i];
    }
    return value;
}

bool ReadExactFile(const std::string &path, std::vector<uint8_t> &out)
{
    out.clear();
    if (path.empty()) {
        return false;
    }
    const int fd = open(path.c_str(), O_RDONLY);
    if (fd < 0) {
        return false;
    }
    struct stat st = {};
    if (fstat(fd, &st) != 0 || st.st_size <= 0 || st.st_size > 128 * 1024 * 1024) {
        close(fd);
        return false;
    }
    out.resize(static_cast<size_t>(st.st_size));
    size_t offset = 0;
    while (offset < out.size()) {
        const ssize_t count = read(fd, out.data() + offset, out.size() - offset);
        if (count < 0) {
            if (errno == EINTR) {
                continue;
            }
            close(fd);
            out.clear();
            return false;
        }
        if (count == 0) {
            break;
        }
        offset += static_cast<size_t>(count);
    }
    close(fd);
    if (offset != out.size()) {
        out.clear();
        return false;
    }
    return true;
}

bool LoadHmosFrameHeader(const std::string &path, HmosFrame &frame)
{
    frame = {};
    if (path.empty()) {
        return false;
    }
    const int fd = open(path.c_str(), O_RDONLY);
    if (fd < 0) {
        return false;
    }
    struct stat st = {};
    if (fstat(fd, &st) != 0 || st.st_size < 32 || st.st_size > 128 * 1024 * 1024) {
        close(fd);
        return false;
    }
    uint8_t header[32] = {};
    size_t offset = 0;
    while (offset < sizeof(header)) {
        const ssize_t count = read(fd, header + offset, sizeof(header) - offset);
        if (count < 0) {
            if (errno == EINTR) {
                continue;
            }
            close(fd);
            return false;
        }
        if (count == 0) {
            close(fd);
            return false;
        }
        offset += static_cast<size_t>(count);
    }
    close(fd);

    constexpr uint32_t HMOS_FRAME_MAGIC = 0x46574d48; // "HMWF" little-endian.
    const uint32_t magic = ReadLe32(header);
    const uint32_t headerSize = ReadLe32(header + 4);
    const uint32_t width = ReadLe32(header + 8);
    const uint32_t height = ReadLe32(header + 12);
    const uint32_t stride = ReadLe32(header + 16);
    const uint32_t format = ReadLe32(header + 20);
    const uint64_t frameNumber = ReadLe64(header + 24);
    if (magic != HMOS_FRAME_MAGIC || headerSize < 32 ||
        width == 0 || height == 0 || width > 4096 || height > 4096 ||
        stride < width * 4 || stride > 4096 * 4 || format != 1) {
        return false;
    }
    const uint64_t payloadSize = static_cast<uint64_t>(stride) * static_cast<uint64_t>(height);
    if (payloadSize > 128ull * 1024ull * 1024ull ||
        static_cast<uint64_t>(st.st_size) < static_cast<uint64_t>(headerSize) + payloadSize) {
        return false;
    }

    frame.valid = true;
    frame.width = width;
    frame.height = height;
    frame.stride = stride;
    frame.frameNumber = frameNumber;
    return true;
}

bool WriteAllFd(int fd, const char *data, size_t size)
{
    size_t offset = 0;
    while (offset < size) {
        const ssize_t written = write(fd, data + offset, size - offset);
        if (written < 0) {
            if (errno == EINTR) {
                continue;
            }
            return false;
        }
        if (written == 0) {
            return false;
        }
        offset += static_cast<size_t>(written);
    }
    return true;
}

void AppendInputBridgeEvent(const std::string &path, const char *line)
{
    if (path.empty() || line == nullptr) {
        return;
    }
    const int fd = open(path.c_str(), O_CREAT | O_WRONLY | O_APPEND, 0600);
    if (fd < 0) {
        OH_LOG_WARN(LOG_APP, "xcomponent input bridge open failed path=%{public}s errno=%{public}d",
            path.c_str(), errno);
        return;
    }
    if (!WriteAllFd(fd, line, strlen(line))) {
        OH_LOG_WARN(LOG_APP, "xcomponent input bridge write failed path=%{public}s errno=%{public}d",
            path.c_str(), errno);
    }
    close(fd);
}

bool AppendSurfaceKeyBridgeEvent(const std::string &surfaceId, const char *origin, const char *action,
                                 int32_t keyCode, uint64_t modifiers, const char *source,
                                 int64_t deviceId, int64_t timestamp, uint64_t &sequence,
                                 std::string &inputPath, std::string &message)
{
    if (surfaceId.empty()) {
        message = "missing XComponent id";
        return false;
    }
    if (action == nullptr ||
        (strcmp(action, "KEY_DOWN") != 0 && strcmp(action, "KEY_UP") != 0)) {
        message = "unsupported key action";
        return false;
    }

    XComponentSurfaceRecord snapshot;
    bool found = false;
    {
        std::lock_guard<std::mutex> lock(g_surfaceMutex);
        auto it = g_surfaceRecords.find(surfaceId);
        if (it != g_surfaceRecords.end()) {
            sequence = ++it->second.inputSeq;
            snapshot = it->second;
            found = true;
        }
    }
    if (!found) {
        message = "XComponent not registered";
        return false;
    }
    if (snapshot.inputPath.empty()) {
        message = "input bridge path is not ready";
        return false;
    }

    inputPath = snapshot.inputPath;
    const char *safeSource = source == nullptr || source[0] == '\0' ? "ARKUI" : source;
    char line[256] = { 0 };
    snprintf(line, sizeof(line), "%llu %s %d %llu %s %lld %lld\n",
        static_cast<unsigned long long>(sequence), action, keyCode,
        static_cast<unsigned long long>(modifiers), safeSource,
        static_cast<long long>(deviceId), static_cast<long long>(timestamp));
    AppendInputBridgeEvent(snapshot.inputPath, line);
    message = "key event appended";
    if (kVerboseXComponentLogs) {
        OH_LOG_INFO(LOG_APP,
            "%{public}s input key id=%{public}s action=%{public}s key=%{public}d modifiers=%{public}llu source=%{public}s device=%{public}lld time=%{public}lld seq=%{public}llu path=%{public}s",
            origin == nullptr ? "bridge" : origin, surfaceId.c_str(), action, keyCode,
            static_cast<unsigned long long>(modifiers), safeSource,
            static_cast<long long>(deviceId), static_cast<long long>(timestamp),
            static_cast<unsigned long long>(sequence), snapshot.inputPath.c_str());
    }
    return true;
}

bool LoadHmosFrame(const std::string &path, HmosFrame &frame)
{
    static uint32_t readFailureLogs = 0;
    static uint32_t invalidFailureLogs = 0;
    std::vector<uint8_t> bytes;
    if (path.empty()) {
        return false;
    }
    if (!ReadExactFile(path, bytes) || bytes.size() < 32) {
        if (readFailureLogs < 6) {
            struct stat st = {};
            const int statErr = stat(path.c_str(), &st) == 0 ? 0 : errno;
            if (statErr == ENOENT) {
                return false;
            }
            OH_LOG_WARN(LOG_APP,
                "hmos frame unavailable path=%{public}s statErr=%{public}d size=%{public}lld",
                path.c_str(), statErr, statErr == 0 ? static_cast<long long>(st.st_size) : -1);
            readFailureLogs++;
        }
        return false;
    }

    constexpr uint32_t HMOS_FRAME_MAGIC = 0x46574d48; // "HMWF" little-endian.
    const uint32_t magic = ReadLe32(bytes.data());
    const uint32_t headerSize = ReadLe32(bytes.data() + 4);
    const uint32_t width = ReadLe32(bytes.data() + 8);
    const uint32_t height = ReadLe32(bytes.data() + 12);
    const uint32_t stride = ReadLe32(bytes.data() + 16);
    const uint32_t format = ReadLe32(bytes.data() + 20);
    const uint64_t frameNumber = ReadLe64(bytes.data() + 24);
    if (magic != HMOS_FRAME_MAGIC || headerSize < 32 || headerSize > bytes.size() ||
        width == 0 || height == 0 || width > 4096 || height > 4096 ||
        stride < width * 4 || stride > 4096 * 4 || format != 1) {
        if (invalidFailureLogs < 6) {
            OH_LOG_WARN(LOG_APP,
                "hmos frame invalid path=%{public}s magic=%{public}x header=%{public}u size=%{public}ux%{public}u stride=%{public}u format=%{public}u bytes=%{public}zu",
                path.c_str(), magic, headerSize, width, height, stride, format, bytes.size());
            invalidFailureLogs++;
        }
        return false;
    }

    const uint64_t payloadSize = static_cast<uint64_t>(stride) * static_cast<uint64_t>(height);
    if (payloadSize > 128ull * 1024ull * 1024ull ||
        static_cast<uint64_t>(bytes.size()) < static_cast<uint64_t>(headerSize) + payloadSize) {
        if (invalidFailureLogs < 6) {
            OH_LOG_WARN(LOG_APP,
                "hmos frame truncated path=%{public}s payload=%{public}llu bytes=%{public}zu header=%{public}u",
                path.c_str(), static_cast<unsigned long long>(payloadSize), bytes.size(), headerSize);
            invalidFailureLogs++;
        }
        return false;
    }

    frame.valid = true;
    frame.width = width;
    frame.height = height;
    frame.stride = stride;
    frame.frameNumber = frameNumber;
    frame.pixels.assign(bytes.begin() + static_cast<ptrdiff_t>(headerSize),
        bytes.begin() + static_cast<ptrdiff_t>(headerSize + payloadSize));
    return true;
}

void FillRectBgra(uint8_t *dst, size_t dstStride, int width, int height,
                  int left, int top, int right, int bottom,
                  uint8_t b, uint8_t g, uint8_t r, uint8_t a)
{
    left = std::max(0, std::min(left, width));
    right = std::max(0, std::min(right, width));
    top = std::max(0, std::min(top, height));
    bottom = std::max(0, std::min(bottom, height));
    if (left >= right || top >= bottom) {
        return;
    }
    for (int y = top; y < bottom; y++) {
        uint8_t *row = dst + static_cast<size_t>(y) * dstStride + static_cast<size_t>(left) * 4;
        for (int x = left; x < right; x++) {
            row[0] = b;
            row[1] = g;
            row[2] = r;
            row[3] = a;
            row += 4;
        }
    }
}

void DrawBootstrapFrame(uint8_t *dst, size_t dstStride, int width, int height, uint64_t tick)
{
    (void)tick;
    for (int y = 0; y < height; y++) {
        uint8_t *row = dst + static_cast<size_t>(y) * dstStride;
        for (int x = 0; x < width; x++) {
            row[0] = 8;
            row[1] = 8;
            row[2] = 8;
            row[3] = 255;
            row += 4;
        }
    }
}

bool CopyFrameToBuffer(uint8_t *dst, size_t dstStride, int width, int height, const HmosFrame &frame)
{
    if (!frame.valid || frame.width != static_cast<uint32_t>(width) || frame.height != static_cast<uint32_t>(height)) {
        return false;
    }
    const size_t rowBytes = static_cast<size_t>(width) * 4;
    for (int y = 0; y < height; y++) {
        memcpy(dst + static_cast<size_t>(y) * dstStride,
            frame.pixels.data() + static_cast<size_t>(y) * frame.stride,
            rowBytes);
    }
    return true;
}

void RecordSurfacePresent(const std::string &surfaceId, bool success, const char *source, int width, int height,
                          uint64_t frameNumber, const std::string &message)
{
    if (surfaceId.empty()) {
        return;
    }
    std::lock_guard<std::mutex> lock(g_surfaceMutex);
    auto it = g_surfaceRecords.find(surfaceId);
    if (it == g_surfaceRecords.end()) {
        return;
    }
    if (success) {
        it->second.presentCount++;
    } else {
        it->second.presentFailCount++;
    }
    it->second.lastPresentMs = MonotonicMillis();
    it->second.lastPresentSource = source == nullptr ? "" : source;
    it->second.lastPresentWidth = width > 0 ? static_cast<uint32_t>(width) : 0;
    it->second.lastPresentHeight = height > 0 ? static_cast<uint32_t>(height) : 0;
    it->second.lastPresentFrame = frameNumber;
    it->second.lastPresentMessage = message;
}

void ConfigureNativeWindowForCompositor(XComponentSurfaceRecord &record, const std::string &surfaceId)
{
    if (!record.surfaceReady || record.window == nullptr || record.nativeWindowConfigured) {
        return;
    }
    OHNativeWindow *nativeWindow = static_cast<OHNativeWindow *>(record.window);
    const int32_t sourceCode = OH_NativeWindow_NativeWindowHandleOpt(nativeWindow, SET_SOURCE_TYPE, OH_SURFACE_SOURCE_GAME);
    const uint64_t usage = static_cast<uint64_t>(
        NATIVEBUFFER_USAGE_CPU_WRITE | NATIVEBUFFER_USAGE_MEM_DMA |
        NATIVEBUFFER_USAGE_HW_RENDER | NATIVEBUFFER_USAGE_HW_TEXTURE);
    const int32_t usageCode = OH_NativeWindow_NativeWindowHandleOpt(nativeWindow, SET_USAGE, usage);
    record.nativeWindowConfigured = true;
    record.lastPresentSource = "native-window";
    record.lastPresentMessage = std::string("configured source=game code=") + std::to_string(sourceCode) +
        " usageCode=" + std::to_string(usageCode);
    OH_LOG_INFO(LOG_APP,
        "wineonarkui compositor configured id=%{public}s window=%{public}s sourceCode=%{public}d usageCode=%{public}d usage=%{public}llu",
        surfaceId.c_str(), HexPointer(record.window).c_str(), sourceCode, usageCode,
        static_cast<unsigned long long>(usage));
}

size_t ResolveBufferStrideBytes(const BufferHandle *handle, int width, int height)
{
    const size_t minimum = static_cast<size_t>(width) * 4;
    if (handle == nullptr || handle->stride <= 0) {
        return minimum;
    }
    const size_t stride = static_cast<size_t>(handle->stride);
    if (handle->size > 0 && stride >= minimum &&
        stride * static_cast<size_t>(height) <= static_cast<size_t>(handle->size)) {
        return stride;
    }
    return stride * 4;
}

std::string ReadXComponentId(OH_NativeXComponent *component)
{
    if (component == nullptr) {
        return "";
    }
    char id[OH_XCOMPONENT_ID_LEN_MAX + 1] = { 0 };
    uint64_t size = sizeof(id);
    const int32_t code = OH_NativeXComponent_GetXComponentId(component, id, &size);
    if (code != OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
        OH_LOG_WARN(LOG_APP, "xcomponent id read failed code=%{public}d", code);
        return "";
    }
    return std::string(id);
}

void StoreSurfaceRecord(OH_NativeXComponent *component, void *window, bool ready, const char *eventName)
{
    const std::string id = ReadXComponentId(component);
    if (id.empty()) {
        OH_LOG_WARN(LOG_APP, "xcomponent %{public}s ignored: empty id window=%{public}s", eventName, HexPointer(window).c_str());
        return;
    }

    uint64_t width = 0;
    uint64_t height = 0;
    double offsetX = 0;
    double offsetY = 0;
    const int32_t sizeCode = window == nullptr ? OH_NATIVEXCOMPONENT_RESULT_BAD_PARAMETER :
        OH_NativeXComponent_GetXComponentSize(component, window, &width, &height);
    if (window != nullptr) {
        OH_NativeXComponent_GetXComponentOffset(component, window, &offsetX, &offsetY);
    }

    {
        std::lock_guard<std::mutex> lock(g_surfaceMutex);
        XComponentSurfaceRecord &record = g_surfaceRecords[id];
        const bool windowChanged = record.window != window;
        record.component = component;
        record.window = ready ? window : nullptr;
        record.width = ready ? width : 0;
        record.height = ready ? height : 0;
        record.offsetX = ready ? offsetX : 0;
        record.offsetY = ready ? offsetY : 0;
        if (windowChanged || record.surfaceReady != ready) {
            record.generation = ++g_surfaceGeneration;
            record.nativeWindowConfigured = false;
        }
        record.surfaceReady = ready;
        record.lastSizeCode = sizeCode;
        if (ready) {
            ConfigureNativeWindowForCompositor(record, id);
        }
        if (!ready) {
            record.destroyCount++;
            record.lastPresentMessage = "surface destroyed";
            g_lastSurfaceFrames.erase(id);
        }
    }

    OH_LOG_INFO(LOG_APP,
        "xcomponent surface %{public}s id=%{public}s window=%{public}s ready=%{public}d size=%{public}llux%{public}llu sizeCode=%{public}d",
        eventName, id.c_str(), HexPointer(window).c_str(), ready ? 1 : 0,
        static_cast<unsigned long long>(width), static_cast<unsigned long long>(height), sizeCode);
}

void OnSurfaceCreated(OH_NativeXComponent *component, void *window)
{
    StoreSurfaceRecord(component, window, true, "created");
}

void OnSurfaceChanged(OH_NativeXComponent *component, void *window)
{
    StoreSurfaceRecord(component, window, true, "changed");
}

void OnSurfaceDestroyed(OH_NativeXComponent *component, void *window)
{
    StoreSurfaceRecord(component, window, false, "destroyed");
}

void DispatchTouchEvent(OH_NativeXComponent *component, void *window)
{
    OH_NativeXComponent_TouchEvent event = {};
    const int32_t eventCode = OH_NativeXComponent_GetTouchEvent(component, window, &event);
    const std::string id = ReadXComponentId(component);
    if (eventCode != OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
        OH_LOG_WARN(LOG_APP, "xcomponent touch read failed id=%{public}s code=%{public}d window=%{public}s",
            id.c_str(), eventCode, HexPointer(window).c_str());
        return;
    }

    OH_NativeXComponent_TouchPointToolType tool = OH_NATIVEXCOMPONENT_TOOL_TYPE_UNKNOWN;
    const int32_t toolCode = event.numPoints > 0 ?
        OH_NativeXComponent_GetTouchPointToolType(component, 0, &tool) :
        OH_NATIVEXCOMPONENT_RESULT_FAILED;
    OH_NativeXComponent_EventSourceType source = OH_NATIVEXCOMPONENT_SOURCE_TYPE_UNKNOWN;
    const int32_t sourceCode = OH_NativeXComponent_GetTouchEventSourceType(component, event.id, &source);

    if (kVerboseXComponentLogs) {
        OH_LOG_INFO(LOG_APP,
            "xcomponent input touch id=%{public}s action=%{public}s pointId=%{public}d tool=%{public}s toolCode=%{public}d source=%{public}s sourceCode=%{public}d x=%{public}.1f y=%{public}.1f points=%{public}u force=%{public}.3f window=%{public}s",
            id.c_str(), TouchTypeName(event.type), event.id, ToolTypeName(tool), toolCode,
            SourceTypeName(source), sourceCode, event.x, event.y, event.numPoints, event.force,
            HexPointer(window).c_str());
    }

    XComponentSurfaceRecord snapshot;
    uint64_t inputSeq = 0;
    bool skipMove = false;
    const int64_t nowMs = MonotonicMillis();
    {
        std::lock_guard<std::mutex> lock(g_surfaceMutex);
        auto it = g_surfaceRecords.find(id);
        if (it != g_surfaceRecords.end()) {
            if (event.type == OH_NATIVEXCOMPONENT_MOVE &&
                it->second.lastMoveInputMs > 0 &&
                nowMs > 0 &&
                nowMs - it->second.lastMoveInputMs < kMoveInputMinIntervalMs) {
                skipMove = true;
            } else {
                inputSeq = ++it->second.inputSeq;
                if (event.type == OH_NATIVEXCOMPONENT_MOVE) {
                    it->second.lastMoveInputMs = nowMs;
                } else {
                    it->second.lastMoveInputMs = 0;
                }
            }
            snapshot = it->second;
        }
    }
    if (skipMove) {
        return;
    }
    if (!snapshot.inputPath.empty()) {
        const double surfaceWidth = snapshot.width > 0 ? static_cast<double>(snapshot.width) :
            static_cast<double>(snapshot.frameWidth);
        const double surfaceHeight = snapshot.height > 0 ? static_cast<double>(snapshot.height) :
            static_cast<double>(snapshot.frameHeight);
        double mappedX = event.x;
        double mappedY = event.y;
        if (snapshot.frameWidth > 0 && surfaceWidth > 0) {
            mappedX = event.x * static_cast<double>(snapshot.frameWidth) / surfaceWidth;
        }
        if (snapshot.frameHeight > 0 && surfaceHeight > 0) {
            mappedY = event.y * static_cast<double>(snapshot.frameHeight) / surfaceHeight;
        }
        char line[256] = { 0 };
        snprintf(line, sizeof(line), "%llu %s %.2f %.2f %s %s %d %.3f\n",
            static_cast<unsigned long long>(inputSeq), TouchTypeName(event.type), mappedX, mappedY,
            ToolTypeName(tool), SourceTypeName(source), event.id, event.force);
        AppendInputBridgeEvent(snapshot.inputPath, line);
        if (kTraceInputBridgeEvents &&
            (event.type != OH_NATIVEXCOMPONENT_MOVE || inputSeq <= 12 || inputSeq % 180 == 0)) {
            OH_LOG_INFO(LOG_APP,
                "xcomponent input bridge touch id=%{public}s seq=%{public}llu action=%{public}s raw=%{public}.1f,%{public}.1f mapped=%{public}.1f,%{public}.1f surface=%{public}.0fx%{public}.0f frame=%{public}ux%{public}u tool=%{public}s source=%{public}s path=%{public}s",
                id.c_str(), static_cast<unsigned long long>(inputSeq), TouchTypeName(event.type),
                event.x, event.y, mappedX, mappedY, surfaceWidth, surfaceHeight,
                snapshot.frameWidth, snapshot.frameHeight, ToolTypeName(tool), SourceTypeName(source),
                snapshot.inputPath.c_str());
        }
    }

    if (IsStylusTool(tool) && event.type == OH_NATIVEXCOMPONENT_DOWN) {
        if (kVerboseXComponentLogs) {
            OH_LOG_INFO(LOG_APP,
                "handwriting stylus down forwarded to Wine focus path id=%{public}s x=%{public}.1f y=%{public}.1f",
                id.c_str(), event.x, event.y);
        }
        return;
    }

    if (IsStylusTool(tool) && event.type == OH_NATIVEXCOMPONENT_UP) {
        std::lock_guard<std::mutex> lock(g_handwritingMutex);
        g_handwritingRequest.available = true;
        g_handwritingRequest.editable = false;
        g_handwritingRequest.reason = "pen-up-waiting-for-wine-hit-test";
        g_handwritingRequest.xcomponentId = id;
        g_handwritingRequest.sessionId.clear();
        g_handwritingRequest.hwnd.clear();
        g_handwritingRequest.x = event.x;
        g_handwritingRequest.y = event.y;
        g_handwritingRequest.width = 240;
        g_handwritingRequest.height = 56;
        g_handwritingRequest.text.clear();
        g_handwritingRequest.selectionStart = 0;
        g_handwritingRequest.selectionEnd = 0;
        if (kVerboseXComponentLogs) {
            OH_LOG_INFO(LOG_APP,
                "handwriting anchor candidate stored id=%{public}s editable=0 reason=%{public}s x=%{public}.1f y=%{public}.1f",
                id.c_str(), g_handwritingRequest.reason.c_str(), event.x, event.y);
        }
    }
}

bool DispatchKeyEvent(OH_NativeXComponent *component, void *window)
{
    OH_NativeXComponent_KeyEvent *keyEvent = nullptr;
    const int32_t eventCode = OH_NativeXComponent_GetKeyEvent(component, &keyEvent);
    const std::string id = ReadXComponentId(component);
    if (eventCode != OH_NATIVEXCOMPONENT_RESULT_SUCCESS || keyEvent == nullptr) {
        OH_LOG_WARN(LOG_APP, "xcomponent key read failed id=%{public}s code=%{public}d window=%{public}s",
            id.c_str(), eventCode, HexPointer(window).c_str());
        return false;
    }

    OH_NativeXComponent_KeyAction action = OH_NATIVEXCOMPONENT_KEY_ACTION_UNKNOWN;
    OH_NativeXComponent_KeyCode code = KEY_UNKNOWN;
    OH_NativeXComponent_EventSourceType source = OH_NATIVEXCOMPONENT_SOURCE_TYPE_UNKNOWN;
    int64_t deviceId = -1;
    int64_t timestamp = 0;
    uint64_t modifiers = 0;
    const int32_t actionCode = OH_NativeXComponent_GetKeyEventAction(keyEvent, &action);
    const int32_t keyCode = OH_NativeXComponent_GetKeyEventCode(keyEvent, &code);
    const int32_t sourceCode = OH_NativeXComponent_GetKeyEventSourceType(keyEvent, &source);
    OH_NativeXComponent_GetKeyEventDeviceId(keyEvent, &deviceId);
    OH_NativeXComponent_GetKeyEventTimestamp(keyEvent, &timestamp);
    OH_NativeXComponent_GetKeyEventModifierKeyStates(keyEvent, &modifiers);

    XComponentSurfaceRecord snapshot;
    uint64_t inputSeq = 0;
    {
        std::lock_guard<std::mutex> lock(g_surfaceMutex);
        auto it = g_surfaceRecords.find(id);
        if (it != g_surfaceRecords.end()) {
            inputSeq = ++it->second.inputSeq;
            snapshot = it->second;
        }
    }

    if (kVerboseXComponentLogs) {
        OH_LOG_INFO(LOG_APP,
            "xcomponent input key id=%{public}s action=%{public}s actionCode=%{public}d key=%{public}d keyCode=%{public}d source=%{public}s sourceCode=%{public}d device=%{public}lld modifiers=%{public}llu time=%{public}lld path=%{public}s",
            id.c_str(), KeyActionName(action), actionCode, static_cast<int32_t>(code), keyCode,
            SourceTypeName(source), sourceCode, static_cast<long long>(deviceId),
            static_cast<unsigned long long>(modifiers), static_cast<long long>(timestamp),
            snapshot.inputPath.c_str());
    }

    if (!snapshot.inputPath.empty()) {
        char line[256] = { 0 };
        snprintf(line, sizeof(line), "%llu %s %d %llu %s %lld %lld\n",
            static_cast<unsigned long long>(inputSeq), KeyActionName(action), static_cast<int32_t>(code),
            static_cast<unsigned long long>(modifiers), SourceTypeName(source),
            static_cast<long long>(deviceId), static_cast<long long>(timestamp));
        AppendInputBridgeEvent(snapshot.inputPath, line);
        if (kTraceInputBridgeEvents) {
            OH_LOG_INFO(LOG_APP,
                "xcomponent input bridge key id=%{public}s seq=%{public}llu action=%{public}s key=%{public}d modifiers=%{public}llu source=%{public}s path=%{public}s",
                id.c_str(), static_cast<unsigned long long>(inputSeq), KeyActionName(action),
                static_cast<int32_t>(code), static_cast<unsigned long long>(modifiers),
                SourceTypeName(source), snapshot.inputPath.c_str());
        }
    }

    return action == OH_NATIVEXCOMPONENT_KEY_ACTION_DOWN || action == OH_NATIVEXCOMPONENT_KEY_ACTION_UP;
}

void RegisterNativeXComponent(napi_env env, napi_value exports)
{
    napi_value componentValue = nullptr;
    if (napi_get_named_property(env, exports, OH_NATIVE_XCOMPONENT_OBJ, &componentValue) != napi_ok ||
        componentValue == nullptr) {
        OH_LOG_INFO(LOG_APP, "xcomponent native object not present during module init");
        return;
    }

    void *wrapped = nullptr;
    if (napi_unwrap(env, componentValue, &wrapped) != napi_ok || wrapped == nullptr) {
        OH_LOG_WARN(LOG_APP, "xcomponent native object unwrap failed");
        return;
    }

    OH_NativeXComponent *component = static_cast<OH_NativeXComponent *>(wrapped);
    const std::string id = ReadXComponentId(component);
    {
        std::lock_guard<std::mutex> lock(g_surfaceMutex);
        XComponentSurfaceRecord &record = g_surfaceRecords[id];
        record.component = component;
    }

    const int32_t code = OH_NativeXComponent_RegisterCallback(component, &g_xcomponentCallback);
    const int32_t keyCode = OH_NativeXComponent_RegisterKeyEventCallbackWithResult(component, DispatchKeyEvent);
    const int32_t softKeyboardCode = OH_NativeXComponent_SetNeedSoftKeyboard(component, true);
    OH_LOG_INFO(LOG_APP, "xcomponent callback register id=%{public}s component=%{public}s code=%{public}d",
        id.c_str(), HexPointer(component).c_str(), code);
    OH_LOG_INFO(LOG_APP, "xcomponent key callback register id=%{public}s keyCode=%{public}d softKeyboard=%{public}d",
        id.c_str(), keyCode, softKeyboardCode);
}

std::string LastDlError()
{
    const char *error = dlerror();
    if (error == nullptr) {
        return "unknown dlopen error";
    }
    return error;
}

int NormalizeExitCode(int code)
{
    if (code < 0) {
        return 1;
    }
    if (code > 255) {
        return 255;
    }
    return code;
}

LaunchChildResult ResultFromWaitStatus(int status)
{
    if (WIFEXITED(status)) {
        const int code = WEXITSTATUS(status);
        return {
            code == 0 ? "started" : "runtime-error",
            code == 0 ? "proton runtime child exited cleanly" : "proton runtime child exited with error",
            code,
            true
        };
    }
    if (WIFSIGNALED(status)) {
        const int signal = WTERMSIG(status);
        return {
            "runtime-error",
            std::string("proton runtime child crashed with signal ") + std::to_string(signal),
            128 + signal,
            true
        };
    }
    return { "runtime-error", "proton runtime child ended with unknown status", status, true };
}

std::string ExtractLaunchField(const std::string &commandLine, const std::string &name)
{
    const std::string prefix = name + "=";
    size_t cursor = 0;
    while (cursor < commandLine.size()) {
        const size_t lineEnd = commandLine.find('\n', cursor);
        const size_t end = lineEnd == std::string::npos ? commandLine.size() : lineEnd;
        if (end >= cursor + prefix.size() && commandLine.compare(cursor, prefix.size(), prefix) == 0) {
            return commandLine.substr(cursor + prefix.size(), end - cursor - prefix.size());
        }
        if (lineEnd == std::string::npos) {
            break;
        }
        cursor = lineEnd + 1;
    }
    return "";
}

std::string SanitizeLogLeaf(const std::string &value, const char *fallback)
{
    std::string base = value;
    const size_t slash = base.find_last_of("/\\");
    if (slash != std::string::npos) {
        base = base.substr(slash + 1);
    }
    if (base.empty()) {
        base = fallback;
    }

    std::string clean;
    clean.reserve(base.size());
    for (char ch : base) {
        const bool alnum =
            (ch >= '0' && ch <= '9') ||
            (ch >= 'A' && ch <= 'Z') ||
            (ch >= 'a' && ch <= 'z');
        if (alnum) {
            clean.push_back(ch);
        } else if (ch == '.' || ch == '_' || ch == '-') {
            clean.push_back(ch);
        } else if (!clean.empty() && clean.back() != '-') {
            clean.push_back('-');
        }
        if (clean.size() >= 80) {
            break;
        }
    }
    while (!clean.empty() && clean.back() == '-') {
        clean.pop_back();
    }
    return clean.empty() ? fallback : clean;
}

std::string BuildLaunchLogPath(const std::string &commandLine)
{
    const std::string workdir = ExtractLaunchField(commandLine, "workdir");
    if (workdir.empty()) {
        return "";
    }
    const std::string kind = SanitizeLogLeaf(ExtractLaunchField(commandLine, "prepared.kind"), "run");
    const std::string target = SanitizeLogLeaf(ExtractLaunchField(commandLine, "prepared.target"), "target");
    char leaf[192];
    std::snprintf(leaf, sizeof(leaf), "proton-hmos-%s-%s-%ld-%d.log",
        kind.c_str(), target.c_str(), static_cast<long>(time(nullptr)), static_cast<int>(getpid()));
    if (workdir[workdir.size() - 1] == '/') {
        return workdir + leaf;
    }
    return workdir + "/" + leaf;
}

std::string ReadFileTail(const std::string &path, size_t maxBytes)
{
    const int fd = open(path.c_str(), O_RDONLY);
    if (fd < 0) {
        return "";
    }

    struct stat st = {};
    if (fstat(fd, &st) != 0 || st.st_size <= 0) {
        close(fd);
        return "";
    }

    const off_t offset = st.st_size > static_cast<off_t>(maxBytes) ? st.st_size - static_cast<off_t>(maxBytes) : 0;
    const size_t length = static_cast<size_t>(st.st_size - offset);
    std::vector<char> buffer(length);
    const ssize_t n = pread(fd, buffer.data(), buffer.size(), offset);
    close(fd);
    if (n <= 0) {
        return "";
    }
    return std::string(buffer.data(), static_cast<size_t>(n));
}

std::string ReadFileHead(const std::string &path, size_t maxBytes)
{
    const int fd = open(path.c_str(), O_RDONLY);
    if (fd < 0) {
        return "";
    }

    std::vector<char> buffer(maxBytes);
    const ssize_t n = read(fd, buffer.data(), buffer.size());
    close(fd);
    if (n <= 0) {
        return "";
    }
    return std::string(buffer.data(), static_cast<size_t>(n));
}

std::string CompactLogText(const std::string &text, size_t maxChars)
{
    std::string compact;
    compact.reserve(std::min(text.size(), maxChars));
    bool inSpace = false;
    for (char ch : text) {
        const bool space = ch == '\r' || ch == '\n' || ch == '\t';
        if (space) {
            if (!inSpace && !compact.empty()) {
                compact += " | ";
            }
            inSpace = true;
        } else {
            compact.push_back(ch);
            inSpace = false;
        }
        if (compact.size() >= maxChars) {
            compact += "...";
            break;
        }
    }
    return compact;
}

bool ContainsAnyLogKeyword(const std::string &line)
{
    static const char *keywords[] = {
        "MAP_FIXED",
        "private file fallback",
        "map_image",
        "loaddll",
        "SIGSEGV",
        "Unhandled signal",
        "RtlCreateHeap",
        "RtlExitUserProcess",
        "Could not allocate",
        "Could not commit",
        "warn:heap",
        "err:heap",
        "NtAllocateVirtualMemory",
        "trace:heap",
        "trace:virtual",
        "Allocation failed",
        "out of memory",
        "mmap error",
        "map_view",
        "alloc_free_area",
        "try_map_free_area",
        "create_view",
        "SIGSYS",
        "sigaction",
        "Sigaction",
        "HMOS sigaction",
        "HMOS rt_sigaction",
        "exception",
        "Exception",
        "failed",
        "Failed",
        "not found",
        "No such file",
        "cannot",
        "x11drv",
        "X11",
        "DISPLAY",
        "display",
        "driver",
        "CreateWindow",
        "create_window",
        "RegisterClass",
        "WineChildMain",
        "native wineserver",
        "wineserver",
        "server socket",
        "WINESERVERSOCKET",
        "WineFile",
        "winefile",
        "ExplorerWClass",
        "WFS_Frame",
        "MDICLIENT",
        "CabinetWClass",
        "Progman",
        "WorkerW",
        "Shell_TrayWnd",
        "HMOS exported",
        "HMOS skipping child/small",
        "HMOS process broker",
        "HMOS in-process",
        "CreateProcessW",
        "NtCreateUserProcess",
        "ShowWindow",
        "SetWindow",
        "WM_CREATE",
        "WM_PAINT",
        "BeginPaint",
        "EndPaint",
        "libX",
        "xcb",
        "wayland",
        "vulkan",
        "freetype",
        "wine:",
        "fixme:",
        "err:"
    };
    for (const char *keyword : keywords) {
        if (line.find(keyword) != std::string::npos) {
            return true;
        }
    }
    return false;
}

std::string ExtractLaunchHighlights(const std::string &text, size_t maxChars)
{
    std::string highlights;
    size_t cursor = 0;
    while (cursor <= text.size()) {
        const size_t lineEnd = text.find('\n', cursor);
        const size_t end = lineEnd == std::string::npos ? text.size() : lineEnd;
        const std::string line = text.substr(cursor, end - cursor);
        if (ContainsAnyLogKeyword(line)) {
            if (!highlights.empty()) {
                highlights += '\n';
            }
            highlights += line;
            if (highlights.size() >= maxChars) {
                highlights += "\n...";
                break;
            }
        }
        if (lineEnd == std::string::npos) {
            break;
        }
        cursor = lineEnd + 1;
    }
    return highlights;
}

std::string BuildSiblingPath(const std::string &path, const std::string &leaf)
{
    if (path.empty()) {
        return "";
    }
    const size_t pos = path.find_last_of('/');
    if (pos == std::string::npos) {
        return leaf;
    }
    return path.substr(0, pos + 1) + leaf;
}

std::string BuildDriveCPath(const std::string &path, const std::string &leaf)
{
    const std::string marker = "/dosdevices/c:";
    const size_t pos = path.find(marker);
    if (pos == std::string::npos) {
        return "";
    }
    return path.substr(0, pos + marker.size()) + "/" + leaf;
}

bool AttachLaunchMarkerPath(const std::string &markerPath)
{
    if (markerPath.empty()) {
        return false;
    }
    const std::string marker = ReadFileTail(markerPath, 65536);
    if (marker.empty()) {
        return false;
    }

    const std::string compact = CompactLogText(marker, 24000);
    constexpr size_t LOG_CHUNK_SIZE = 1500;
    const size_t totalParts = (compact.size() + LOG_CHUNK_SIZE - 1) / LOG_CHUNK_SIZE;
    for (size_t offset = 0, part = 1; offset < compact.size(); offset += LOG_CHUNK_SIZE, part++) {
        const std::string chunk = compact.substr(offset, LOG_CHUNK_SIZE);
        OH_LOG_ERROR(LOG_APP,
            "launch marker path=%{public}s part=%{public}zu/%{public}zu text=%{public}s",
            markerPath.c_str(), part, totalParts, chunk.c_str());
    }
    return true;
}

void AttachLaunchMarker(const std::string &logPath)
{
    if (AttachLaunchMarkerPath(BuildSiblingPath(logPath, "tinygame-entry.txt"))) {
        return;
    }
    AttachLaunchMarkerPath(BuildDriveCPath(logPath, "tinygame-entry.txt"));
}

void AttachLaunchOutput(LaunchChildResult &result, const std::string &logPath)
{
    if (logPath.empty()) {
        return;
    }
    const std::string tail = ReadFileTail(logPath, 1048576);
    if (tail.empty()) {
        return;
    }
    const std::string head = ReadFileHead(logPath, 262144);
    const std::string highlightSource = head.empty() ? tail : head + "\n" + tail;
    const std::string highlights = CompactLogText(ExtractLaunchHighlights(highlightSource, 96000), 96000);
    if (!highlights.empty()) {
        constexpr size_t LOG_CHUNK_SIZE = 1500;
        const size_t totalParts = (highlights.size() + LOG_CHUNK_SIZE - 1) / LOG_CHUNK_SIZE;
        for (size_t offset = 0, part = 1; offset < highlights.size(); offset += LOG_CHUNK_SIZE, part++) {
            const std::string chunk = highlights.substr(offset, LOG_CHUNK_SIZE);
            OH_LOG_ERROR(LOG_APP,
                "launch output highlights path=%{public}s part=%{public}zu/%{public}zu text=%{public}s",
                logPath.c_str(), part, totalParts, chunk.c_str());
        }
    }
    const std::string compact = CompactLogText(tail, 96000);
    constexpr size_t LOG_CHUNK_SIZE = 1500;
    const size_t totalParts = (compact.size() + LOG_CHUNK_SIZE - 1) / LOG_CHUNK_SIZE;
    for (size_t offset = 0, part = 1; offset < compact.size(); offset += LOG_CHUNK_SIZE, part++) {
        const std::string chunk = compact.substr(offset, LOG_CHUNK_SIZE);
        OH_LOG_ERROR(LOG_APP,
            "launch output tail path=%{public}s part=%{public}zu/%{public}zu text=%{public}s",
            logPath.c_str(), part, totalParts, chunk.c_str());
    }
    if (result.status != "started") {
        result.reason += ": " + CompactLogText(tail, 512);
    }
    AttachLaunchMarker(logPath);
}

void LogLaunchOutputSnapshot(const std::string &logPath, const char *label)
{
    if (logPath.empty()) {
        return;
    }
    const std::string tail = ReadFileTail(logPath, 1048576);
    if (tail.empty()) {
        OH_LOG_WARN(LOG_APP, "launch output delayed[%{public}s] empty path=%{public}s", label, logPath.c_str());
        return;
    }
    const std::string highlights = CompactLogText(ExtractLaunchHighlights(tail, 72000), 72000);
    const std::string compact = highlights.empty() ? CompactLogText(tail, 72000) : highlights;
    constexpr size_t LOG_CHUNK_SIZE = 1500;
    const size_t totalParts = (compact.size() + LOG_CHUNK_SIZE - 1) / LOG_CHUNK_SIZE;
    for (size_t offset = 0, part = 1; offset < compact.size(); offset += LOG_CHUNK_SIZE, part++) {
        const std::string chunk = compact.substr(offset, LOG_CHUNK_SIZE);
        OH_LOG_ERROR(LOG_APP,
            "launch output delayed[%{public}s] path=%{public}s part=%{public}zu/%{public}zu text=%{public}s",
            label, logPath.c_str(), part, totalParts, chunk.c_str());
    }
}

void ScheduleLaunchOutputSnapshots(const std::string &logPath)
{
    if (logPath.empty()) {
        return;
    }
    std::thread([logPath]() {
        sleep(8);
        LogLaunchOutputSnapshot(logPath, "8s");
        sleep(12);
        LogLaunchOutputSnapshot(logPath, "20s");
    }).detach();
}

template<typename LaunchFn>
LaunchChildResult LaunchInChildProcess(LaunchFn launch, const std::string &commandLine)
{
    const std::string logPath = BuildLaunchLogPath(commandLine);
    if (!logPath.empty()) {
        unlink(logPath.c_str());
        const std::string markerPath = BuildSiblingPath(logPath, "tinygame-entry.txt");
        if (!markerPath.empty()) {
            unlink(markerPath.c_str());
        }
        const std::string driveMarkerPath = BuildDriveCPath(logPath, "tinygame-entry.txt");
        if (!driveMarkerPath.empty()) {
            unlink(driveMarkerPath.c_str());
        }
    }

    const pid_t child = fork();
    if (child < 0) {
        const int code = errno;
        return { "runtime-error", std::string("fork isolation failed: ") + strerror(code), code, true };
    }
    if (child == 0) {
        if (!logPath.empty()) {
            const int logFd = open(logPath.c_str(), O_CREAT | O_WRONLY | O_TRUNC, 0644);
            if (logFd >= 0) {
                dup2(logFd, STDOUT_FILENO);
                dup2(logFd, STDERR_FILENO);
                if (logFd > STDERR_FILENO) {
                    close(logFd);
                }
                setvbuf(stdout, nullptr, _IONBF, 0);
                setvbuf(stderr, nullptr, _IONBF, 0);
            }
        }
        const int code = launch(commandLine.c_str());
        _exit(NormalizeExitCode(code));
    }

    // Give smoke-test launches time to fail without blocking a real game session forever.
    constexpr int WAIT_ATTEMPTS = 30;
    constexpr useconds_t WAIT_INTERVAL_US = 100000;
    for (int attempt = 0; attempt < WAIT_ATTEMPTS; attempt++) {
        int status = 0;
        const pid_t waited = waitpid(child, &status, WNOHANG);
        if (waited == child) {
            LaunchChildResult result = ResultFromWaitStatus(status);
            AttachLaunchOutput(result, logPath);
            return result;
        }
        if (waited < 0) {
            const int code = errno;
            if (code == EINTR) {
                continue;
            }
            return { "runtime-error", std::string("waitpid failed: ") + strerror(code), code, true };
        }
        usleep(WAIT_INTERVAL_US);
    }

    LaunchChildResult result = {
        "started",
        std::string("proton runtime child still running pid=") + std::to_string(static_cast<int>(child)),
        0,
        false
    };
    AttachLaunchOutput(result, logPath);
    ScheduleLaunchOutputSnapshots(logPath);
    return result;
}

bool ProbeLibrary(const char *library, std::string &error)
{
    dlerror();
    void *handle = dlopen(library, RTLD_NOW | RTLD_LOCAL);
    if (handle == nullptr) {
        error = LastDlError();
        return false;
    }
    dlclose(handle);
    return true;
}

uint16_t ReadLe16(const uint8_t *data)
{
    return static_cast<uint16_t>(data[0]) | (static_cast<uint16_t>(data[1]) << 8);
}

bool ReadFullyAt(int fd, uint64_t offset, uint8_t *buffer, size_t length)
{
    size_t done = 0;
    while (done < length) {
        const ssize_t n = pread(fd, buffer + done, length - done, static_cast<off_t>(offset + done));
        if (n <= 0) {
            return false;
        }
        done += static_cast<size_t>(n);
    }
    return true;
}

bool WriteFully(int fd, const uint8_t *buffer, size_t length)
{
    size_t done = 0;
    while (done < length) {
        const ssize_t n = write(fd, buffer + done, length - done);
        if (n <= 0) {
            return false;
        }
        done += static_cast<size_t>(n);
    }
    return true;
}

bool FileExistsWithSize(const std::string &path, uint64_t size)
{
    struct stat st = {};
    if (stat(path.c_str(), &st) != 0) {
        return false;
    }
    return static_cast<uint64_t>(st.st_size) == size;
}

bool IsDirectory(const std::string &path)
{
    struct stat st = {};
    return stat(path.c_str(), &st) == 0 && S_ISDIR(st.st_mode);
}

std::string ParentPath(const std::string &path)
{
    const size_t pos = path.find_last_of('/');
    if (pos == std::string::npos || pos == 0) {
        return "/";
    }
    return path.substr(0, pos);
}

bool EnsureDir(const std::string &path)
{
    if (path.empty() || path == "/") {
        return true;
    }
    struct stat st = {};
    if (stat(path.c_str(), &st) == 0) {
        return S_ISDIR(st.st_mode);
    }
    if (!EnsureDir(ParentPath(path))) {
        return false;
    }
    if (mkdir(path.c_str(), 0755) == 0 || errno == EEXIST) {
        return true;
    }
    return false;
}

bool StartsWith(const std::string &value, const std::string &prefix)
{
    return value.size() >= prefix.size() && value.compare(0, prefix.size(), prefix) == 0;
}

bool ShouldSkipRuntimeZipRelativePath(const std::string &relative)
{
    if (relative.empty() || relative.find("..") != std::string::npos || relative[0] == '/') {
        return true;
    }
    const size_t leafPos = relative.find_last_of('/');
    const std::string leaf = leafPos == std::string::npos ? relative : relative.substr(leafPos + 1);
    if (leaf.empty() || leaf[0] == '.' || leaf == "proton_rawfile_index.json" ||
        leaf == ".proton-rawfile-index.json" || leaf == ".gitkeep" || leaf == "PROTON_PLACEHOLDER.txt") {
        return true;
    }
    return StartsWith(relative, "files/share/wine/mono/") || StartsWith(relative, "files/share/wine/gecko/");
}

struct ZipEntry {
    std::string name;
    uint16_t method;
    uint32_t compressedSize;
    uint32_t uncompressedSize;
    uint32_t localHeaderOffset;
};

bool LoadZipCentralDirectory(int fd, std::vector<ZipEntry> &entries, std::string &error)
{
    struct stat st = {};
    if (fstat(fd, &st) != 0) {
        error = std::string("fstat failed: ") + strerror(errno);
        return false;
    }
    const uint64_t zipSize = static_cast<uint64_t>(st.st_size);
    const uint64_t tailSize = zipSize < 66000 ? zipSize : 66000;
    std::vector<uint8_t> tail(static_cast<size_t>(tailSize));
    if (!ReadFullyAt(fd, zipSize - tailSize, tail.data(), tail.size())) {
        error = "read zip tail failed";
        return false;
    }

    int64_t eocd = -1;
    for (int64_t i = static_cast<int64_t>(tail.size()) - 22; i >= 0; i--) {
        if (ReadLe32(tail.data() + i) == 0x06054b50u) {
            eocd = i;
            break;
        }
    }
    if (eocd < 0) {
        error = "zip end-of-central-directory not found";
        return false;
    }

    const uint8_t *record = tail.data() + eocd;
    const uint16_t totalEntries = ReadLe16(record + 10);
    const uint32_t centralSize = ReadLe32(record + 12);
    const uint32_t centralOffset = ReadLe32(record + 16);
    if (totalEntries == 0xffffu || centralSize == 0xffffffffu || centralOffset == 0xffffffffu) {
        error = "zip64 HSP is not supported by the stored rawfile extractor yet";
        return false;
    }
    if (static_cast<uint64_t>(centralOffset) + centralSize > zipSize) {
        error = "zip central directory is outside file bounds";
        return false;
    }

    std::vector<uint8_t> central(centralSize);
    if (!ReadFullyAt(fd, centralOffset, central.data(), central.size())) {
        error = "read zip central directory failed";
        return false;
    }

    size_t cursor = 0;
    entries.reserve(totalEntries);
    for (uint16_t i = 0; i < totalEntries; i++) {
        if (cursor + 46 > central.size() || ReadLe32(central.data() + cursor) != 0x02014b50u) {
            error = "invalid zip central directory entry";
            return false;
        }
        const uint16_t method = ReadLe16(central.data() + cursor + 10);
        const uint32_t compressedSize = ReadLe32(central.data() + cursor + 20);
        const uint32_t uncompressedSize = ReadLe32(central.data() + cursor + 24);
        const uint16_t nameLen = ReadLe16(central.data() + cursor + 28);
        const uint16_t extraLen = ReadLe16(central.data() + cursor + 30);
        const uint16_t commentLen = ReadLe16(central.data() + cursor + 32);
        const uint32_t localHeaderOffset = ReadLe32(central.data() + cursor + 42);
        const size_t next = cursor + 46 + nameLen + extraLen + commentLen;
        if (next > central.size()) {
            error = "truncated zip central directory entry";
            return false;
        }
        std::string name(reinterpret_cast<const char *>(central.data() + cursor + 46), nameLen);
        entries.push_back({ name, method, compressedSize, uncompressedSize, localHeaderOffset });
        cursor = next;
    }
    return true;
}

bool CopyStoredZipEntry(int zipFd, const ZipEntry &entry, const std::string &targetPath, std::string &error)
{
    uint8_t header[30] = {};
    if (!ReadFullyAt(zipFd, entry.localHeaderOffset, header, sizeof(header)) || ReadLe32(header) != 0x04034b50u) {
        error = "invalid local zip header: " + entry.name;
        return false;
    }
    const uint16_t nameLen = ReadLe16(header + 26);
    const uint16_t extraLen = ReadLe16(header + 28);
    const uint64_t dataOffset = static_cast<uint64_t>(entry.localHeaderOffset) + 30 + nameLen + extraLen;

    if (!EnsureDir(ParentPath(targetPath))) {
        error = std::string("mkdir failed for ") + ParentPath(targetPath) + ": " + strerror(errno);
        return false;
    }

    const int outFd = open(targetPath.c_str(), O_CREAT | O_WRONLY | O_TRUNC, 0644);
    if (outFd < 0) {
        error = std::string("open output failed: ") + targetPath + ": " + strerror(errno);
        return false;
    }

    std::vector<uint8_t> buffer(1024 * 1024);
    uint64_t copied = 0;
    bool ok = true;
    while (copied < entry.uncompressedSize) {
        const size_t chunk = static_cast<size_t>(std::min<uint64_t>(buffer.size(), entry.uncompressedSize - copied));
        if (!ReadFullyAt(zipFd, dataOffset + copied, buffer.data(), chunk) || !WriteFully(outFd, buffer.data(), chunk)) {
            ok = false;
            break;
        }
        copied += chunk;
    }
    const int savedErrno = errno;
    close(outFd);
    if (!ok) {
        unlink(targetPath.c_str());
        error = std::string("copy stored zip entry failed: ") + entry.name + ": " + strerror(savedErrno);
        return false;
    }
    return true;
}

bool CopyRegularFile(const std::string &sourcePath, const std::string &targetPath, uint64_t size, std::string &error)
{
    if (!EnsureDir(ParentPath(targetPath))) {
        error = std::string("mkdir failed for ") + ParentPath(targetPath) + ": " + strerror(errno);
        return false;
    }
    const int inFd = open(sourcePath.c_str(), O_RDONLY);
    if (inFd < 0) {
        error = std::string("open input failed: ") + sourcePath + ": " + strerror(errno);
        return false;
    }
    const int outFd = open(targetPath.c_str(), O_CREAT | O_WRONLY | O_TRUNC, 0644);
    if (outFd < 0) {
        error = std::string("open output failed: ") + targetPath + ": " + strerror(errno);
        close(inFd);
        return false;
    }
    std::vector<uint8_t> buffer(1024 * 1024);
    uint64_t copied = 0;
    bool ok = true;
    while (copied < size) {
        const size_t chunk = static_cast<size_t>(std::min<uint64_t>(buffer.size(), size - copied));
        const ssize_t n = read(inFd, buffer.data(), chunk);
        if (n <= 0 || !WriteFully(outFd, buffer.data(), static_cast<size_t>(n))) {
            ok = false;
            break;
        }
        copied += static_cast<uint64_t>(n);
    }
    const int savedErrno = errno;
    close(inFd);
    close(outFd);
    if (!ok || copied != size) {
        unlink(targetPath.c_str());
        error = std::string("copy regular file failed: ") + sourcePath + ": " + strerror(savedErrno);
        return false;
    }
    return true;
}

std::string JoinPath(const std::string &left, const std::string &right)
{
    if (left.empty() || left[left.size() - 1] == '/') {
        return left + right;
    }
    return left + "/" + right;
}

struct StageCounters {
    int32_t fileCount = 0;
    int32_t copiedCount = 0;
    int32_t skippedCount = 0;
    uint64_t totalBytes = 0;
};

bool StageDirectoryRecursive(const std::string &sourceRoot, const std::string &relativeDir, const std::string &targetRoot,
    StageCounters &counters, std::string &error)
{
    const std::string sourceDir = relativeDir.empty() ? sourceRoot : JoinPath(sourceRoot, relativeDir);
    DIR *dir = opendir(sourceDir.c_str());
    if (dir == nullptr) {
        error = std::string("opendir failed: ") + sourceDir + ": " + strerror(errno);
        return false;
    }
    while (true) {
        errno = 0;
        dirent *entry = readdir(dir);
        if (entry == nullptr) {
            break;
        }
        const std::string name = entry->d_name;
        if (name == "." || name == "..") {
            continue;
        }
        const std::string relative = relativeDir.empty() ? name : JoinPath(relativeDir, name);
        const std::string sourcePath = JoinPath(sourceRoot, relative);
        struct stat st = {};
        if (stat(sourcePath.c_str(), &st) != 0) {
            error = std::string("stat failed: ") + sourcePath + ": " + strerror(errno);
            closedir(dir);
            return false;
        }
        if (S_ISDIR(st.st_mode)) {
            if (!StageDirectoryRecursive(sourceRoot, relative, targetRoot, counters, error)) {
                closedir(dir);
                return false;
            }
            continue;
        }
        if (!S_ISREG(st.st_mode) || ShouldSkipRuntimeZipRelativePath(relative)) {
            continue;
        }
        counters.fileCount++;
        counters.totalBytes += static_cast<uint64_t>(st.st_size);
        const std::string targetPath = JoinPath(targetRoot, relative);
        if (FileExistsWithSize(targetPath, static_cast<uint64_t>(st.st_size))) {
            counters.skippedCount++;
            continue;
        }
        if (!CopyRegularFile(sourcePath, targetPath, static_cast<uint64_t>(st.st_size), error)) {
            closedir(dir);
            return false;
        }
        counters.copiedCount++;
    }
    if (errno != 0) {
        error = std::string("readdir failed: ") + sourceDir + ": " + strerror(errno);
        closedir(dir);
        return false;
    }
    closedir(dir);
    return true;
}

std::string ProbeProcessModel(const char *library, const char *symbol)
{
    if (symbol == nullptr || symbol[0] == '\0') {
        return "";
    }
    dlerror();
    void *handle = dlopen(library, RTLD_NOW | RTLD_LOCAL);
    if (handle == nullptr) {
        return "";
    }

    using ProcessModelFn = const char *(*)();
    dlerror();
    auto processModel = reinterpret_cast<ProcessModelFn>(dlsym(handle, symbol));
    const char *value = processModel == nullptr ? nullptr : processModel();
    std::string result = value == nullptr ? "" : value;
    dlclose(handle);
    return result;
}

bool AddRuntimeComponents(napi_env env, napi_value object)
{
    napi_value items = nullptr;
    napi_create_array_with_length(env, sizeof(RUNTIME_COMPONENTS) / sizeof(RUNTIME_COMPONENTS[0]), &items);

    bool allReady = true;
    for (size_t i = 0; i < sizeof(RUNTIME_COMPONENTS) / sizeof(RUNTIME_COMPONENTS[0]); i++) {
        std::string error;
        const bool available = ProbeLibrary(RUNTIME_COMPONENTS[i].library, error);
        allReady = allReady && available;

        napi_value item = nullptr;
        napi_create_object(env, &item);
        SetNamed(env, item, "name", CreateString(env, RUNTIME_COMPONENTS[i].name));
        SetNamed(env, item, "library", CreateString(env, RUNTIME_COMPONENTS[i].library));
        SetNamed(env, item, "available", CreateBool(env, available));
        SetNamed(env, item, "error", CreateString(env, available ? "" : error));
        SetNamed(env, item, "processModel", CreateString(env, available ? ProbeProcessModel(RUNTIME_COMPONENTS[i].library,
            RUNTIME_COMPONENTS[i].processModelSymbol) : ""));
        napi_set_element(env, items, static_cast<uint32_t>(i), item);
    }

    SetNamed(env, object, "runtimeReady", CreateBool(env, allReady));
    SetNamed(env, object, "runtimeComponents", items);
    return allReady;
}

std::string AbiName()
{
#if defined(__aarch64__)
    return "arm64-v8a";
#elif defined(__x86_64__)
    return "x86_64";
#else
    return "unknown";
#endif
}

napi_value ProbeRuntime(napi_env env, napi_callback_info info)
{
    (void)info;
    napi_value result = nullptr;
    napi_create_object(env, &result);

    uint32_t vulkanVersion = 0;
    VkResult vkResult = vkEnumerateInstanceVersion(&vulkanVersion);

    SetNamed(env, result, "nativeModule", CreateString(env, "libproton.so"));
    SetNamed(env, result, "abi", CreateString(env, AbiName()));
    SetNamed(env, result, "vulkanLinked", CreateBool(env, true));
    SetNamed(env, result, "vulkanProbeResult", CreateInt(env, static_cast<int32_t>(vkResult)));
    SetNamed(env, result, "vulkanApiVersion", CreateInt(env, static_cast<int32_t>(vulkanVersion)));
    const bool runtimeReady = AddRuntimeComponents(env, result);
    SetNamed(env, result, "stage", CreateString(env, runtimeReady ? "runtime-native-inprocess-ready" : "runtime-native-missing-payload"));

    OH_LOG_INFO(LOG_APP, "runtime probe abi=%{public}s vk=%{public}d runtime=%{public}d", AbiName().c_str(), vkResult,
        runtimeReady);
    return result;
}

napi_value MountSurface(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    std::string surfaceId = "";
    if (argc > 0) {
        surfaceId = ReadStringArg(env, args[0]);
    }

    XComponentSurfaceRecord snapshot;
    bool found = false;
    if (!surfaceId.empty()) {
        std::lock_guard<std::mutex> lock(g_surfaceMutex);
        auto it = g_surfaceRecords.find(surfaceId);
        if (it != g_surfaceRecords.end()) {
            snapshot = it->second;
            found = true;
        }
    }

    std::string message;
    if (surfaceId.empty()) {
        message = "missing XComponent id";
    } else if (!found) {
        message = "native XComponent is not registered for this id yet";
    } else if (!snapshot.surfaceReady || snapshot.window == nullptr) {
        message = "registered, waiting for native surface callback";
    } else {
        message = std::string("native window ready ") + std::to_string(snapshot.width) + "x" +
            std::to_string(snapshot.height) + " window=" + HexPointer(snapshot.window);
    }

    napi_value result = nullptr;
    napi_create_object(env, &result);
    SetNamed(env, result, "success", CreateBool(env, found && snapshot.surfaceReady && snapshot.window != nullptr));
    SetNamed(env, result, "xcomponentId", CreateString(env, surfaceId));
    SetNamed(env, result, "renderer", CreateString(env, "xcomponent-native-window"));
    SetNamed(env, result, "message", CreateString(env, message));
    SetNamed(env, result, "windowHandle", CreateString(env, snapshot.window == nullptr ? "" : HexPointer(snapshot.window)));
    SetNamed(env, result, "width", CreateNumber(env, static_cast<double>(snapshot.width)));
    SetNamed(env, result, "height", CreateNumber(env, static_cast<double>(snapshot.height)));
    SetNamed(env, result, "generation", CreateUint64AsNumber(env, snapshot.generation));
    SetNamed(env, result, "nativeWindowConfigured", CreateBool(env, snapshot.nativeWindowConfigured));
    return result;
}

napi_value QueryGraphicsCapabilities(napi_env env, napi_callback_info info)
{
    (void)info;
    uint32_t vulkanVersion = 0;
    VkResult versionResult = vkEnumerateInstanceVersion(&vulkanVersion);
    VkResult extensionResult = VK_SUCCESS;
    const std::vector<std::string> instanceExtensions = EnumerateVulkanInstanceExtensions(extensionResult);
    const bool hasKhrSurface = HasString(instanceExtensions, VK_KHR_SURFACE_EXTENSION_NAME);
    const bool hasOhosSurface = HasString(instanceExtensions, VK_OHOS_SURFACE_EXTENSION_NAME);
    VulkanDeviceProbe deviceProbe = ProbeVulkanDevices(instanceExtensions);

    napi_value result = nullptr;
    napi_create_object(env, &result);
    SetNamed(env, result, "nativeModule", CreateString(env, "libproton.so"));
    SetNamed(env, result, "abi", CreateString(env, AbiName()));
    SetNamed(env, result, "nativeWindow", CreateBool(env, true));
    SetNamed(env, result, "cpuPresent", CreateBool(env, true));
    SetNamed(env, result, "vulkanLinked", CreateBool(env, true));
    SetNamed(env, result, "vulkanProbeResult", CreateInt(env, static_cast<int32_t>(versionResult)));
    SetNamed(env, result, "vulkanApiVersion", CreateInt(env, static_cast<int32_t>(vulkanVersion)));
    SetNamed(env, result, "instanceExtensionResult", CreateInt(env, static_cast<int32_t>(extensionResult)));
    SetNamed(env, result, "instanceExtensions", CreateStringArray(env, instanceExtensions));
    SetNamed(env, result, "hasKhrSurface", CreateBool(env, hasKhrSurface));
    SetNamed(env, result, "hasOhosSurface", CreateBool(env, hasOhosSurface));
    SetNamed(env, result, "hasArkUiVulkanSurface", CreateBool(env, hasKhrSurface && hasOhosSurface));
    SetNamed(env, result, "instanceCreateResult", CreateInt(env, static_cast<int32_t>(deviceProbe.instanceResult)));
    SetNamed(env, result, "physicalDeviceResult", CreateInt(env, static_cast<int32_t>(deviceProbe.physicalDeviceResult)));
    SetNamed(env, result, "physicalDeviceCount", CreateInt(env, static_cast<int32_t>(deviceProbe.physicalDeviceCount)));
    SetNamed(env, result, "swapchainDeviceCount", CreateInt(env, static_cast<int32_t>(deviceProbe.swapchainDeviceCount)));
    SetNamed(env, result, "hasSwapchain", CreateBool(env, deviceProbe.swapchainDeviceCount > 0));
    SetNamed(env, result, "presentBackend", CreateString(env,
        hasKhrSurface && hasOhosSurface && deviceProbe.swapchainDeviceCount > 0 ?
        "VK_OHOS_surface" : "native-window-cpu"));
    OH_LOG_INFO(LOG_APP,
        "graphics capabilities vkResult=%{public}d api=%{public}u khrSurface=%{public}d ohosSurface=%{public}d physicalDevices=%{public}u swapchainDevices=%{public}u",
        versionResult, vulkanVersion, hasKhrSurface ? 1 : 0, hasOhosSurface ? 1 : 0,
        deviceProbe.physicalDeviceCount, deviceProbe.swapchainDeviceCount);
    return result;
}

napi_value QuerySurfaceState(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    const std::string surfaceId = argc > 0 ? ReadStringArg(env, args[0]) : "";
    XComponentSurfaceRecord snapshot;
    bool found = false;
    if (!surfaceId.empty()) {
        std::lock_guard<std::mutex> lock(g_surfaceMutex);
        auto it = g_surfaceRecords.find(surfaceId);
        if (it != g_surfaceRecords.end()) {
            snapshot = it->second;
            found = true;
        }
    }

    napi_value result = nullptr;
    napi_create_object(env, &result);
    SetNamed(env, result, "success", CreateBool(env, found));
    SetNamed(env, result, "xcomponentId", CreateString(env, surfaceId));
    SetNamed(env, result, "renderer", CreateString(env, "wineonarkui-native-compositor"));
    SetNamed(env, result, "surfaceReady", CreateBool(env, found && snapshot.surfaceReady && snapshot.window != nullptr));
    SetNamed(env, result, "windowHandle", CreateString(env, snapshot.window == nullptr ? "" : HexPointer(snapshot.window)));
    SetNamed(env, result, "width", CreateNumber(env, static_cast<double>(snapshot.width)));
    SetNamed(env, result, "height", CreateNumber(env, static_cast<double>(snapshot.height)));
    SetNamed(env, result, "offsetX", CreateNumber(env, snapshot.offsetX));
    SetNamed(env, result, "offsetY", CreateNumber(env, snapshot.offsetY));
    SetNamed(env, result, "generation", CreateUint64AsNumber(env, snapshot.generation));
    SetNamed(env, result, "destroyCount", CreateUint64AsNumber(env, snapshot.destroyCount));
    SetNamed(env, result, "nativeWindowConfigured", CreateBool(env, snapshot.nativeWindowConfigured));
    SetNamed(env, result, "frameWidth", CreateInt(env, static_cast<int32_t>(snapshot.frameWidth)));
    SetNamed(env, result, "frameHeight", CreateInt(env, static_cast<int32_t>(snapshot.frameHeight)));
    SetNamed(env, result, "inputSequence", CreateUint64AsNumber(env, snapshot.inputSeq));
    SetNamed(env, result, "presentCount", CreateUint64AsNumber(env, snapshot.presentCount));
    SetNamed(env, result, "presentFailCount", CreateUint64AsNumber(env, snapshot.presentFailCount));
    SetNamed(env, result, "lastPresentMs", CreateNumber(env, static_cast<double>(snapshot.lastPresentMs)));
    SetNamed(env, result, "lastPresentSource", CreateString(env, snapshot.lastPresentSource));
    SetNamed(env, result, "lastPresentMessage", CreateString(env, snapshot.lastPresentMessage));
    SetNamed(env, result, "lastPresentWidth", CreateInt(env, static_cast<int32_t>(snapshot.lastPresentWidth)));
    SetNamed(env, result, "lastPresentHeight", CreateInt(env, static_cast<int32_t>(snapshot.lastPresentHeight)));
    SetNamed(env, result, "lastPresentFrame", CreateUint64AsNumber(env, snapshot.lastPresentFrame));
    return result;
}

napi_value ReportWinePresent(napi_env env, napi_callback_info info)
{
    size_t argc = 7;
    napi_value args[7] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    const std::string surfaceId = argc > 0 ? ReadStringArg(env, args[0]) : "";
    const std::string source = argc > 1 ? ReadStringArg(env, args[1]) : "wine";
    const bool success = argc > 2 ? ReadIntArg(env, args[2]) != 0 : true;
    const int32_t width = argc > 3 ? ReadIntArg(env, args[3]) : 0;
    const int32_t height = argc > 4 ? ReadIntArg(env, args[4]) : 0;
    const uint64_t frameNumber = argc > 5 ? static_cast<uint64_t>(ReadInt64Arg(env, args[5])) : 0;
    const std::string message = argc > 6 ? ReadStringArg(env, args[6]) : "";
    RecordSurfacePresent(surfaceId, success, source.c_str(), width, height, frameNumber, message);

    napi_value result = nullptr;
    napi_create_object(env, &result);
    SetNamed(env, result, "success", CreateBool(env, !surfaceId.empty()));
    SetNamed(env, result, "xcomponentId", CreateString(env, surfaceId));
    SetNamed(env, result, "message", CreateString(env, message));
    return result;
}

napi_value ClearSurfaceFrameCache(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    const std::string surfaceId = argc > 0 ? ReadStringArg(env, args[0]) : "";
    size_t removed = 0;
    {
        std::lock_guard<std::mutex> lock(g_surfaceMutex);
        if (surfaceId.empty()) {
            removed = g_lastSurfaceFrames.size();
            g_lastSurfaceFrames.clear();
        } else {
            removed = g_lastSurfaceFrames.erase(surfaceId);
            auto it = g_surfaceRecords.find(surfaceId);
            if (it != g_surfaceRecords.end()) {
                it->second.frameWidth = 0;
                it->second.frameHeight = 0;
            }
        }
    }

    OH_LOG_INFO(LOG_APP, "xcomponent frame cache cleared id=%{public}s removed=%{public}zu",
        surfaceId.c_str(), removed);

    napi_value result = nullptr;
    napi_create_object(env, &result);
    SetNamed(env, result, "success", CreateBool(env, true));
    SetNamed(env, result, "xcomponentId", CreateString(env, surfaceId));
    SetNamed(env, result, "removed", CreateNumber(env, static_cast<double>(removed)));
    return result;
}

napi_value RenderSurfaceFrame(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = { nullptr, nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    const std::string surfaceId = argc > 0 ? ReadStringArg(env, args[0]) : "";
    const std::string framePath = argc > 1 ? ReadStringArg(env, args[1]) : "";

    XComponentSurfaceRecord snapshot;
    bool found = false;
    if (!surfaceId.empty()) {
        std::lock_guard<std::mutex> lock(g_surfaceMutex);
        auto it = g_surfaceRecords.find(surfaceId);
        if (it != g_surfaceRecords.end()) {
            snapshot = it->second;
            it->second.renderCount++;
            snapshot.renderCount = it->second.renderCount;
            found = true;
        }
    }

    napi_value result = nullptr;
    napi_create_object(env, &result);
    SetNamed(env, result, "xcomponentId", CreateString(env, surfaceId));
    SetNamed(env, result, "framePath", CreateString(env, framePath));

    if (surfaceId.empty() || !found || !snapshot.surfaceReady || snapshot.window == nullptr) {
        SetNamed(env, result, "success", CreateBool(env, false));
        SetNamed(env, result, "source", CreateString(env, "none"));
        SetNamed(env, result, "message", CreateString(env, surfaceId.empty() ? "missing XComponent id" :
            (!found ? "XComponent not registered" : "native surface not ready")));
        SetNamed(env, result, "inputSequence", CreateNumber(env, static_cast<double>(snapshot.inputSeq)));
        return result;
    }

    HmosFrame frame;
    HmosFrame header;
    bool hasCachedFrame = false;
    const bool hasFreshHeader = LoadHmosFrameHeader(framePath, header);
    if (hasFreshHeader) {
        std::lock_guard<std::mutex> lock(g_surfaceMutex);
        auto cached = g_lastSurfaceFrames.find(surfaceId);
        if (cached != g_lastSurfaceFrames.end() && cached->second.valid &&
            cached->second.frameNumber == header.frameNumber &&
            cached->second.width == header.width &&
            cached->second.height == header.height &&
            cached->second.stride == header.stride) {
            frame = cached->second;
            hasCachedFrame = true;
        }
    }

    const bool hasFreshFrame = !hasCachedFrame && LoadHmosFrame(framePath, frame);
    if (hasFreshFrame) {
        std::lock_guard<std::mutex> lock(g_surfaceMutex);
        g_lastSurfaceFrames[surfaceId] = frame;
    } else if (!hasCachedFrame) {
        std::lock_guard<std::mutex> lock(g_surfaceMutex);
        auto cached = g_lastSurfaceFrames.find(surfaceId);
        if (cached != g_lastSurfaceFrames.end() && cached->second.valid) {
            frame = cached->second;
            hasCachedFrame = true;
        }
    }
    const bool hasFrame = hasFreshFrame || hasCachedFrame;
    const char *sourceName = hasFreshFrame ? "frame" : (hasCachedFrame ? "cached-frame" : "bootstrap");

    if (hasCachedFrame && !hasFreshFrame) {
        SetNamed(env, result, "success", CreateBool(env, true));
        SetNamed(env, result, "source", CreateString(env, sourceName));
        SetNamed(env, result, "message", CreateString(env, "no fresh Wine frame"));
        SetNamed(env, result, "width", CreateInt(env, static_cast<int>(frame.width)));
        SetNamed(env, result, "height", CreateInt(env, static_cast<int>(frame.height)));
        SetNamed(env, result, "frameNumber", CreateNumber(env, static_cast<double>(frame.frameNumber)));
        SetNamed(env, result, "inputSequence", CreateNumber(env, static_cast<double>(snapshot.inputSeq)));
        return result;
    }

    const int renderWidth = hasFrame ? static_cast<int>(frame.width) :
        static_cast<int>(std::max<uint64_t>(320, std::min<uint64_t>(snapshot.width ? snapshot.width : 896, 1280)));
    const int renderHeight = hasFrame ? static_cast<int>(frame.height) :
        static_cast<int>(std::max<uint64_t>(240, std::min<uint64_t>(snapshot.height ? snapshot.height : 640, 800)));
    {
        std::lock_guard<std::mutex> lock(g_surfaceMutex);
        auto it = g_surfaceRecords.find(surfaceId);
        if (it != g_surfaceRecords.end()) {
            it->second.frameWidth = static_cast<uint32_t>(renderWidth);
            it->second.frameHeight = static_cast<uint32_t>(renderHeight);
            it->second.inputPath = DeriveInputPathFromFramePath(framePath);
        }
    }
    OHNativeWindow *nativeWindow = static_cast<OHNativeWindow *>(snapshot.window);

    OH_NativeWindow_NativeWindowHandleOpt(nativeWindow, SET_BUFFER_GEOMETRY, renderWidth, renderHeight);
    OH_NativeWindow_NativeWindowHandleOpt(nativeWindow, SET_FORMAT, NATIVEBUFFER_PIXEL_FMT_BGRA_8888);
    OH_NativeWindow_NativeWindowHandleOpt(nativeWindow, SET_USAGE,
        static_cast<uint64_t>(NATIVEBUFFER_USAGE_CPU_WRITE | NATIVEBUFFER_USAGE_MEM_DMA));

    OHNativeWindowBuffer *windowBuffer = nullptr;
    int fenceFd = -1;
    const int32_t requestCode = OH_NativeWindow_NativeWindowRequestBuffer(nativeWindow, &windowBuffer, &fenceFd);
    if (fenceFd >= 0) {
        close(fenceFd);
        fenceFd = -1;
    }
    if (requestCode != 0 || windowBuffer == nullptr) {
        RecordSurfacePresent(surfaceId, false, sourceName, renderWidth, renderHeight, frame.frameNumber,
            "NativeWindow request buffer failed code=" + std::to_string(requestCode));
        SetNamed(env, result, "success", CreateBool(env, false));
        SetNamed(env, result, "source", CreateString(env, sourceName));
        SetNamed(env, result, "message", CreateString(env, "NativeWindow request buffer failed code=" + std::to_string(requestCode)));
        SetNamed(env, result, "inputSequence", CreateNumber(env, static_cast<double>(snapshot.inputSeq)));
        return result;
    }

    BufferHandle *handle = OH_NativeWindow_GetBufferHandleFromNative(windowBuffer);
    void *mapped = handle == nullptr ? nullptr : handle->virAddr;
    OH_NativeBuffer *nativeBuffer = nullptr;
    bool didMap = false;
    if (mapped == nullptr &&
        OH_NativeBuffer_FromNativeWindowBuffer(windowBuffer, &nativeBuffer) == 0 &&
        OH_NativeBuffer_Map(nativeBuffer, &mapped) == 0) {
        didMap = true;
    }

    if (mapped == nullptr) {
        OH_NativeWindow_NativeWindowAbortBuffer(nativeWindow, windowBuffer);
        RecordSurfacePresent(surfaceId, false, "none", renderWidth, renderHeight, frame.frameNumber,
            "NativeWindow buffer has no CPU mapping");
        SetNamed(env, result, "success", CreateBool(env, false));
        SetNamed(env, result, "source", CreateString(env, "none"));
        SetNamed(env, result, "message", CreateString(env, "NativeWindow buffer has no CPU mapping"));
        SetNamed(env, result, "inputSequence", CreateNumber(env, static_cast<double>(snapshot.inputSeq)));
        return result;
    }

    const size_t dstStride = ResolveBufferStrideBytes(handle, renderWidth, renderHeight);
    uint8_t *dst = static_cast<uint8_t *>(mapped);
    if (hasFrame) {
        CopyFrameToBuffer(dst, dstStride, renderWidth, renderHeight, frame);
    } else {
        DrawBootstrapFrame(dst, dstStride, renderWidth, renderHeight, snapshot.renderCount);
    }

    if (didMap && nativeBuffer != nullptr) {
        OH_NativeBuffer_Unmap(nativeBuffer);
    }

    Region region = {};
    region.rects = nullptr;
    region.rectNumber = 0;
    const int32_t flushCode = OH_NativeWindow_NativeWindowFlushBuffer(nativeWindow, windowBuffer, -1, region);
    if (flushCode != 0) {
        RecordSurfacePresent(surfaceId, false, hasFrame ? "frame" : "bootstrap", renderWidth, renderHeight,
            frame.frameNumber, "NativeWindow flush buffer failed code=" + std::to_string(flushCode));
        SetNamed(env, result, "success", CreateBool(env, false));
        SetNamed(env, result, "source", CreateString(env, hasFrame ? "frame" : "bootstrap"));
        SetNamed(env, result, "message", CreateString(env, "NativeWindow flush buffer failed code=" + std::to_string(flushCode)));
        SetNamed(env, result, "inputSequence", CreateNumber(env, static_cast<double>(snapshot.inputSeq)));
        return result;
    }

    if (kVerboseXComponentLogs && (snapshot.renderCount <= 3 || snapshot.renderCount % 120 == 0)) {
        OH_LOG_INFO(LOG_APP,
            "xcomponent render id=%{public}s source=%{public}s size=%{public}dx%{public}d frame=%{public}llu path=%{public}s",
            surfaceId.c_str(), sourceName, renderWidth, renderHeight,
            static_cast<unsigned long long>(frame.frameNumber), framePath.c_str());
    }

    RecordSurfacePresent(surfaceId, true, sourceName, renderWidth, renderHeight, frame.frameNumber,
        hasFrame ? "rendered Wine frame" : "rendered bootstrap frame");
    SetNamed(env, result, "success", CreateBool(env, true));
    SetNamed(env, result, "source", CreateString(env, sourceName));
    SetNamed(env, result, "message", CreateString(env, hasFrame ? "rendered Wine frame" : "rendered bootstrap frame"));
    SetNamed(env, result, "width", CreateInt(env, renderWidth));
    SetNamed(env, result, "height", CreateInt(env, renderHeight));
    SetNamed(env, result, "frameNumber", CreateNumber(env, static_cast<double>(frame.frameNumber)));
    SetNamed(env, result, "inputSequence", CreateNumber(env, static_cast<double>(snapshot.inputSeq)));
    return result;
}

int RunProtonRuntimeLaunchDirect(const char *commandLine)
{
    if (commandLine == nullptr || commandLine[0] == '\0') {
        OH_LOG_ERROR(LOG_APP, "WineChildMain got empty launch envelope");
        return EINVAL;
    }

    const std::string logPath = BuildLaunchLogPath(commandLine);
    int logFd = -1;
    if (!logPath.empty()) {
        logFd = open(logPath.c_str(), O_CREAT | O_WRONLY | O_TRUNC, 0644);
        if (logFd >= 0) {
            dprintf(logFd, "\n=== WineChildMain direct launch pid=%d ===\n", static_cast<int>(getpid()));
            dup2(logFd, STDOUT_FILENO);
            dup2(logFd, STDERR_FILENO);
            setvbuf(stdout, nullptr, _IONBF, 0);
            setvbuf(stderr, nullptr, _IONBF, 0);
        }
    }

    dlerror();
    void *runtime = dlopen("libproton_hmos_runtime.so", RTLD_NOW | RTLD_LOCAL);
    if (runtime == nullptr) {
        OH_LOG_ERROR(LOG_APP, "WineChildMain missing runtime: %{public}s", LastDlError().c_str());
        if (logFd >= 0) {
            close(logFd);
        }
        return 127;
    }

    using LaunchFn = int (*)(const char *);
    dlerror();
    auto launch = reinterpret_cast<LaunchFn>(dlsym(runtime, "proton_hmos_launch"));
    if (launch == nullptr) {
        const std::string error = LastDlError();
        dlclose(runtime);
        OH_LOG_ERROR(LOG_APP, "WineChildMain missing proton_hmos_launch: %{public}s", error.c_str());
        if (logFd >= 0) {
            close(logFd);
        }
        return 126;
    }

    OH_LOG_INFO(LOG_APP, "WineChildMain entering runtime");
    const int code = launch(commandLine);
    dlclose(runtime);
    OH_LOG_INFO(LOG_APP, "WineChildMain runtime returned rc=%{public}d", code);
    if (logFd >= 0) {
        fsync(logFd);
        close(logFd);
    }
    LaunchChildResult directResult = {
        code == 0 ? "started" : "runtime-error",
        "WineChildMain direct launch completed",
        NormalizeExitCode(code),
        true
    };
    AttachLaunchOutput(directResult, logPath);
    return NormalizeExitCode(code);
}

extern "C" int WineChildMain(const char *entryParams)
{
    return RunProtonRuntimeLaunchDirect(entryParams);
}

extern "C" int WineBrokerProbeMain(const char *entryParams)
{
    OH_LOG_INFO(LOG_APP, "WineBrokerProbeMain ok params=%{public}s", entryParams == nullptr ? "" : entryParams);
    return 0;
}

napi_value LaunchSession(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    std::string commandLine = "";
    if (argc > 0) {
        commandLine = ReadStringArg(env, args[0]);
    }

    napi_value result = nullptr;
    napi_create_object(env, &result);
    SetNamed(env, result, "sessionId", CreateString(env, "native-loader"));

    if (commandLine.empty()) {
        SetNamed(env, result, "status", CreateString(env, "invalid-command"));
        SetNamed(env, result, "reason", CreateString(env, "empty command line"));
        return result;
    }

    dlerror();
    void *runtime = dlopen("libproton_hmos_runtime.so", RTLD_NOW | RTLD_LOCAL);
    if (runtime == nullptr) {
        SetNamed(env, result, "status", CreateString(env, "missing-runtime"));
        SetNamed(env, result, "reason", CreateString(env, LastDlError()));
        return result;
    }

    using LaunchFn = int (*)(const char *);
    dlerror();
    auto launch = reinterpret_cast<LaunchFn>(dlsym(runtime, "proton_hmos_launch"));
    if (launch == nullptr) {
        const std::string error = LastDlError();
        dlclose(runtime);
        SetNamed(env, result, "status", CreateString(env, "missing-symbol"));
        SetNamed(env, result, "reason", CreateString(env, error));
        return result;
    }

    const LaunchChildResult childResult = LaunchInChildProcess(launch, commandLine);
    dlclose(runtime);

    SetNamed(env, result, "status", CreateString(env, childResult.status));
    SetNamed(env, result, "reason", CreateString(env, childResult.reason));
    if (childResult.hasExitCode) {
        SetNamed(env, result, "exitCode", CreateInt(env, static_cast<int32_t>(childResult.exitCode)));
    }
    return result;
}

napi_value LaunchSessionInCurrentProcess(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    std::string commandLine = "";
    if (argc > 0) {
        commandLine = ReadStringArg(env, args[0]);
    }

    napi_value result = nullptr;
    napi_create_object(env, &result);
    SetNamed(env, result, "sessionId", CreateString(env, "native-current-process"));

    if (commandLine.empty()) {
        SetNamed(env, result, "status", CreateString(env, "invalid-command"));
        SetNamed(env, result, "reason", CreateString(env, "empty command line"));
        return result;
    }

    OH_LOG_WARN(LOG_APP, "launchSessionInCurrentProcess entering shared native runtime; crash isolation is emulated only");
    const int code = RunProtonRuntimeLaunchDirect(commandLine.c_str());
    SetNamed(env, result, "status", CreateString(env, code == 0 ? "finished" : "runtime-error"));
    SetNamed(env, result, "reason", CreateString(env, std::string("current-process runtime returned rc=") + std::to_string(code)));
    SetNamed(env, result, "exitCode", CreateInt(env, static_cast<int32_t>(code)));
    return result;
}

napi_value ChmodExecutable(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    std::string path = "";
    if (argc > 0) {
        path = ReadStringArg(env, args[0]);
    }

    napi_value result = nullptr;
    napi_create_object(env, &result);
    SetNamed(env, result, "path", CreateString(env, path));

    if (path.empty()) {
        SetNamed(env, result, "success", CreateBool(env, false));
        SetNamed(env, result, "errnoCode", CreateInt(env, EINVAL));
        SetNamed(env, result, "message", CreateString(env, "empty path"));
        return result;
    }

    const int rc = chmod(path.c_str(), 0755);
    const int code = rc == 0 ? 0 : errno;
    SetNamed(env, result, "success", CreateBool(env, rc == 0));
    SetNamed(env, result, "errnoCode", CreateInt(env, static_cast<int32_t>(code)));
    SetNamed(env, result, "message", CreateString(env, rc == 0 ? "executable bit set" : strerror(code)));
    return result;
}

napi_value StageStoredZipRawfileTree(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value args[3] = { nullptr, nullptr, nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    napi_value result = nullptr;
    napi_create_object(env, &result);
    if (argc < 3) {
        SetNamed(env, result, "success", CreateBool(env, false));
        SetNamed(env, result, "error", CreateString(env, "stageStoredZipRawfileTree requires hspPath, zipRoot, targetPath"));
        return result;
    }

    const std::string hspPath = ReadStringArg(env, args[0]);
    std::string zipRoot = ReadStringArg(env, args[1]);
    const std::string targetRoot = ReadStringArg(env, args[2]);
    if (!zipRoot.empty() && zipRoot[zipRoot.size() - 1] != '/') {
        zipRoot.push_back('/');
    }

    SetNamed(env, result, "hspPath", CreateString(env, hspPath));
    SetNamed(env, result, "zipRoot", CreateString(env, zipRoot));
    SetNamed(env, result, "targetPath", CreateString(env, targetRoot));

    const int zipFd = open(hspPath.c_str(), O_RDONLY);
    if (zipFd < 0) {
        SetNamed(env, result, "success", CreateBool(env, false));
        SetNamed(env, result, "error", CreateString(env, std::string("open HSP failed: ") + strerror(errno)));
        return result;
    }

    std::vector<ZipEntry> entries;
    std::string error;
    if (!LoadZipCentralDirectory(zipFd, entries, error)) {
        close(zipFd);
        SetNamed(env, result, "success", CreateBool(env, false));
        SetNamed(env, result, "error", CreateString(env, error));
        return result;
    }

    int32_t fileCount = 0;
    int32_t copiedCount = 0;
    int32_t skippedCount = 0;
    uint64_t totalBytes = 0;
    for (size_t i = 0; i < entries.size(); i++) {
        const ZipEntry &entry = entries[i];
        if (!StartsWith(entry.name, zipRoot) || entry.name.empty() || entry.name[entry.name.size() - 1] == '/') {
            continue;
        }
        const std::string relative = entry.name.substr(zipRoot.size());
        if (ShouldSkipRuntimeZipRelativePath(relative)) {
            continue;
        }
        if (entry.method != 0) {
            close(zipFd);
            SetNamed(env, result, "success", CreateBool(env, false));
            SetNamed(env, result, "error", CreateString(env, "compressed rawfile is not supported: " + entry.name));
            return result;
        }
        if (entry.compressedSize != entry.uncompressedSize) {
            close(zipFd);
            SetNamed(env, result, "success", CreateBool(env, false));
            SetNamed(env, result, "error", CreateString(env, "stored rawfile size mismatch: " + entry.name));
            return result;
        }

        fileCount++;
        totalBytes += entry.uncompressedSize;
        const std::string targetPath = JoinPath(targetRoot, relative);
        if (FileExistsWithSize(targetPath, entry.uncompressedSize)) {
            skippedCount++;
            continue;
        }
        if (!CopyStoredZipEntry(zipFd, entry, targetPath, error)) {
            close(zipFd);
            SetNamed(env, result, "success", CreateBool(env, false));
            SetNamed(env, result, "error", CreateString(env, error));
            SetNamed(env, result, "fileCount", CreateInt(env, fileCount));
            SetNamed(env, result, "copiedCount", CreateInt(env, copiedCount));
            SetNamed(env, result, "skippedCount", CreateInt(env, skippedCount));
            SetNamed(env, result, "totalBytes", CreateNumber(env, static_cast<double>(totalBytes)));
            return result;
        }
        copiedCount++;
        if (fileCount <= 10 || fileCount % 500 == 0) {
            OH_LOG_INFO(LOG_APP, "staged zip rawfile %{public}d/%{public}zu: %{public}s", fileCount, entries.size(), relative.c_str());
        }
    }

    close(zipFd);
    SetNamed(env, result, "success", CreateBool(env, true));
    SetNamed(env, result, "error", CreateString(env, ""));
    SetNamed(env, result, "fileCount", CreateInt(env, fileCount));
    SetNamed(env, result, "copiedCount", CreateInt(env, copiedCount));
    SetNamed(env, result, "skippedCount", CreateInt(env, skippedCount));
    SetNamed(env, result, "totalBytes", CreateNumber(env, static_cast<double>(totalBytes)));
    return result;
}

napi_value StageDirectoryRawfileTree(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = { nullptr, nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    napi_value result = nullptr;
    napi_create_object(env, &result);
    if (argc < 2) {
        SetNamed(env, result, "success", CreateBool(env, false));
        SetNamed(env, result, "error", CreateString(env, "stageDirectoryRawfileTree requires sourceRoot and targetPath"));
        return result;
    }

    const std::string sourceRoot = ReadStringArg(env, args[0]);
    const std::string targetRoot = ReadStringArg(env, args[1]);
    SetNamed(env, result, "sourceRoot", CreateString(env, sourceRoot));
    SetNamed(env, result, "targetPath", CreateString(env, targetRoot));

    if (!IsDirectory(sourceRoot)) {
        SetNamed(env, result, "success", CreateBool(env, false));
        SetNamed(env, result, "error", CreateString(env, "source rawfile directory is not readable: " + sourceRoot));
        return result;
    }

    StageCounters counters;
    std::string error;
    if (!StageDirectoryRecursive(sourceRoot, "", targetRoot, counters, error)) {
        SetNamed(env, result, "success", CreateBool(env, false));
        SetNamed(env, result, "error", CreateString(env, error));
        SetNamed(env, result, "fileCount", CreateInt(env, counters.fileCount));
        SetNamed(env, result, "copiedCount", CreateInt(env, counters.copiedCount));
        SetNamed(env, result, "skippedCount", CreateInt(env, counters.skippedCount));
        SetNamed(env, result, "totalBytes", CreateNumber(env, static_cast<double>(counters.totalBytes)));
        return result;
    }

    SetNamed(env, result, "success", CreateBool(env, true));
    SetNamed(env, result, "error", CreateString(env, ""));
    SetNamed(env, result, "fileCount", CreateInt(env, counters.fileCount));
    SetNamed(env, result, "copiedCount", CreateInt(env, counters.copiedCount));
    SetNamed(env, result, "skippedCount", CreateInt(env, counters.skippedCount));
    SetNamed(env, result, "totalBytes", CreateNumber(env, static_cast<double>(counters.totalBytes)));
    return result;
}

napi_value NotifyWineSurfaceResize(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value args[3] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 3) {
        napi_value undefined = nullptr;
        napi_get_undefined(env, &undefined);
        return undefined;
    }

    const std::string windowId = ReadStringArg(env, args[0]);
    const int32_t width = ReadIntArg(env, args[1]);
    const int32_t height = ReadIntArg(env, args[2]);
    {
        std::lock_guard<std::mutex> lock(g_surfaceMutex);
        auto it = g_surfaceRecords.find(windowId);
        if (it != g_surfaceRecords.end()) {
            it->second.width = width > 0 ? static_cast<uint64_t>(width) : 0;
            it->second.height = height > 0 ? static_cast<uint64_t>(height) : 0;
        }
    }
    OH_LOG_INFO(LOG_APP, "wine surface resize windowId=%{public}s width=%{public}d height=%{public}d",
        windowId.c_str(), width, height);

    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    return undefined;
}

napi_value InjectKeyEvent(napi_env env, napi_callback_info info)
{
    size_t argc = 7;
    napi_value args[7] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    const std::string surfaceId = argc > 0 ? ReadStringArg(env, args[0]) : "";
    const std::string action = argc > 1 ? ReadStringArg(env, args[1]) : "";
    const int32_t keyCode = argc > 2 ? ReadIntArg(env, args[2]) : 0;
    const uint64_t modifiers = argc > 3 ? static_cast<uint64_t>(ReadInt64Arg(env, args[3])) : 0;
    const std::string source = argc > 4 ? ReadStringArg(env, args[4]) : "ARKUI";
    const int64_t deviceId = argc > 5 ? ReadInt64Arg(env, args[5]) : -1;
    const int64_t timestamp = argc > 6 ? ReadInt64Arg(env, args[6]) : 0;

    uint64_t sequence = 0;
    std::string inputPath;
    std::string message;
    const bool success = AppendSurfaceKeyBridgeEvent(surfaceId, "arkui", action.c_str(), keyCode, modifiers,
        source.c_str(), deviceId, timestamp, sequence, inputPath, message);

    napi_value result = nullptr;
    napi_create_object(env, &result);
    SetNamed(env, result, "success", CreateBool(env, success));
    SetNamed(env, result, "xcomponentId", CreateString(env, surfaceId));
    SetNamed(env, result, "message", CreateString(env, message));
    SetNamed(env, result, "inputPath", CreateString(env, inputPath));
    SetNamed(env, result, "sequence", CreateNumber(env, static_cast<double>(sequence)));
    return result;
}

napi_value ConsumeHandwritingRequest(napi_env env, napi_callback_info info)
{
    (void)info;
    HandwritingRequest snapshot;
    {
        std::lock_guard<std::mutex> lock(g_handwritingMutex);
        snapshot = g_handwritingRequest;
        g_handwritingRequest.available = false;
    }

    napi_value result = nullptr;
    napi_create_object(env, &result);
    SetNamed(env, result, "available", CreateBool(env, snapshot.available));
    SetNamed(env, result, "editable", CreateBool(env, snapshot.editable));
    SetNamed(env, result, "reason", CreateString(env, snapshot.reason));
    SetNamed(env, result, "xcomponentId", CreateString(env, snapshot.xcomponentId));
    SetNamed(env, result, "sessionId", CreateString(env, snapshot.sessionId));
    SetNamed(env, result, "hwnd", CreateString(env, snapshot.hwnd));
    SetNamed(env, result, "x", CreateNumber(env, snapshot.x));
    SetNamed(env, result, "y", CreateNumber(env, snapshot.y));
    SetNamed(env, result, "width", CreateNumber(env, snapshot.width));
    SetNamed(env, result, "height", CreateNumber(env, snapshot.height));
    SetNamed(env, result, "text", CreateString(env, snapshot.text));
    SetNamed(env, result, "selectionStart", CreateInt(env, snapshot.selectionStart));
    SetNamed(env, result, "selectionEnd", CreateInt(env, snapshot.selectionEnd));
    if (snapshot.available) {
        OH_LOG_INFO(LOG_APP,
            "handwriting request consumed editable=%{public}d reason=%{public}s id=%{public}s",
            snapshot.editable ? 1 : 0, snapshot.reason.c_str(), snapshot.xcomponentId.c_str());
    }
    return result;
}

napi_value ShowWineHandwritingAnchor(napi_env env, napi_callback_info info)
{
    size_t argc = 5;
    napi_value args[5] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    const std::string sessionId = argc > 0 ? ReadStringArg(env, args[0]) : "";
    const std::string hwnd = argc > 1 ? ReadStringArg(env, args[1]) : "";
    const std::string rect = argc > 2 ? ReadStringArg(env, args[2]) : "";
    const std::string text = argc > 3 ? ReadStringArg(env, args[3]) : "";
    const std::string selection = argc > 4 ? ReadStringArg(env, args[4]) : "";
    OH_LOG_INFO(LOG_APP,
        "handwriting anchor show requested session=%{public}s hwnd=%{public}s rect=%{public}s textLen=%{public}llu selection=%{public}s",
        sessionId.c_str(), hwnd.c_str(), rect.c_str(), static_cast<unsigned long long>(text.size()), selection.c_str());
    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    return undefined;
}

napi_value HideWineHandwritingAnchor(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    const std::string sessionId = argc > 0 ? ReadStringArg(env, args[0]) : "";
    const std::string reason = argc > 1 ? ReadStringArg(env, args[1]) : "";
    OH_LOG_INFO(LOG_APP, "handwriting anchor hide requested session=%{public}s reason=%{public}s",
        sessionId.c_str(), reason.c_str());
    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    return undefined;
}

napi_value CommitWineImeText(napi_env env, napi_callback_info info)
{
    size_t argc = 5;
    napi_value args[5] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    const std::string sessionId = argc > 0 ? ReadStringArg(env, args[0]) : "";
    const std::string hwnd = argc > 1 ? ReadStringArg(env, args[1]) : "";
    const std::string text = argc > 2 ? ReadStringArg(env, args[2]) : "";
    const std::string selection = argc > 3 ? ReadStringArg(env, args[3]) : "";
    const std::string compositionState = argc > 4 ? ReadStringArg(env, args[4]) : "";
    OH_LOG_INFO(LOG_APP,
        "wine ime commit requested session=%{public}s hwnd=%{public}s textLen=%{public}llu selection=%{public}s composition=%{public}s",
        sessionId.c_str(), hwnd.c_str(), static_cast<unsigned long long>(text.size()), selection.c_str(), compositionState.c_str());
    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    return undefined;
}

napi_value EnumerateControllers(napi_env env, napi_callback_info info)
{
    (void)info;
    napi_value result = nullptr;
    napi_create_array(env, &result);
    OH_LOG_INFO(LOG_APP, "controller bridge enumerate requested count=0 source=joystick-pending");
    return result;
}

napi_value GetControllerState(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    const int32_t deviceId = argc > 0 ? ReadIntArg(env, args[0]) : -1;

    napi_value result = nullptr;
    napi_create_object(env, &result);
    SetNamed(env, result, "deviceId", CreateInt(env, deviceId));
    SetNamed(env, result, "connected", CreateBool(env, false));

    napi_value buttons = nullptr;
    napi_create_object(env, &buttons);
    const char *buttonNames[] = { "A", "B", "X", "Y", "L1", "R1", "L2", "R2", "Start", "Select", "Mode", "ThumbL", "ThumbR" };
    for (const char *button : buttonNames) {
        SetNamed(env, buttons, button, CreateBool(env, false));
    }
    SetNamed(env, result, "buttons", buttons);

    napi_value axes = nullptr;
    napi_create_object(env, &axes);
    const char *axisNames[] = { "LX", "LY", "RX", "RY", "LT", "RT", "HAT" };
    for (const char *axis : axisNames) {
        SetNamed(env, axes, axis, CreateNumber(env, 0));
    }
    SetNamed(env, result, "axes", axes);
    OH_LOG_INFO(LOG_APP, "controller bridge state requested deviceId=%{public}d connected=0", deviceId);
    return result;
}

napi_value SendControllerOutput(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    const int32_t deviceId = argc > 0 ? ReadIntArg(env, args[0]) : -1;
    const std::string output = argc > 1 ? ReadStringArg(env, args[1]) : "";
    OH_LOG_INFO(LOG_APP,
        "controller bridge output queued deviceId=%{public}d bytes=%{public}llu supports=rumble,adaptive-trigger,hd-haptics",
        deviceId, static_cast<unsigned long long>(output.size()));
    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    return undefined;
}

napi_value StopSession(napi_env env, napi_callback_info info)
{
    (void)info;
    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    return undefined;
}
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    RegisterNativeXComponent(env, exports);
    napi_property_descriptor desc[] = {
        { "probeRuntime", nullptr, ProbeRuntime, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "mountSurface", nullptr, MountSurface, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "queryGraphicsCapabilities", nullptr, QueryGraphicsCapabilities, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "querySurfaceState", nullptr, QuerySurfaceState, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "reportWinePresent", nullptr, ReportWinePresent, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "renderSurfaceFrame", nullptr, RenderSurfaceFrame, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "clearSurfaceFrameCache", nullptr, ClearSurfaceFrameCache, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "notifyWineSurfaceResize", nullptr, NotifyWineSurfaceResize, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "injectKeyEvent", nullptr, InjectKeyEvent, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "consumeHandwritingRequest", nullptr, ConsumeHandwritingRequest, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "showWineHandwritingAnchor", nullptr, ShowWineHandwritingAnchor, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "hideWineHandwritingAnchor", nullptr, HideWineHandwritingAnchor, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "commitWineImeText", nullptr, CommitWineImeText, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "enumerateControllers", nullptr, EnumerateControllers, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "getControllerState", nullptr, GetControllerState, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "sendControllerOutput", nullptr, SendControllerOutput, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "launchSession", nullptr, LaunchSession, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "launchSessionInCurrentProcess", nullptr, LaunchSessionInCurrentProcess, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "chmodExecutable", nullptr, ChmodExecutable, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "stageStoredZipRawfileTree", nullptr, StageStoredZipRawfileTree, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "stageDirectoryRawfileTree", nullptr, StageDirectoryRawfileTree, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "stopSession", nullptr, StopSession, nullptr, nullptr, nullptr, napi_default, nullptr }
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module protonModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "proton",
    .nm_priv = nullptr,
    .reserved = { 0 },
};

extern "C" __attribute__((constructor)) void RegisterProtonModule(void)
{
    napi_module_register(&protonModule);
}
