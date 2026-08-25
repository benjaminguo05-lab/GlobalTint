#import "GTAppListController.h"
#import "GTAppDetailController.h"

#import <Cephei/HBPreferences.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>

static NSString * const GTPrefsIdentifier =
    @"com.benja.globaltint";

static id GTLSMessageId(id object, SEL selector) {
    if (!object || !selector ||
        ![object respondsToSelector:selector]) {
        return nil;
    }

    return ((id (*)(id, SEL))objc_msgSend)(
        object,
        selector
    );
}

static void GTLoadLaunchServicesFrameworks(void) {
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        dlopen(
            "/System/Library/Frameworks/CoreServices.framework/CoreServices",
            RTLD_LAZY | RTLD_LOCAL
        );

        dlopen(
            "/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices",
            RTLD_LAZY | RTLD_LOCAL
        );
    });
}

static NSArray<NSDictionary<NSString *, NSString *> *> *
GTInstalledApplicationRecords(void) {
    GTLoadLaunchServicesFrameworks();

    Class workspaceClass =
        NSClassFromString(@"LSApplicationWorkspace");

    if (!workspaceClass) {
        return @[];
    }

    id workspace =
        GTLSMessageId(
            (id)workspaceClass,
            NSSelectorFromString(@"defaultWorkspace")
        );

    if (!workspace) {
        return @[];
    }

    NSArray *proxies =
        GTLSMessageId(
            workspace,
            NSSelectorFromString(@"allInstalledApplications")
        );

    if (![proxies isKindOfClass:[NSArray class]]) {
        proxies =
            GTLSMessageId(
                workspace,
                NSSelectorFromString(@"allApplications")
            );
    }

    if (![proxies isKindOfClass:[NSArray class]]) {
        return @[];
    }

    NSMutableDictionary<NSString *, NSDictionary *> *deduplicated =
        [NSMutableDictionary dictionary];

    for (id proxy in proxies) {
        NSString *bundleID =
            GTLSMessageId(
                proxy,
                NSSelectorFromString(@"applicationIdentifier")
            );

        if (![bundleID isKindOfClass:[NSString class]] ||
            bundleID.length == 0) {
            bundleID =
                GTLSMessageId(
                    proxy,
                    NSSelectorFromString(@"bundleIdentifier")
                );
        }

        if (![bundleID isKindOfClass:[NSString class]] ||
            bundleID.length == 0) {
            continue;
        }

        NSString *name =
            GTLSMessageId(
                proxy,
                NSSelectorFromString(@"localizedName")
            );

        if (![name isKindOfClass:[NSString class]] ||
            name.length == 0) {
            name =
                GTLSMessageId(
                    proxy,
                    NSSelectorFromString(@"itemName")
                );
        }

        if (![name isKindOfClass:[NSString class]] ||
            name.length == 0) {
            name = bundleID;
        }

        NSString *applicationType =
            GTLSMessageId(
                proxy,
                NSSelectorFromString(@"applicationType")
            );

        NSString *type = @"user";

        if ([applicationType isKindOfClass:[NSString class]] &&
            [[applicationType lowercaseString]
             containsString:@"system"]) {
            type = @"system";
        }

        NSString *normalized =
            bundleID.lowercaseString;

        deduplicated[normalized] = @{
            @"name": name,
            @"bundleID": bundleID,
            @"type": type
        };
    }

    NSArray *records =
        deduplicated.allValues;

    return [records sortedArrayUsingComparator:
        ^NSComparisonResult(NSDictionary *left,
                            NSDictionary *right) {

        NSString *leftName =
            left[@"name"] ?: left[@"bundleID"] ?: @"";

        NSString *rightName =
            right[@"name"] ?: right[@"bundleID"] ?: @"";

        NSComparisonResult result =
            [leftName localizedCaseInsensitiveCompare:rightName];

        if (result != NSOrderedSame) {
            return result;
        }

        return [(left[@"bundleID"] ?: @"")
                localizedCaseInsensitiveCompare:
                    (right[@"bundleID"] ?: @"")];
    }];
}

@implementation GTAppListController

- (HBPreferences *)preferences {
    return [[HBPreferences alloc]
            initWithIdentifier:GTPrefsIdentifier];
}

- (NSSet<NSString *> *)configuredBundleIDs {
    HBPreferences *preferences =
        [self preferences];

    NSMutableSet<NSString *> *bundleIDs =
        [NSMutableSet set];

    for (NSString *key in @[
        @"AppColorOverrides",
        @"AppComponentColorOverrides",
        @"AppComponentSwitchOverrides"
    ]) {
        id value =
            [preferences objectForKey:key];

        if (![value isKindOfClass:[NSDictionary class]]) {
            continue;
        }

        for (id rawKey in [(NSDictionary *)value allKeys]) {
            if (![rawKey isKindOfClass:[NSString class]]) {
                continue;
            }

            NSString *bundleID =
                [[(NSString *)rawKey
                  stringByTrimmingCharactersInSet:
                    [NSCharacterSet
                     whitespaceAndNewlineCharacterSet]]
                 lowercaseString];

            if (bundleID.length > 0) {
                [bundleIDs addObject:bundleID];
            }
        }
    }

    id excluded =
        [preferences objectForKey:@"ExcludedBundleIDs"];

    if ([excluded isKindOfClass:[NSString class]]) {
        NSArray<NSString *> *parts =
            [(NSString *)excluded
             componentsSeparatedByString:@","];

        for (NSString *part in parts) {
            NSString *bundleID =
                [[part
                  stringByTrimmingCharactersInSet:
                    [NSCharacterSet
                     whitespaceAndNewlineCharacterSet]]
                 lowercaseString];

            if (bundleID.length > 0) {
                [bundleIDs addObject:bundleID];
            }
        }
    }

    return [bundleIDs copy];
}

- (PSSpecifier *)appSpecifierWithName:(NSString *)name
                             bundleID:(NSString *)bundleID {

    NSString *label =
        [name isEqualToString:bundleID]
        ? bundleID
        : [NSString stringWithFormat:@"%@ · %@",
           name,
           bundleID];

    PSSpecifier *specifier =
        [PSSpecifier preferenceSpecifierNamed:label
                                       target:self
                                          set:nil
                                          get:nil
                                       detail:[GTAppDetailController class]
                                         cell:PSLinkCell
                                         edit:nil];

    [specifier setProperty:bundleID
                    forKey:@"GTBundleID"];

    [specifier setProperty:name
                    forKey:@"GTAppName"];

    return specifier;
}

- (NSMutableArray *)buildSpecifiers {
    NSMutableArray *items =
        [NSMutableArray array];

    PSSpecifier *intro =
        [PSSpecifier groupSpecifierWithName:@"APP 配置管理"];

    [intro setProperty:
        @"直接从已安装 App 中选择。进入 App 后可以管理主色、组件颜色、组件开关以及排除状态。应用列表由系统 LaunchServices 读取；若某个 App 没出现在列表中，主页面仍保留手动 Bundle ID 配置作为备用。"
        forKey:@"footerText"];

    [items addObject:intro];

    PSSpecifier *refresh =
        [PSSpecifier preferenceSpecifierNamed:@"刷新应用列表"
                                       target:self
                                          set:nil
                                          get:nil
                                       detail:nil
                                         cell:PSButtonCell
                                         edit:nil];

    refresh.buttonAction =
        @selector(refreshApplicationList);

    [items addObject:refresh];

    NSArray<NSDictionary *> *records =
        GTInstalledApplicationRecords();

    NSMutableArray<NSDictionary *> *userApps =
        [NSMutableArray array];

    NSMutableArray<NSDictionary *> *systemApps =
        [NSMutableArray array];

    NSMutableSet<NSString *> *listedBundleIDs =
        [NSMutableSet set];

    for (NSDictionary *record in records) {
        NSString *bundleID =
            [record[@"bundleID"] lowercaseString];

        if (bundleID.length == 0) {
            continue;
        }

        [listedBundleIDs addObject:bundleID];

        if ([record[@"type"] isEqualToString:@"system"]) {
            [systemApps addObject:record];
        } else {
            [userApps addObject:record];
        }
    }

    if (userApps.count > 0) {
        PSSpecifier *group =
            [PSSpecifier
             groupSpecifierWithName:@"用户 App"];

        [items addObject:group];

        for (NSDictionary *record in userApps) {
            [items addObject:
                [self appSpecifierWithName:record[@"name"]
                                  bundleID:record[@"bundleID"]]];
        }
    }

    if (systemApps.count > 0) {
        PSSpecifier *group =
            [PSSpecifier
             groupSpecifierWithName:@"系统 App"];

        [items addObject:group];

        for (NSDictionary *record in systemApps) {
            [items addObject:
                [self appSpecifierWithName:record[@"name"]
                                  bundleID:record[@"bundleID"]]];
        }
    }

    NSMutableArray<NSString *> *missingConfigured =
        [NSMutableArray array];

    for (NSString *bundleID in [self configuredBundleIDs]) {
        if (![listedBundleIDs containsObject:bundleID]) {
            [missingConfigured addObject:bundleID];
        }
    }

    [missingConfigured sortUsingSelector:
        @selector(localizedCaseInsensitiveCompare:)];

    if (missingConfigured.count > 0) {
        PSSpecifier *group =
            [PSSpecifier
             groupSpecifierWithName:@"已配置但未在应用列表中"];

        [group setProperty:
            @"这些 Bundle ID 已存在 GlobalTint 配置，但 LaunchServices 当前没有把它们返回到已安装 App 列表。仍可进入并编辑。"
            forKey:@"footerText"];

        [items addObject:group];

        for (NSString *bundleID in missingConfigured) {
            [items addObject:
                [self appSpecifierWithName:bundleID
                                  bundleID:bundleID]];
        }
    }

    if (userApps.count == 0 &&
        systemApps.count == 0 &&
        missingConfigured.count == 0) {

        PSSpecifier *empty =
            [PSSpecifier groupSpecifierWithName:
                @"未读取到应用"];

        [empty setProperty:
            @"LaunchServices 没有返回应用列表。可以返回 GlobalTint 主页面继续使用手动 Bundle ID 配置。"
            forKey:@"footerText"];

        [items addObject:empty];
    }

    return items;
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers =
            [self buildSpecifiers];
    }

    return _specifiers;
}

- (void)refreshApplicationList {
    _specifiers = nil;
    [self reloadSpecifiers];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    self.title = @"App 配置管理";
}

@end
