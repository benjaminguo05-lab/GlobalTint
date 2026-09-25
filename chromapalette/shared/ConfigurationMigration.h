#import <Foundation/Foundation.h>

static inline NSDictionary *CPConfigurationPayload(id file) {
    if (![file isKindOfClass:NSDictionary.class]) return nil;
    id value=file[@"configuration"] ?: file;
    if (![value isKindOfClass:NSDictionary.class] || ![value[@"enabled"] isKindOfClass:NSNumber.class] ||
        ![value[@"roles"] isKindOfClass:NSDictionary.class] || ![value[@"groups"] isKindOfClass:NSDictionary.class]) return nil;
    return value;
}
static inline NSDictionary *CPMigrateAccent(NSDictionary *input) {
    if (![input isKindOfClass:NSDictionary.class]) return input;
    NSDictionary *roles=[input[@"roles"] isKindOfClass:NSDictionary.class] ? input[@"roles"] : @{};
    NSMutableDictionary *out=[input mutableCopy], *next=[roles mutableCopy];
    NSDictionary *selected=roles[@"accent.color"];
    NSString *oldGroup=nil;
    if (![selected isKindOfClass:NSDictionary.class]) {
        selected=nil;
        for (NSString *key in @[@"accent.foreground",@"filza.accent",@"messages.accent",@"notes.link"])
            if ([roles[key] isKindOfClass:NSDictionary.class]) { selected=roles[key]; oldGroup=[key componentsSeparatedByString:@"."].firstObject; break; }
    }
    if (selected) {
        NSMutableDictionary *color=[selected mutableCopy]; color[@"enabled"]=@YES;
        next[@"accent.color"]=color;
        NSMutableDictionary *groups=[input[@"groups"] isKindOfClass:NSDictionary.class] ? [input[@"groups"] mutableCopy] : [NSMutableDictionary dictionary];
        if (oldGroup) groups[@"accent"]=@((!groups[oldGroup] || [groups[oldGroup] boolValue]) && (!selected[@"enabled"] || [selected[@"enabled"] boolValue]));
        out[@"groups"]=groups;
    }
    out[@"roles"]=next;
    return out;
}
