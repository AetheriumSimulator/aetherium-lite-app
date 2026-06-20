#define _GNU_SOURCE

#include <dlfcn.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

extern char **environ;

static char *dirname_dup(const char *path)
{
    char *copy;
    char *slash;

    if (!path || !path[0]) {
        return NULL;
    }
    copy = realpath(path, NULL);
    if (!copy) {
        copy = strdup(path);
    }
    if (!copy) {
        return NULL;
    }
    slash = strrchr(copy, '/');
    if (!slash) {
        free(copy);
        return NULL;
    }
    if (slash == copy) {
        slash[1] = '\0';
    } else {
        slash[0] = '\0';
    }
    return copy;
}

static char *join_path(const char *dir, const char *name)
{
    size_t dir_len;
    size_t name_len;
    char *result;

    if (!dir || !name) {
        return NULL;
    }
    dir_len = strlen(dir);
    name_len = strlen(name);
    result = malloc(dir_len + name_len + 2);
    if (!result) {
        return NULL;
    }
    memcpy(result, dir, dir_len);
    if (dir_len && result[dir_len - 1] != '/') {
        result[dir_len++] = '/';
    }
    memcpy(result + dir_len, name, name_len + 1);
    return result;
}

static int ends_with(const char *value, const char *suffix)
{
    size_t value_len;
    size_t suffix_len;

    if (!value || !suffix) {
        return 0;
    }
    value_len = strlen(value);
    suffix_len = strlen(suffix);
    return value_len >= suffix_len && !strcmp(value + value_len - suffix_len, suffix);
}

static void ensure_winedllpath_from_ntdll(const char *ntdll_path)
{
    static const char suffix[] = "/x86_64-unix/ntdll.so";
    const char *path = getenv("WINEDLLPATH");
    char *root;
    size_t root_len;

    if (path && path[0]) {
        return;
    }
    if (!ntdll_path || !ends_with(ntdll_path, suffix)) {
        return;
    }

    root_len = strlen(ntdll_path) - strlen(suffix);
    root = malloc(root_len + 1);
    if (!root) {
        return;
    }
    memcpy(root, ntdll_path, root_len);
    root[root_len] = '\0';
    if (!setenv("WINEDLLPATH", root, 1)) {
        fprintf(stderr, "wine-hmos-loader: inferred WINEDLLPATH=%s\n", root);
    }
    free(root);
}

static void log_access_probe(const char *label, const char *path)
{
    if (!path || !path[0]) {
        return;
    }
    fprintf(stderr, "wine-hmos-loader: probe %s %s => %s\n",
            label, path, access(path, R_OK) == 0 ? "readable" : "missing");
}

static void log_winedllpath_probe(void)
{
    const char *path = getenv("WINEDLLPATH");
    char *copy;
    char *item;

    fprintf(stderr, "wine-hmos-loader: env WINEPREFIX=%s\n", getenv("WINEPREFIX") ?: "<unset>");
    fprintf(stderr, "wine-hmos-loader: env WINEDLLPATH=%s\n", path ?: "<unset>");
    fprintf(stderr, "wine-hmos-loader: env LD_LIBRARY_PATH=%s\n", getenv("LD_LIBRARY_PATH") ?: "<unset>");
    if (!path || !path[0]) {
        return;
    }

    copy = strdup(path);
    if (!copy) {
        return;
    }
    for (item = strtok(copy, ":"); item; item = strtok(NULL, ":")) {
        char *kernel32 = join_path(item, "x86_64-windows/kernel32.dll");
        char *ntdll = join_path(item, "x86_64-unix/ntdll.so");
        log_access_probe("kernel32", kernel32);
        log_access_probe("ntdll", ntdll);
        free(kernel32);
        free(ntdll);
    }
    free(copy);
}

static void *try_load_ntdll(const char *path)
{
    void *handle;

    if (!path || !path[0]) {
        return NULL;
    }
    handle = dlopen(path, RTLD_NOW | RTLD_GLOBAL);
    if (handle) {
        return handle;
    }
    fprintf(stderr, "wine-hmos-loader: dlopen failed for %s: %s\n", path, dlerror());
    return NULL;
}

__attribute__((visibility("default"))) int wine_hmos_main(int argc, char **argv, char **envp)
{
    const char *env_ntdll;
    char *loader_dir = NULL;
    char *ntdll_path = NULL;
    void *handle = NULL;
    void (*wine_main)(int, char **) = NULL;

    if (envp) {
        environ = envp;
    }

    env_ntdll = getenv("WINE_HMOS_NTDLL_SO");
    ensure_winedllpath_from_ntdll(env_ntdll);
    log_winedllpath_probe();
    if (env_ntdll && env_ntdll[0]) {
        log_access_probe("env-ntdll", env_ntdll);
        handle = try_load_ntdll(env_ntdll);
    }

    if (!handle && argc > 0 && argv && argv[0]) {
        loader_dir = dirname_dup(argv[0]);
        ntdll_path = join_path(loader_dir, "ntdll.so");
        handle = try_load_ntdll(ntdll_path);
    }

    if (!handle) {
        handle = try_load_ntdll("ntdll.so");
    }

    free(ntdll_path);
    free(loader_dir);

    if (!handle) {
        fprintf(stderr, "wine-hmos-loader: could not load ntdll.so\n");
        return 127;
    }

    wine_main = (void (*)(int, char **))dlsym(handle, "__wine_main");
    if (!wine_main) {
        fprintf(stderr, "wine-hmos-loader: __wine_main not found in ntdll.so: %s\n", dlerror());
        return 126;
    }

    wine_main(argc, argv);
    return 0;
}
