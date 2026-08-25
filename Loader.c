#include <dlfcn.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int GTGetExecutablePath(char *buffer, size_t capacity) {
    if (!buffer || capacity == 0) {
        return 0;
    }

    uint32_t size = (uint32_t)capacity;

    if (_NSGetExecutablePath(buffer, &size) != 0) {
        return 0;
    }

    buffer[capacity - 1] = '\0';
    return 1;
}

static int GTIsFullApplicationProcess(const char *executablePath) {
    if (!executablePath) {
        return 0;
    }

    // Full applications have an .app component. App extensions commonly have
    // both a host .app and their own .appex component, so reject .appex first.
    if (strstr(executablePath, ".appex/") != NULL) {
        return 0;
    }

    return strstr(executablePath, ".app/") != NULL;
}

static int GTIsSpringBoardProcess(void) {
    const char *programName = getprogname();

    if (programName &&
        strcmp(programName, "SpringBoard") == 0) {
        return 1;
    }

    char executablePath[PATH_MAX] = {0};

    if (!GTGetExecutablePath(
            executablePath,
            sizeof(executablePath))) {
        return 0;
    }

    const char *lastSlash =
        strrchr(executablePath, '/');

    const char *baseName =
        lastSlash ? lastSlash + 1 : executablePath;

    return strcmp(baseName, "SpringBoard") == 0;
}

static int GTCorePath(char *buffer, size_t capacity) {
    if (!buffer || capacity == 0) {
        return 0;
    }

    Dl_info info;

    if (dladdr((const void *)&GTCorePath, &info) == 0 ||
        !info.dli_fname) {
        return 0;
    }

    const char *lastSlash =
        strrchr(info.dli_fname, '/');

    if (!lastSlash) {
        return 0;
    }

    size_t directoryLength =
        (size_t)(lastSlash - info.dli_fname);

    const char *coreName =
        "/GlobalTintCore.dylib";

    size_t required =
        directoryLength +
        strlen(coreName) +
        1;

    if (required > capacity) {
        return 0;
    }

    memcpy(
        buffer,
        info.dli_fname,
        directoryLength
    );

    memcpy(
        buffer + directoryLength,
        coreName,
        strlen(coreName) + 1
    );

    return 1;
}

__attribute__((constructor))
static void GTLoaderInitialize(void) {
    // This check happens inside the tiny C loader, before the UIKit/Logos
    // GlobalTint core image is ever loaded.
    if (GTIsSpringBoardProcess()) {
        return;
    }

    char executablePath[PATH_MAX] = {0};

    if (!GTGetExecutablePath(
            executablePath,
            sizeof(executablePath))) {
        return;
    }

    if (!GTIsFullApplicationProcess(
            executablePath)) {
        return;
    }

    char corePath[PATH_MAX] = {0};

    if (!GTCorePath(
            corePath,
            sizeof(corePath))) {
        return;
    }

    // The core has a deliberately impossible MobileLoader filter and is only
    // reached through this explicit dlopen in eligible full app processes.
    (void)dlopen(
        corePath,
        RTLD_NOW | RTLD_LOCAL
    );
}
