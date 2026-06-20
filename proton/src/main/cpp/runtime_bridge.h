#ifndef PROTON_HMOS_RUNTIME_BRIDGE_H
#define PROTON_HMOS_RUNTIME_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

// Export this symbol from libproton_hmos_runtime.so. libproton.so loads it at runtime.
int proton_hmos_launch(const char *command_line);

// Native child-process entrypoints use the same launch envelope but keep a
// distinct symbol so Wine's broker path can be wired without depending on NAPI.
int proton_hmos_launch_child(const char *command_line);

#ifdef __cplusplus
}
#endif

#endif
