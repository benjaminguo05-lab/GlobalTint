#import "Runtime.h"
#import <mach-o/dyld.h>
#include <atomic>

static std::atomic<bool> pending(false);

static void ImageAdded(const struct mach_header *header, intptr_t slide) {
    // Callback may run under dyld's loader lock. Do not touch Objective-C here.
    if (pending.exchange(true)) return;
    dispatch_async(dispatch_get_main_queue(), ^{ pending.store(false); CPInstallPrivate(NO); });
}
__attribute__((constructor)) static void InitializeApps(void) {
    @autoreleasepool {
        NSString *bundle=NSBundle.mainBundle.bundleIdentifier ?: @"";
        NSString *path=NSBundle.mainBundle.bundlePath ?: @"";
        if ([bundle isEqual:@"com.apple.springboard"] || ![path.pathExtension isEqual:@"app"] || [path containsString:@".appex/"]) return;
        if (!NSClassFromString(@"UIApplication")) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            CPStart(NO, ^{ CPInstallComponents(); CPInstallPrivate(NO); });
            _dyld_register_func_for_add_image(ImageAdded);
        });
    }
}
