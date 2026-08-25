#import "GTAppDetailController.h"
#import "GTAppIcon.h"

#import <Cephei/HBPreferences.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>

static NSString * const GTPrefsIdentifier =
    @"com.benja.globaltint";

static CFStringRef const GTReloadNotification =
    CFSTR("com.benja.globaltint/ReloadPrefs");

static UIColor *GTDetailColorFromHex(NSString *hex) {
    if (![hex isKindOfClass:[NSString class]]) {
        hex = @"#0A84FF";
    }

    NSString *clean =
        [[[hex stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]]
          stringByReplacingOccurrencesOfString:@"#"
                                    withString:@""]
         uppercaseString];

    if (clean.length == 3) {
        unichar r = [clean characterAtIndex:0];
        unichar g = [clean characterAtIndex:1];
        unichar b = [clean characterAtIndex:2];

        clean =
            [NSString stringWithFormat:
                @"%C%C%C%C%C%C",
                r, r, g, g, b, b];
    }

    if (clean.length != 6) {
        clean = @"0A84FF";
    }

    unsigned long long value = 0;

    if (![[NSScanner scannerWithString:clean]
          scanHexLongLong:&value]) {
        value = 0x0A84FF;
    }

    return [UIColor
        colorWithRed:
            ((value >> 16) & 0xFF) / 255.0
              green:
            ((value >> 8) & 0xFF) / 255.0
               blue:
            (value & 0xFF) / 255.0
              alpha:1.0];
}

static NSString *GTDetailHexFromColor(UIColor *color) {
    CGFloat red = 0.0;
    CGFloat green = 0.0;
    CGFloat blue = 0.0;
    CGFloat alpha = 0.0;

    if (![color getRed:&red
                 green:&green
                  blue:&blue
                 alpha:&alpha]) {
        red = 10.0 / 255.0;
        green = 132.0 / 255.0;
        blue = 1.0;
    }

    NSInteger r =
        (NSInteger)llround(
            MAX(0.0, MIN(1.0, red)) * 255.0);

    NSInteger g =
        (NSInteger)llround(
            MAX(0.0, MIN(1.0, green)) * 255.0);

    NSInteger b =
        (NSInteger)llround(
            MAX(0.0, MIN(1.0, blue)) * 255.0);

    return [NSString stringWithFormat:
        @"#%02lX%02lX%02lX",
        (long)r,
        (long)g,
        (long)b];
}

@interface GTAppDetailController ()
@property (nonatomic, copy) NSString *gtBundleID;
@property (nonatomic, copy) NSString *gtAppName;
@property (nonatomic, copy) NSString *gtPendingComponentColorKey;
@end

@implementation GTAppDetailController

#pragma mark - Lifecycle

- (void)setSpecifier:(PSSpecifier *)specifier {
    [super setSpecifier:specifier];

    NSString *bundleID =
        [specifier propertyForKey:@"GTBundleID"];

    NSString *appName =
        [specifier propertyForKey:@"GTAppName"];

    self.gtBundleID =
        [bundleID isKindOfClass:[NSString class]]
        ? bundleID.lowercaseString
        : @"";

    self.gtAppName =
        ([appName isKindOfClass:[NSString class]] &&
         appName.length > 0)
        ? appName
        : self.gtBundleID;

    self.title = self.gtAppName;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    self.title =
        self.gtAppName.length > 0
        ? self.gtAppName
        : @"App 配置";

    if (_specifiers) {
        [self reloadSpecifiers];
    }
}

#pragma mark - Preferences

- (HBPreferences *)preferences {
    return [[HBPreferences alloc]
            initWithIdentifier:GTPrefsIdentifier];
}

- (void)postReloadNotification {
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        GTReloadNotification,
        NULL,
        NULL,
        YES
    );
}

- (NSDictionary *)dictionaryForKey:(NSString *)key {
    id value =
        [[self preferences] objectForKey:key];

    if (![value isKindOfClass:[NSDictionary class]]) {
        return @{};
    }

    return value;
}

- (NSString *)globalAccentHex {
    id value =
        [[self preferences] objectForKey:@"AccentColor"];

    if ([value isKindOfClass:[NSString class]] &&
        [(NSString *)value length] > 0) {
        return [(NSString *)value uppercaseString];
    }

    return @"#0A84FF";
}

#pragma mark - Exclusion

- (NSMutableOrderedSet<NSString *> *)excludedBundleSet {
    id value =
        [[self preferences] objectForKey:@"ExcludedBundleIDs"];

    NSMutableOrderedSet<NSString *> *result =
        [NSMutableOrderedSet orderedSet];

    if (![value isKindOfClass:[NSString class]]) {
        return result;
    }

    for (NSString *part in
         [(NSString *)value componentsSeparatedByString:@","]) {

        NSString *bundleID =
            [[part
              stringByTrimmingCharactersInSet:
                [NSCharacterSet
                 whitespaceAndNewlineCharacterSet]]
             lowercaseString];

        if (bundleID.length > 0) {
            [result addObject:bundleID];
        }
    }

    return result;
}

- (id)appExcludedValue:(PSSpecifier *)specifier {
    return @([[self excludedBundleSet]
              containsObject:self.gtBundleID]);
}

- (void)setAppExcludedValue:(id)value
                  specifier:(PSSpecifier *)specifier {

    if (self.gtBundleID.length == 0) {
        return;
    }

    NSMutableOrderedSet<NSString *> *excluded =
        [self excludedBundleSet];

    if ([value boolValue]) {
        [excluded addObject:self.gtBundleID];
    } else {
        [excluded removeObject:self.gtBundleID];
    }

    NSArray<NSString *> *sorted =
        [[excluded array]
         sortedArrayUsingSelector:
            @selector(localizedCaseInsensitiveCompare:)];

    NSString *serialized =
        [sorted componentsJoinedByString:@", "];

    HBPreferences *preferences =
        [self preferences];

    if (serialized.length > 0) {
        [preferences setObject:serialized
                        forKey:@"ExcludedBundleIDs"];
    } else {
        [preferences removeObjectForKey:@"ExcludedBundleIDs"];
    }

    [self postReloadNotification];
}

#pragma mark - App accent

- (NSString *)appAccentHex {
    NSDictionary *profiles =
        [self dictionaryForKey:@"AppColorOverrides"];

    id value = profiles[self.gtBundleID];

    if ([value isKindOfClass:[NSString class]] &&
        [(NSString *)value length] > 0) {
        return [(NSString *)value uppercaseString];
    }

    return nil;
}

- (PSSpecifier *)appAccentButton {
    NSString *value =
        [self appAccentHex] ?: @"跟随全局";

    PSSpecifier *button =
        [PSSpecifier
         preferenceSpecifierNamed:
            [NSString stringWithFormat:
                @"App 主色 · %@", value]
                        target:self
                           set:nil
                           get:nil
                        detail:nil
                          cell:PSButtonCell
                          edit:nil];

    button.buttonAction =
        @selector(chooseAppAccent);

    return button;
}

- (void)chooseAppAccent {
    self.gtPendingComponentColorKey = nil;

    NSString *initial =
        [self appAccentHex] ?: [self globalAccentHex];

    UIColorPickerViewController *picker =
        [[UIColorPickerViewController alloc] init];

    picker.delegate = self;
    picker.supportsAlpha = NO;
    picker.title = @"App 主色";
    picker.selectedColor =
        GTDetailColorFromHex(initial);

    [self presentViewController:picker
                       animated:YES
                     completion:nil];
}

- (void)clearAppAccent {
    HBPreferences *preferences =
        [self preferences];

    NSDictionary *stored =
        [preferences objectForKey:@"AppColorOverrides"];

    NSMutableDictionary *profiles =
        [stored isKindOfClass:[NSDictionary class]]
        ? [stored mutableCopy]
        : [NSMutableDictionary dictionary];

    [profiles removeObjectForKey:self.gtBundleID];

    [preferences setObject:[profiles copy]
                    forKey:@"AppColorOverrides"];

    [self postReloadNotification];
    [self reloadSpecifiers];
}

#pragma mark - Component colors

- (NSDictionary *)componentColorRules {
    NSDictionary *all =
        [self dictionaryForKey:
            @"AppComponentColorOverrides"];

    id rules = all[self.gtBundleID];

    if (![rules isKindOfClass:[NSDictionary class]]) {
        return @{};
    }

    return rules;
}

- (NSString *)componentColorTextForKey:(NSString *)key {
    id value =
        [self componentColorRules][key];

    if ([value isKindOfClass:[NSString class]] &&
        [(NSString *)value length] > 0) {
        return [(NSString *)value uppercaseString];
    }

    return @"跟随全局组件颜色";
}

- (PSSpecifier *)componentColorButtonForKey:(NSString *)key
                                      name:(NSString *)name
                                    action:(SEL)action {

    NSString *value =
        [self componentColorTextForKey:key];

    PSSpecifier *button =
        [PSSpecifier
         preferenceSpecifierNamed:
            [NSString stringWithFormat:
                @"%@ · %@", name, value]
                        target:self
                           set:nil
                           get:nil
                        detail:nil
                          cell:PSButtonCell
                          edit:nil];

    button.buttonAction = action;
    return button;
}

- (void)presentComponentColorPickerForKey:(NSString *)key
                                     name:(NSString *)name {

    self.gtPendingComponentColorKey = key;

    id current =
        [self componentColorRules][key];

    NSString *initial = nil;

    if ([current isKindOfClass:[NSString class]] &&
        [(NSString *)current length] > 0) {
        initial = current;
    }

    if (initial.length == 0) {
        initial =
            [self appAccentHex] ?: [self globalAccentHex];
    }

    UIColorPickerViewController *picker =
        [[UIColorPickerViewController alloc] init];

    picker.delegate = self;
    picker.supportsAlpha = NO;
    picker.title = name;
    picker.selectedColor =
        GTDetailColorFromHex(initial);

    [self presentViewController:picker
                       animated:YES
                     completion:nil];
}

- (void)chooseWindowColor {
    [self presentComponentColorPickerForKey:@"WindowColor"
                                       name:@"应用整体强调色"];
}

- (void)chooseSwitchColor {
    [self presentComponentColorPickerForKey:@"SwitchColor"
                                       name:@"开关按钮"];
}

- (void)chooseSliderColor {
    [self presentComponentColorPickerForKey:@"SliderColor"
                                       name:@"滑动条 / 音量进度条"];
}

- (void)chooseProgressColor {
    [self presentComponentColorPickerForKey:@"ProgressColor"
                                       name:@"进度条"];
}

- (void)chooseSegmentedColor {
    [self presentComponentColorPickerForKey:@"SegmentedColor"
                                       name:@"分段选择按钮"];
}

- (void)choosePageControlColor {
    [self presentComponentColorPickerForKey:@"PageControlColor"
                                       name:@"页面圆点指示器"];
}

- (void)chooseRefreshControlColor {
    [self presentComponentColorPickerForKey:@"RefreshControlColor"
                                       name:@"下拉刷新指示器"];
}

- (void)chooseNavigationBarColor {
    [self presentComponentColorPickerForKey:@"NavigationBarColor"
                                       name:@"顶部导航栏"];
}

- (void)chooseTabBarColor {
    [self presentComponentColorPickerForKey:@"TabBarColor"
                                       name:@"底部标签栏"];
}

- (void)chooseToolbarColor {
    [self presentComponentColorPickerForKey:@"ToolbarColor"
                                       name:@"工具栏"];
}

- (void)chooseSearchBarColor {
    [self presentComponentColorPickerForKey:@"SearchBarColor"
                                       name:@"搜索栏"];
}


- (void)clearAllComponentColors {
    HBPreferences *preferences =
        [self preferences];

    NSDictionary *stored =
        [preferences objectForKey:
            @"AppComponentColorOverrides"];

    NSMutableDictionary *all =
        [stored isKindOfClass:[NSDictionary class]]
        ? [stored mutableCopy]
        : [NSMutableDictionary dictionary];

    [all removeObjectForKey:self.gtBundleID];

    [preferences setObject:[all copy]
                    forKey:@"AppComponentColorOverrides"];

    [self postReloadNotification];
    [self reloadSpecifiers];
}

#pragma mark - Component switches

- (NSDictionary *)componentSwitchRules {
    NSDictionary *all =
        [self dictionaryForKey:
            @"AppComponentSwitchOverrides"];

    id rules = all[self.gtBundleID];

    if (![rules isKindOfClass:[NSDictionary class]]) {
        return @{};
    }

    return rules;
}

- (NSString *)componentSwitchTextForKey:(NSString *)key {
    id value =
        [self componentSwitchRules][key];

    if (![value respondsToSelector:@selector(boolValue)]) {
        return @"跟随全局";
    }

    return [value boolValue]
        ? @"强制开启"
        : @"强制关闭";
}

- (PSSpecifier *)componentSwitchButtonForKey:(NSString *)key
                                       name:(NSString *)name
                                     action:(SEL)action {

    NSString *value =
        [self componentSwitchTextForKey:key];

    PSSpecifier *button =
        [PSSpecifier
         preferenceSpecifierNamed:
            [NSString stringWithFormat:
                @"%@ · %@", name, value]
                        target:self
                           set:nil
                           get:nil
                        detail:nil
                          cell:PSButtonCell
                          edit:nil];

    button.buttonAction = action;
    return button;
}

- (void)setComponentSwitchRuleForKey:(NSString *)key
                               value:(NSNumber *)value {

    HBPreferences *preferences =
        [self preferences];

    NSDictionary *stored =
        [preferences objectForKey:
            @"AppComponentSwitchOverrides"];

    NSMutableDictionary *all =
        [stored isKindOfClass:[NSDictionary class]]
        ? [stored mutableCopy]
        : [NSMutableDictionary dictionary];

    NSDictionary *existing =
        [all[self.gtBundleID]
         isKindOfClass:[NSDictionary class]]
        ? all[self.gtBundleID]
        : @{};

    NSMutableDictionary *rules =
        [existing mutableCopy];

    if (value) {
        rules[key] = @([value boolValue]);
    } else {
        [rules removeObjectForKey:key];
    }

    if (rules.count == 0) {
        [all removeObjectForKey:self.gtBundleID];
    } else {
        all[self.gtBundleID] = [rules copy];
    }

    [preferences setObject:[all copy]
                    forKey:@"AppComponentSwitchOverrides"];

    [self postReloadNotification];
    [self reloadSpecifiers];
}

- (void)presentComponentSwitchChoiceForKey:(NSString *)key
                                      name:(NSString *)name {

    UIAlertController *sheet =
        [UIAlertController
         alertControllerWithTitle:name
                          message:self.gtBundleID
                   preferredStyle:
                        UIAlertControllerStyleActionSheet];

    __weak typeof(self) weakSelf = self;

    [sheet addAction:
        [UIAlertAction
         actionWithTitle:@"强制开启"
                   style:UIAlertActionStyleDefault
                 handler:
            ^(__unused UIAlertAction *action) {
        [weakSelf setComponentSwitchRuleForKey:key
                                         value:@YES];
    }]];

    [sheet addAction:
        [UIAlertAction
         actionWithTitle:@"强制关闭"
                   style:UIAlertActionStyleDestructive
                 handler:
            ^(__unused UIAlertAction *action) {
        [weakSelf setComponentSwitchRuleForKey:key
                                         value:@NO];
    }]];

    [sheet addAction:
        [UIAlertAction
         actionWithTitle:@"跟随全局"
                   style:UIAlertActionStyleDefault
                 handler:
            ^(__unused UIAlertAction *action) {
        [weakSelf setComponentSwitchRuleForKey:key
                                         value:nil];
    }]];

    [sheet addAction:
        [UIAlertAction
         actionWithTitle:@"取消"
                   style:UIAlertActionStyleCancel
                 handler:nil]];

    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView =
            self.view;

        sheet.popoverPresentationController.sourceRect =
            CGRectMake(
                CGRectGetMidX(self.view.bounds),
                CGRectGetMidY(self.view.bounds),
                1.0,
                1.0
            );
    }

    [self presentViewController:sheet
                       animated:YES
                     completion:nil];
}

- (void)chooseWindowSwitch {
    [self presentComponentSwitchChoiceForKey:@"应用整体强调色"
                                        name:@"应用整体强调色"];
}

- (void)chooseSwitchSwitch {
    [self presentComponentSwitchChoiceForKey:@"开关按钮"
                                        name:@"开关按钮"];
}

- (void)chooseSliderSwitch {
    [self presentComponentSwitchChoiceForKey:@"滑动条 / 音量进度条"
                                        name:@"滑动条 / 音量进度条"];
}

- (void)chooseProgressSwitch {
    [self presentComponentSwitchChoiceForKey:@"进度条"
                                        name:@"进度条"];
}

- (void)chooseSegmentedSwitch {
    [self presentComponentSwitchChoiceForKey:@"Segmented"
                                        name:@"分段选择按钮"];
}

- (void)choosePageControlSwitch {
    [self presentComponentSwitchChoiceForKey:@"页面圆点指示器"
                                        name:@"页面圆点指示器"];
}

- (void)chooseRefreshControlSwitch {
    [self presentComponentSwitchChoiceForKey:@"下拉刷新指示器"
                                        name:@"下拉刷新指示器"];
}

- (void)chooseNavigationBarSwitch {
    [self presentComponentSwitchChoiceForKey:@"顶部导航栏"
                                        name:@"顶部导航栏"];
}

- (void)chooseTabBarSwitch {
    [self presentComponentSwitchChoiceForKey:@"底部标签栏"
                                        name:@"底部标签栏"];
}

- (void)chooseToolbarSwitch {
    [self presentComponentSwitchChoiceForKey:@"工具栏"
                                        name:@"工具栏"];
}

- (void)chooseSearchBarSwitch {
    [self presentComponentSwitchChoiceForKey:@"搜索栏"
                                        name:@"搜索栏"];
}


- (void)clearAllComponentSwitches {
    HBPreferences *preferences =
        [self preferences];

    NSDictionary *stored =
        [preferences objectForKey:
            @"AppComponentSwitchOverrides"];

    NSMutableDictionary *all =
        [stored isKindOfClass:[NSDictionary class]]
        ? [stored mutableCopy]
        : [NSMutableDictionary dictionary];

    [all removeObjectForKey:self.gtBundleID];

    [preferences setObject:[all copy]
                    forKey:@"AppComponentSwitchOverrides"];

    [self postReloadNotification];
    [self reloadSpecifiers];
}

#pragma mark - Reset App

- (void)resetThisApp {
    UIAlertController *alert =
        [UIAlertController
         alertControllerWithTitle:@"恢复此 App 为全局配置"
                          message:
            @"将删除此 App 的主色、组件颜色、组件开关和排除状态。"
                   preferredStyle:
            UIAlertControllerStyleAlert];

    [alert addAction:
        [UIAlertAction
         actionWithTitle:@"取消"
                   style:UIAlertActionStyleCancel
                 handler:nil]];

    __weak typeof(self) weakSelf = self;

    [alert addAction:
        [UIAlertAction
         actionWithTitle:@"恢复"
                   style:UIAlertActionStyleDestructive
                 handler:
            ^(__unused UIAlertAction *action) {

        HBPreferences *preferences =
            [weakSelf preferences];

        for (NSString *key in @[
            @"AppColorOverrides",
            @"AppComponentColorOverrides",
            @"AppComponentSwitchOverrides"
        ]) {
            id stored =
                [preferences objectForKey:key];

            NSMutableDictionary *dict =
                [stored isKindOfClass:[NSDictionary class]]
                ? [stored mutableCopy]
                : [NSMutableDictionary dictionary];

            [dict removeObjectForKey:
                weakSelf.gtBundleID];

            [preferences setObject:[dict copy]
                            forKey:key];
        }

        NSMutableOrderedSet *excluded =
            [weakSelf excludedBundleSet];

        [excluded removeObject:
            weakSelf.gtBundleID];

        NSArray *sorted =
            [[excluded array]
             sortedArrayUsingSelector:
                @selector(localizedCaseInsensitiveCompare:)];

        NSString *serialized =
            [sorted componentsJoinedByString:@", "];

        if (serialized.length > 0) {
            [preferences setObject:serialized
                            forKey:@"ExcludedBundleIDs"];
        } else {
            [preferences
             removeObjectForKey:@"ExcludedBundleIDs"];
        }

        [weakSelf postReloadNotification];
        [weakSelf reloadSpecifiers];
    }]];

    [self presentViewController:alert
                       animated:YES
                     completion:nil];
}

#pragma mark - UIColorPickerViewControllerDelegate

- (void)colorPickerViewControllerDidSelectColor:
    (UIColorPickerViewController *)viewController
        API_AVAILABLE(ios(14.0)) {

    if (self.gtBundleID.length == 0) {
        return;
    }

    NSString *hex =
        GTDetailHexFromColor(
            viewController.selectedColor
        );

    HBPreferences *preferences =
        [self preferences];

    if (self.gtPendingComponentColorKey.length > 0) {
        NSDictionary *stored =
            [preferences objectForKey:
                @"AppComponentColorOverrides"];

        NSMutableDictionary *all =
            [stored isKindOfClass:[NSDictionary class]]
            ? [stored mutableCopy]
            : [NSMutableDictionary dictionary];

        NSDictionary *existing =
            [all[self.gtBundleID]
             isKindOfClass:[NSDictionary class]]
            ? all[self.gtBundleID]
            : @{};

        NSMutableDictionary *rules =
            [existing mutableCopy];

        rules[self.gtPendingComponentColorKey] = hex;
        all[self.gtBundleID] = [rules copy];

        [preferences setObject:[all copy]
                        forKey:@"AppComponentColorOverrides"];
    } else {
        NSDictionary *stored =
            [preferences objectForKey:
                @"AppColorOverrides"];

        NSMutableDictionary *profiles =
            [stored isKindOfClass:[NSDictionary class]]
            ? [stored mutableCopy]
            : [NSMutableDictionary dictionary];

        profiles[self.gtBundleID] = hex;

        [preferences setObject:[profiles copy]
                        forKey:@"AppColorOverrides"];
    }

    [self postReloadNotification];
}

- (void)colorPickerViewControllerDidFinish:
    (UIColorPickerViewController *)viewController
        API_AVAILABLE(ios(14.0)) {

    self.gtPendingComponentColorKey = nil;
    [self reloadSpecifiers];
}

#pragma mark - Specifiers

- (NSMutableArray *)buildSpecifiers {
    NSMutableArray *items =
        [NSMutableArray array];

    PSSpecifier *appGroup =
        [PSSpecifier
         groupSpecifierWithName:
            (self.gtAppName.length > 0
             ? self.gtAppName
             : @"App")];

    [appGroup setProperty:
        [NSString stringWithFormat:
            @"Bundle ID：%@",
            self.gtBundleID ?: @""]
        forKey:@"footerText"];

    [items addObject:appGroup];

    PSSpecifier *appHeader =
        [PSSpecifier
         preferenceSpecifierNamed:
            (self.gtAppName.length > 0
             ? self.gtAppName
             : self.gtBundleID)
                        target:nil
                           set:nil
                           get:nil
                        detail:nil
                          cell:PSTitleValueCell
                          edit:nil];

    [appHeader setProperty:@YES
                    forKey:@"GTAppHeader"];

    [appHeader setProperty:self.gtBundleID ?: @""
                    forKey:@"GTBundleID"];

    [items addObject:appHeader];

    PSSpecifier *excluded =
        [PSSpecifier
         preferenceSpecifierNamed:@"排除此 App"
                        target:self
                           set:@selector(setAppExcludedValue:specifier:)
                           get:@selector(appExcludedValue:)
                        detail:nil
                          cell:PSSwitchCell
                          edit:nil];

    [items addObject:excluded];

    PSSpecifier *accentGroup =
        [PSSpecifier groupSpecifierWithName:@"App 主色"];

    [accentGroup setProperty:
        @"未单独设置时，使用全局主主题色。"
        forKey:@"footerText"];

    [items addObject:accentGroup];
    [items addObject:[self appAccentButton]];

    PSSpecifier *clearAccent =
        [PSSpecifier
         preferenceSpecifierNamed:@"清除 App 主色"
                        target:self
                           set:nil
                           get:nil
                        detail:nil
                          cell:PSButtonCell
                          edit:nil];

    clearAccent.buttonAction =
        @selector(clearAppAccent);

    [items addObject:clearAccent];

    PSSpecifier *colorGroup =
        [PSSpecifier
         groupSpecifierWithName:@"App 独立界面颜色"];

    [colorGroup setProperty:
        @"需要主页面开启“启用组件独立颜色”。没有单独设置的项目，会依次使用：全局对应颜色 → 此 App 主色 → 全局主色。"
        forKey:@"footerText"];

    [items addObject:colorGroup];

    [items addObject:
        [self componentColorButtonForKey:@"WindowColor"
                                    name:@"应用整体强调色"
                                  action:@selector(chooseWindowColor)]];

    [items addObject:
        [self componentColorButtonForKey:@"SwitchColor"
                                    name:@"开关按钮"
                                  action:@selector(chooseSwitchColor)]];

    [items addObject:
        [self componentColorButtonForKey:@"SliderColor"
                                    name:@"滑动条 / 音量进度条"
                                  action:@selector(chooseSliderColor)]];

    [items addObject:
        [self componentColorButtonForKey:@"ProgressColor"
                                    name:@"进度条"
                                  action:@selector(chooseProgressColor)]];

    [items addObject:
        [self componentColorButtonForKey:@"SegmentedColor"
                                    name:@"分段选择按钮"
                                  action:@selector(chooseSegmentedColor)]];

    [items addObject:
        [self componentColorButtonForKey:@"PageControlColor"
                                    name:@"页面圆点指示器"
                                  action:@selector(choosePageControlColor)]];

    [items addObject:
        [self componentColorButtonForKey:@"RefreshControlColor"
                                    name:@"下拉刷新指示器"
                                  action:@selector(chooseRefreshControlColor)]];

    [items addObject:
        [self componentColorButtonForKey:@"NavigationBarColor"
                                    name:@"顶部导航栏"
                                  action:@selector(chooseNavigationBarColor)]];

    [items addObject:
        [self componentColorButtonForKey:@"TabBarColor"
                                    name:@"底部标签栏"
                                  action:@selector(chooseTabBarColor)]];

    [items addObject:
        [self componentColorButtonForKey:@"ToolbarColor"
                                    name:@"工具栏"
                                  action:@selector(chooseToolbarColor)]];

    [items addObject:
        [self componentColorButtonForKey:@"SearchBarColor"
                                    name:@"搜索栏"
                                  action:@selector(chooseSearchBarColor)]];


    PSSpecifier *clearColors =
        [PSSpecifier
         preferenceSpecifierNamed:
            @"清除此 App 全部界面颜色"
                        target:self
                           set:nil
                           get:nil
                        detail:nil
                          cell:PSButtonCell
                          edit:nil];

    clearColors.buttonAction =
        @selector(clearAllComponentColors);

    [items addObject:clearColors];

    PSSpecifier *switchGroup =
        [PSSpecifier
         groupSpecifierWithName:@"App 独立界面开关"];

    [switchGroup setProperty:
        @"每一项都可以设为“强制开启”“强制关闭”或“跟随全局”。主页面中的“标准控件总开关”和“导航栏/工具栏总开关”仍然是总开关。"
        forKey:@"footerText"];

    [items addObject:switchGroup];

    [items addObject:
        [self componentSwitchButtonForKey:@"应用整体强调色"
                                     name:@"应用整体强调色"
                                   action:@selector(chooseWindowSwitch)]];

    [items addObject:
        [self componentSwitchButtonForKey:@"开关按钮"
                                     name:@"开关按钮"
                                   action:@selector(chooseSwitchSwitch)]];

    [items addObject:
        [self componentSwitchButtonForKey:@"滑动条 / 音量进度条"
                                     name:@"滑动条 / 音量进度条"
                                   action:@selector(chooseSliderSwitch)]];

    [items addObject:
        [self componentSwitchButtonForKey:@"进度条"
                                     name:@"进度条"
                                   action:@selector(chooseProgressSwitch)]];

    [items addObject:
        [self componentSwitchButtonForKey:@"Segmented"
                                     name:@"分段选择按钮"
                                   action:@selector(chooseSegmentedSwitch)]];

    [items addObject:
        [self componentSwitchButtonForKey:@"页面圆点指示器"
                                     name:@"页面圆点指示器"
                                   action:@selector(choosePageControlSwitch)]];

    [items addObject:
        [self componentSwitchButtonForKey:@"下拉刷新指示器"
                                     name:@"下拉刷新指示器"
                                   action:@selector(chooseRefreshControlSwitch)]];

    [items addObject:
        [self componentSwitchButtonForKey:@"顶部导航栏"
                                     name:@"顶部导航栏"
                                   action:@selector(chooseNavigationBarSwitch)]];

    [items addObject:
        [self componentSwitchButtonForKey:@"底部标签栏"
                                     name:@"底部标签栏"
                                   action:@selector(chooseTabBarSwitch)]];

    [items addObject:
        [self componentSwitchButtonForKey:@"工具栏"
                                     name:@"工具栏"
                                   action:@selector(chooseToolbarSwitch)]];

    [items addObject:
        [self componentSwitchButtonForKey:@"搜索栏"
                                     name:@"搜索栏"
                                   action:@selector(chooseSearchBarSwitch)]];


    PSSpecifier *clearSwitches =
        [PSSpecifier
         preferenceSpecifierNamed:
            @"清除此 App 全部界面开关"
                        target:self
                           set:nil
                           get:nil
                        detail:nil
                          cell:PSButtonCell
                          edit:nil];

    clearSwitches.buttonAction =
        @selector(clearAllComponentSwitches);

    [items addObject:clearSwitches];

    PSSpecifier *resetGroup =
        [PSSpecifier
         groupSpecifierWithName:@"恢复"];

    [items addObject:resetGroup];

    PSSpecifier *reset =
        [PSSpecifier
         preferenceSpecifierNamed:
            @"恢复此 App 为全局配置"
                        target:self
                           set:nil
                           get:nil
                        detail:nil
                          cell:PSButtonCell
                          edit:nil];

    reset.buttonAction =
        @selector(resetThisApp);

    [items addObject:reset];

    return items;
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers =
            [self buildSpecifiers];
    }

    return _specifiers;
}

#pragma mark - App header cell

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

    if (![[specifier propertyForKey:@"GTAppHeader"]
          boolValue]) {
        return cell;
    }

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

    cell.imageView.layer.cornerRadius = 10.0;
    cell.imageView.layer.masksToBounds = YES;

    cell.selectionStyle =
        UITableViewCellSelectionStyleNone;

    cell.accessoryType =
        UITableViewCellAccessoryNone;

    return cell;
}

@end
