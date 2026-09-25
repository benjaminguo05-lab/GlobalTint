#import "Config.h"
#import <roothide.h>
#import <dlfcn.h>
#import <unistd.h>
#import <sys/stat.h>
#import "ConfigurationMigration.h"

static NSString * const IcleanerStatusPath=@"/var/mobile/Library/Preferences/com.benja.chromapalette.icleaner-status.plist";
NSDictionary *CPIcleanerStatus(void) {
    CPPreparePreferences();
    return [NSDictionary dictionaryWithContentsOfURL:[NSURL fileURLWithPath:IcleanerStatusPath] error:nil];
}

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
    input=CPMigrateAccent(input);
    NSMutableDictionary *out = [defaults mutableCopy];
    for (NSString *k in @[@"enabled", @"systemEnabled"])
        if ([input[k] isKindOfClass:NSNumber.class]) out[k] = @([input[k] boolValue]);
    // Preserve colors on upgrade, but do not automatically reactivate the old
    // all-enabled configuration that could freeze apps in 0.1.0.
    if (![input[@"schema"] isKindOfClass:NSNumber.class] || [input[@"schema"] integerValue] < 2) {
        out[@"enabled"]=@NO; out[@"systemEnabled"]=@NO;
    }
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
    // Root-launched jailbreak apps must read the same mobile-owned preferences.
    // Read the explicit file first; the suite remains a fallback if direct access
    // is unavailable. Never create a second root user's configuration.
    NSString *readSource=@"none";
    id raw=nil;
    // Relaxin's cfprefsd redirects third-party preference files through jbroot.
    // UID 0 must read mobile's redirected file, not its own current-user suite.
    for (NSString *path in @[jbroot(CPPreferencePath),CPPreferencePath]) {
        NSDictionary *file=[NSDictionary dictionaryWithContentsOfURL:[NSURL fileURLWithPath:path] error:nil];
        raw=CPConfigurationPayload(file);
        if (raw) { readSource=[path isEqual:CPPreferencePath] ? @"原路径" : @"RootHide mobile 文件"; break; }
    }
    BOOL direct=[raw isKindOfClass:NSDictionary.class];
    if (!direct) {
        NSUserDefaults *store=[[NSUserDefaults alloc] initWithSuiteName:CPPreferencePath];
        [store synchronize]; raw=CPConfigurationPayload([store objectForKey:@"configuration"]);
        if ([raw isKindOfClass:NSDictionary.class]) readSource=@"偏好服务";
    }
    if (![raw isKindOfClass:NSDictionary.class] && geteuid()==0) {
        // Explicit mobile user, so a root app never selects root's empty domain.
        CFPreferencesSynchronize(CFSTR("com.benja.chromapalette"),CFSTR("mobile"),kCFPreferencesAnyHost);
        raw=CFBridgingRelease(CFPreferencesCopyValue(CFSTR("configuration"),CFSTR("com.benja.chromapalette"),CFSTR("mobile"),kCFPreferencesAnyHost));
        raw=CPConfigurationPayload(raw);
        if (raw) readSource=@"mobile 偏好服务";
    }
    NSDictionary *config=CPNormalizeConfiguration(raw);
    NSString *bundle=NSBundle.mainBundle.bundleIdentifier ?: @"";
    if ([bundle.lowercaseString containsString:@"icleaner"]) {
        // Local, fixed-size status only. No screen contents or user configuration.
        NSDictionary *status=@{@"version":@"0.1.8",@"bundle":bundle,@"date":NSDate.date,
            @"pid":@(getpid()),@"uid":@(geteuid()),@"libSandy":@(CPPreparePreferences()),
            @"readable":@([raw isKindOfClass:NSDictionary.class]),@"direct":@(direct),@"source":readSource,
            @"enabled":config[@"enabled"],@"excluded":@([config[@"excludedApps"] containsObject:bundle])};
        if ([status writeToURL:[NSURL fileURLWithPath:IcleanerStatusPath] error:nil]) {
            chmod(IcleanerStatusPath.fileSystemRepresentation,0644);
            if (geteuid()==0) chown(IcleanerStatusPath.fileSystemRepresentation,501,501);
        }
    }
    return config;
}
BOOL CPWriteConfiguration(NSDictionary *configuration) {
    CPPreparePreferences();
    NSUserDefaults *store = [[NSUserDefaults alloc] initWithSuiteName:CPPreferencePath];
    [store setObject:CPNormalizeConfiguration(configuration) forKey:@"configuration"];
    BOOL ok = [store synchronize];
    if (ok) CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)CPNotification, NULL, NULL, true);
    return ok;
}
