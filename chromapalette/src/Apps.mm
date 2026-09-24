#import "Runtime.h"
__attribute__((constructor)) static void InitializeApps(void) {
    @autoreleasepool {
        NSString *bundle=NSBundle.mainBundle.bundleIdentifier ?: @"";
        NSString *path=NSBundle.mainBundle.bundlePath ?: @"";
        if ([bundle isEqual:@"com.apple.springboard"] || ![path.pathExtension isEqual:@"app"] || [path containsString:@".appex/"]) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!NSClassFromString(@"UIApplication")) return;
            CPStart(NO, ^{ CPInstallComponents(); CPInstallPrivate(NO); });
        });
    }
}
