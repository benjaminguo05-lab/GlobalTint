#import <Foundation/Foundation.h>

// Change display attributes only; preserve text, links, fonts and attachments.
static inline NSAttributedString *CPMapAttributedColors(NSAttributedString *source,
    NSArray<NSString *> *keys, id (^map)(id)) {
    if (![source isKindOfClass:NSAttributedString.class] || !source.length) return source;
    __block NSMutableAttributedString *copy=nil;
    for (NSString *key in keys)
        [source enumerateAttribute:key inRange:NSMakeRange(0,source.length) options:0 usingBlock:^(id value,NSRange range,BOOL *stop) {
            id desired=map(value);
            if (desired && ![desired isEqual:value]) {
                if (!copy) copy=[source mutableCopy];
                [copy addAttribute:key value:desired range:range];
            }
        }];
    return copy ?: source;
}
