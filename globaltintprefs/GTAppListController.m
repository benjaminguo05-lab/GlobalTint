#import "GTAppListController.h"
#import "GTAppDetailController.h"
#import "GTAppIcon.h"

#import <Cephei/HBPreferences.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>

static NSString * const GTPrefsIdentifier =
    @"com.benja.globaltint";

static id GTLSMessageId(id object, SEL selector) {
    if (!object ||
        !selector ||
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
            NSSelectorFromString(
                @"allInstalledApplications"
            )
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

    NSMutableDictionary<
        NSString *,
        NSDictionary *
    > *deduplicated =
        [NSMutableDictionary dictionary];

    for (id proxy in proxies) {
        NSString *bundleID =
            GTLSMessageId(
                proxy,
                NSSelectorFromString(
                    @"applicationIdentifier"
                )
            );

        if (![bundleID isKindOfClass:[NSString class]] ||
            bundleID.length == 0) {

            bundleID =
                GTLSMessageId(
                    proxy,
                    NSSelectorFromString(
                        @"bundleIdentifier"
                    )
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
                NSSelectorFromString(
                    @"applicationType"
                )
            );

        NSString *type = @"user";

        if ([applicationType
             isKindOfClass:[NSString class]] &&
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

    return deduplicated.allValues;
}

@interface GTAppListController ()
@property (nonatomic, copy)
    NSArray<NSDictionary<NSString *, NSString *> *>
        *gtApplicationRecords;

@property (nonatomic, copy)
    NSString *gtSearchQuery;

@property (nonatomic, strong)
    UISearchController *gtSearchController;
@end

@implementation GTAppListController

#pragma mark - Preferences / status

- (HBPreferences *)preferences {
    return [[HBPreferences alloc]
            initWithIdentifier:GTPrefsIdentifier];
}

- (NSDictionary *)dictionaryPreferenceForKey:
    (NSString *)key {

    id value =
        [[self preferences] objectForKey:key];

    if (![value isKindOfClass:[NSDictionary class]]) {
        return @{};
    }

    return value;
}

- (NSSet<NSString *> *)excludedBundleIDs {
    id value =
        [[self preferences]
         objectForKey:@"ExcludedBundleIDs"];

    if (![value isKindOfClass:[NSString class]]) {
        return [NSSet set];
    }

    NSMutableSet<NSString *> *result =
        [NSMutableSet set];

    for (NSString *part in
         [(NSString *)value
          componentsSeparatedByString:@","]) {

        NSString *bundleID =
            [[part
              stringByTrimmingCharactersInSet:
                NSCharacterSet
                    .whitespaceAndNewlineCharacterSet]
             lowercaseString];

        if (bundleID.length > 0) {
            [result addObject:bundleID];
        }
    }

    return [result copy];
}

- (NSDictionary *)statusForBundleID:
    (NSString *)bundleID {

    NSString *normalized =
        bundleID.lowercaseString ?: @"";

    NSDictionary *accentProfiles =
        [self dictionaryPreferenceForKey:
            @"AppColorOverrides"];

    NSDictionary *colorProfiles =
        [self dictionaryPreferenceForKey:
            @"AppComponentColorOverrides"];

    NSDictionary *switchProfiles =
        [self dictionaryPreferenceForKey:
            @"AppComponentSwitchOverrides"];

    BOOL hasAccent =
        [accentProfiles[normalized]
         isKindOfClass:[NSString class]];

    NSInteger colorCount = 0;
    id colors = colorProfiles[normalized];

    if ([colors isKindOfClass:[NSDictionary class]]) {
        colorCount =
            [(NSDictionary *)colors count];
    }

    NSInteger switchCount = 0;
    id switches = switchProfiles[normalized];

    if ([switches isKindOfClass:[NSDictionary class]]) {
        switchCount =
            [(NSDictionary *)switches count];
    }

    BOOL excluded =
        [[self excludedBundleIDs]
         containsObject:normalized];

    NSMutableArray<NSString *> *parts =
        [NSMutableArray array];

    if (excluded) {
        [parts addObject:@"已排除"];
    }

    if (hasAccent) {
        [parts addObject:@"主色"];
    }

    if (colorCount > 0) {
        [parts addObject:
            [NSString stringWithFormat:
                @"%ld色",
                (long)colorCount]];
    }

    if (switchCount > 0) {
        [parts addObject:
            [NSString stringWithFormat:
                @"%ld开关",
                (long)switchCount]];
    }

    BOOL configured =
        excluded ||
        hasAccent ||
        colorCount > 0 ||
        switchCount > 0;

    NSString *text =
        configured
        ? [parts componentsJoinedByString:@" · "]
        : @"未配置";

    return @{
        @"configured": @(configured),
        @"excluded": @(excluded),
        @"hasAccent": @(hasAccent),
        @"colorCount": @(colorCount),
        @"switchCount": @(switchCount),
        @"text": text
    };
}

- (NSSet<NSString *> *)configuredBundleIDs {
    NSMutableSet<NSString *> *result =
        [NSMutableSet set];

    for (NSString *key in @[
        @"AppColorOverrides",
        @"AppComponentColorOverrides",
        @"AppComponentSwitchOverrides"
    ]) {
        NSDictionary *dict =
            [self dictionaryPreferenceForKey:key];

        for (id rawKey in dict.allKeys) {
            if (![rawKey isKindOfClass:[NSString class]]) {
                continue;
            }

            NSString *bundleID =
                [[(NSString *)rawKey
                  stringByTrimmingCharactersInSet:
                    NSCharacterSet
                        .whitespaceAndNewlineCharacterSet]
                 lowercaseString];

            if (bundleID.length > 0) {
                [result addObject:bundleID];
            }
        }
    }

    [result unionSet:
        [[self excludedBundleIDs] mutableCopy]];

    return [result copy];
}

#pragma mark - Records / search / sorting

- (void)loadApplicationRecordsIfNeeded {
    if (!self.gtApplicationRecords) {
        self.gtApplicationRecords =
            GTInstalledApplicationRecords();
    }
}

- (BOOL)recordMatchesSearch:
    (NSDictionary *)record {

    NSString *query =
        [self.gtSearchQuery
         stringByTrimmingCharactersInSet:
            NSCharacterSet
                .whitespaceAndNewlineCharacterSet];

    if (query.length == 0) {
        return YES;
    }

    NSString *needle =
        query.lowercaseString;

    NSString *name =
        [record[@"name"]
         isKindOfClass:[NSString class]]
        ? [record[@"name"] lowercaseString]
        : @"";

    NSString *bundleID =
        [record[@"bundleID"]
         isKindOfClass:[NSString class]]
        ? [record[@"bundleID"] lowercaseString]
        : @"";

    return
        [name containsString:needle] ||
        [bundleID containsString:needle];
}

- (NSArray<NSDictionary *> *)sortedRecords:
    (NSArray<NSDictionary *> *)records {

    return [records
        sortedArrayUsingComparator:
            ^NSComparisonResult(
                NSDictionary *left,
                NSDictionary *right
            ) {

        NSString *leftBundle =
            [left[@"bundleID"] lowercaseString] ?: @"";

        NSString *rightBundle =
            [right[@"bundleID"] lowercaseString] ?: @"";

        BOOL leftConfigured =
            [[self statusForBundleID:leftBundle]
             [@"configured"] boolValue];

        BOOL rightConfigured =
            [[self statusForBundleID:rightBundle]
             [@"configured"] boolValue];

        if (leftConfigured != rightConfigured) {
            return leftConfigured
                ? NSOrderedAscending
                : NSOrderedDescending;
        }

        NSString *leftName =
            left[@"name"] ?: left[@"bundleID"] ?: @"";

        NSString *rightName =
            right[@"name"] ?: right[@"bundleID"] ?: @"";

        NSComparisonResult nameResult =
            [leftName
             localizedCaseInsensitiveCompare:
                rightName];

        if (nameResult != NSOrderedSame) {
            return nameResult;
        }

        return [leftBundle
            localizedCaseInsensitiveCompare:
                rightBundle];
    }];
}

#pragma mark - Specifiers

- (PSSpecifier *)appSpecifierWithName:
    (NSString *)name
                             bundleID:
    (NSString *)bundleID {

    PSSpecifier *specifier =
        [PSSpecifier
         preferenceSpecifierNamed:name
                        target:self
                           set:nil
                           get:nil
                        detail:
            [GTAppDetailController class]
                          cell:PSLinkCell
                          edit:nil];

    [specifier setProperty:bundleID
                    forKey:@"GTBundleID"];

    [specifier setProperty:name
                    forKey:@"GTAppName"];

    NSDictionary *status =
        [self statusForBundleID:bundleID];

    [specifier setProperty:
        status[@"text"]
        forKey:@"GTStatusText"];

    [specifier setProperty:
        status[@"configured"]
        forKey:@"GTConfigured"];

    return specifier;
}

- (NSMutableArray *)buildSpecifiers {
    [self loadApplicationRecordsIfNeeded];

    NSMutableArray *items =
        [NSMutableArray array];

    PSSpecifier *intro =
        [PSSpecifier
         groupSpecifierWithName:@"APP 配置管理"];

    [intro setProperty:
        @"支持搜索 App 名称或 Bundle ID。已配置 App 会优先排列；右侧状态会显示“已排除 / 主色 / 组件颜色数量 / 组件开关数量”。"
        forKey:@"footerText"];

    [items addObject:intro];

    PSSpecifier *refresh =
        [PSSpecifier
         preferenceSpecifierNamed:@"刷新应用列表"
                        target:self
                           set:nil
                           get:nil
                        detail:nil
                          cell:PSButtonCell
                          edit:nil];

    refresh.buttonAction =
        @selector(refreshApplicationList);

    [items addObject:refresh];

    NSMutableArray<NSDictionary *> *userApps =
        [NSMutableArray array];

    NSMutableArray<NSDictionary *> *systemApps =
        [NSMutableArray array];

    NSMutableSet<NSString *> *listedBundleIDs =
        [NSMutableSet set];

    for (NSDictionary *record
         in self.gtApplicationRecords) {

        if (![self recordMatchesSearch:record]) {
            continue;
        }

        NSString *bundleID =
            [record[@"bundleID"] lowercaseString];

        if (bundleID.length == 0) {
            continue;
        }

        [listedBundleIDs addObject:bundleID];

        if ([record[@"type"]
             isEqualToString:@"system"]) {
            [systemApps addObject:record];
        } else {
            [userApps addObject:record];
        }
    }

    userApps =
        [[self sortedRecords:userApps] mutableCopy];

    systemApps =
        [[self sortedRecords:systemApps] mutableCopy];

    if (userApps.count > 0) {
        PSSpecifier *group =
            [PSSpecifier
             groupSpecifierWithName:@"用户 App"];

        [items addObject:group];

        for (NSDictionary *record in userApps) {
            [items addObject:
                [self
                 appSpecifierWithName:
                    record[@"name"]
                            bundleID:
                    record[@"bundleID"]]];
        }
    }

    if (systemApps.count > 0) {
        PSSpecifier *group =
            [PSSpecifier
             groupSpecifierWithName:@"系统 App"];

        [items addObject:group];

        for (NSDictionary *record in systemApps) {
            [items addObject:
                [self
                 appSpecifierWithName:
                    record[@"name"]
                            bundleID:
                    record[@"bundleID"]]];
        }
    }

    NSMutableArray<NSString *> *missingConfigured =
        [NSMutableArray array];

    for (NSString *bundleID
         in [self configuredBundleIDs]) {

        if ([listedBundleIDs
             containsObject:bundleID]) {
            continue;
        }

        NSDictionary *synthetic = @{
            @"name": bundleID,
            @"bundleID": bundleID,
            @"type": @"user"
        };

        if (![self recordMatchesSearch:synthetic]) {
            continue;
        }

        [missingConfigured addObject:bundleID];
    }

    [missingConfigured
     sortUsingSelector:
        @selector(
            localizedCaseInsensitiveCompare:
        )];

    if (missingConfigured.count > 0) {
        PSSpecifier *group =
            [PSSpecifier
             groupSpecifierWithName:
                @"已配置但未在应用列表中"];

        [group setProperty:
            @"这些 Bundle ID 已存在 GlobalTint 配置，但 LaunchServices 当前没有返回对应 App。仍可进入编辑。"
            forKey:@"footerText"];

        [items addObject:group];

        for (NSString *bundleID
             in missingConfigured) {

            [items addObject:
                [self
                 appSpecifierWithName:bundleID
                             bundleID:bundleID]];
        }
    }

    BOOL searching =
        [self.gtSearchQuery
         stringByTrimmingCharactersInSet:
            NSCharacterSet
                .whitespaceAndNewlineCharacterSet]
        .length > 0;

    if (userApps.count == 0 &&
        systemApps.count == 0 &&
        missingConfigured.count == 0) {

        PSSpecifier *empty =
            [PSSpecifier
             groupSpecifierWithName:
                (searching
                 ? @"没有搜索结果"
                 : @"未读取到应用")];

        [empty setProperty:
            (searching
             ? @"尝试搜索 App 的完整/部分名称，或 Bundle ID。"
             : @"LaunchServices 没有返回应用列表。可以返回 GlobalTint 主页面继续使用手动 Bundle ID 配置。")
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

#pragma mark - Cell decoration

- (PSSpecifier *)gtSpecifierAtIndexPath:
    (NSIndexPath *)indexPath {

    SEL selector =
        NSSelectorFromString(@"specifierAtIndexPath:");

    if (![self respondsToSelector:selector]) {
        return nil;
    }

    return ((id (*)(id, SEL, id))objc_msgSend)(
        self,
        selector,
        indexPath
    );
}

- (UITableViewCell *)tableView:
    (UITableView *)tableView
             cellForRowAtIndexPath:
    (NSIndexPath *)indexPath {

    UITableViewCell *cell =
        [super tableView:tableView
   cellForRowAtIndexPath:indexPath];

    PSSpecifier *specifier =
        [self gtSpecifierAtIndexPath:indexPath];

    NSString *bundleID =
        [specifier propertyForKey:@"GTBundleID"];

    if (![bundleID isKindOfClass:[NSString class]] ||
        bundleID.length == 0) {
        return cell;
    }

    cell.imageView.image =
        GTApplicationIconForBundleIdentifier(
            bundleID
        );

    cell.imageView.layer.cornerRadius = 9.0;
    cell.imageView.layer.masksToBounds = YES;

    NSString *status =
        [specifier propertyForKey:@"GTStatusText"];

    BOOL configured =
        [[specifier propertyForKey:@"GTConfigured"]
         boolValue];

    UIView *oldAccessory =
        cell.accessoryView;

    if ([oldAccessory
         isKindOfClass:[UIView class]] &&
        oldAccessory.tag == 94170) {
        cell.accessoryView = nil;
    }

    UIView *container =
        [[UIView alloc]
         initWithFrame:
            CGRectMake(
                0.0,
                0.0,
                145.0,
                32.0
            )];

    container.tag = 94170;

    UILabel *label =
        [[UILabel alloc]
         initWithFrame:
            CGRectMake(
                0.0,
                0.0,
                126.0,
                32.0
            )];

    label.text = status ?: @"";
    label.font =
        [UIFont systemFontOfSize:11.5
                         weight:
            (configured
             ? UIFontWeightMedium
             : UIFontWeightRegular)];

    label.textColor =
        configured
        ? UIColor.secondaryLabelColor
        : UIColor.tertiaryLabelColor;

    label.textAlignment =
        NSTextAlignmentRight;

    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.72;

    [container addSubview:label];

    UIImageView *chevron =
        [[UIImageView alloc]
         initWithImage:
            [UIImage
             systemImageNamed:@"chevron.right"]];

    chevron.frame =
        CGRectMake(
            132.0,
            9.0,
            8.0,
            14.0
        );

    chevron.contentMode =
        UIViewContentModeScaleAspectFit;

    chevron.tintColor =
        UIColor.tertiaryLabelColor;

    [container addSubview:chevron];

    cell.accessoryType =
        UITableViewCellAccessoryNone;

    cell.accessoryView = container;

    return cell;
}

#pragma mark - Search

- (void)viewDidLoad {
    [super viewDidLoad];

    self.gtSearchController =
        [[UISearchController alloc]
         initWithSearchResultsController:nil];

    self.gtSearchController
        .searchResultsUpdater = self;

    self.gtSearchController
        .obscuresBackgroundDuringPresentation = NO;

    self.gtSearchController.searchBar.placeholder =
        @"搜索 App 或 Bundle ID";

    self.navigationItem.searchController =
        self.gtSearchController;

    self.navigationItem
        .hidesSearchBarWhenScrolling = NO;

    self.definesPresentationContext = YES;
}

- (void)updateSearchResultsForSearchController:
    (UISearchController *)searchController {

    NSString *query =
        searchController.searchBar.text ?: @"";

    if ([query isEqualToString:
        (self.gtSearchQuery ?: @"")]) {
        return;
    }

    self.gtSearchQuery = query;
    _specifiers = nil;
    [self reloadSpecifiers];
}

#pragma mark - Actions

- (void)refreshApplicationList {
    self.gtApplicationRecords = nil;
    _specifiers = nil;

    [self loadApplicationRecordsIfNeeded];
    [self reloadSpecifiers];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    self.title = @"App 配置管理";

    if (_specifiers) {
        _specifiers = nil;
        [self reloadSpecifiers];
    }
}

@end
