#import "Config.h"
#import <roothide.h>
#import <dlfcn.h>

int CPPreparePreferences(void) {
    static int result = -1;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *handle = dlopen(jbroot("/usr/lib/libsandy.dylib"), RTLD_NOW | RTLD_LOCAL);
        if (!handle) return;
        int (*apply)(const char *) = (int (*)(const char *))dlsym(handle, "libSandy_applyProfile");
        if (apply) result = apply("com.benja.chromapalette");
        // Keep the library loaded for the lifetime of this process.
    });
    return result;
}
NSDictionary *CPNormalizeConfiguration(id input) {
    NSDictionary *defaults = CPDefaults();
    if (![input isKindOfClass:NSDictionary.class]) return defaults;
    NSMutableDictionary *out = [defaults mutableCopy];
    for (NSString *k in @[@"enabled", @"systemEnabled"])
        if ([input[k] isKindOfClass:NSNumber.class]) out[k] = @([input[k] boolValue]);
    NSMutableDictionary *groups = [defaults[@"groups"] mutableCopy];
    NSDictionary *inGroups = [input[@"groups"] isKindOfClass:NSDictionary.class] ? input[@"groups"] : @{};
    for (NSString *k in groups.allKeys) if ([inGroups[k] isKindOfClass:NSNumber.class]) groups[k] = @([inGroups[k] boolValue]);
    out[@"groups"] = groups;
    NSMutableDictionary *roles = [defaults[@"roles"] mutableCopy];
    NSDictionary *inRoles = [input[@"roles"] isKindOfClass:NSDictionary.class] ? input[@"roles"] : @{};
    for (NSString *k in roles.allKeys) {
        NSDictionary *value = inRoles[k];
        if (![value isKindOfClass:NSDictionary.class]) continue;
        NSMutableDictionary *role = [roles[k] mutableCopy];
        if ([value[@"enabled"] isKindOfClass:NSNumber.class]) role[@"enabled"] = @([value[@"enabled"] boolValue]);
        for (NSString *mode in @[@"light", @"dark"])
            if (CPParseHex(value[mode])) role[mode] = CPHex(CPParseHex(value[mode]));
        roles[k] = role;
    }
    out[@"roles"] = roles;
    NSMutableArray *excluded = [NSMutableArray array];
    if ([input[@"excludedApps"] isKindOfClass:NSArray.class])
        for (id value in input[@"excludedApps"])
            if ([value isKindOfClass:NSString.class] && [value length] && [value length] < 256) [excluded addObject:value];
    out[@"excludedApps"] = excluded;
    return out;
}
NSDictionary *CPReadConfiguration(void) {
    CPPreparePreferences();
    NSUserDefaults *store = [[NSUserDefaults alloc] initWithSuiteName:CPPreferencePath];
    [store synchronize];
    return CPNormalizeConfiguration([store objectForKey:@"configuration"]);
}
BOOL CPWriteConfiguration(NSDictionary *configuration) {
    CPPreparePreferences();
    NSUserDefaults *store = [[NSUserDefaults alloc] initWithSuiteName:CPPreferencePath];
    [store setObject:CPNormalizeConfiguration(configuration) forKey:@"configuration"];
    BOOL ok = [store synchronize];
    if (ok) CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)CPNotification, NULL, NULL, true);
    return ok;
}
