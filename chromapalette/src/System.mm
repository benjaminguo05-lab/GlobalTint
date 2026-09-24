#import "Runtime.h"
__attribute__((constructor)) static void InitializeSystem(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.springboard"]) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            // Only the explicit status-bar / Control Center adapters are registered here.
            CPStart(YES, ^{ CPInstallPrivate(YES); });
        });
    }
}
