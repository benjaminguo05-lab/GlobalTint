#import "Runtime.h"
#import <mach-o/dyld.h>
#include <atomic>

static std::atomic<bool> pending(false);

static void ImageAdded(const struct mach_header *header, intptr_t slide) {
    if (pending.exchange(true)) return;
    dispatch_async(dispatch_get_main_queue(), ^{ pending.store(false); CPInstallPrivate(YES); });
}
__attribute__((constructor)) static void InitializeSystem(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.springboard"]) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            // Only the explicit status-bar / Control Center adapters are registered here.
            CPStart(YES, ^{ CPInstallPrivate(YES); });
            _dyld_register_func_for_add_image(ImageAdded);
        });
    }
}
