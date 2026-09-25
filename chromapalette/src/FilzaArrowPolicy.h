#import <Foundation/Foundation.h>

// These four assets have explicit live view adapters. Keep the factory's source
// images intact so disabling/recoloring a cached arrow remains reversible.
static inline BOOL CPFilzaLiveArrowAsset(id name) {
    if (![name isKindOfClass:NSString.class]) return NO;
    return [name isEqual:@"arrow_up"] || [name isEqual:@"arrow_down"] ||
        [name isEqual:@"e_return"] || [name isEqual:@"e_expand"];
}
