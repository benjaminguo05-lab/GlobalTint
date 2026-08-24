#import "GTListController.h"

#import <Cephei/HBPreferences.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>

static NSString * const GTPrefsIdentifier = @"com.benja.globaltint";
static CFStringRef const GTReloadNotification =
    CFSTR("com.benja.globaltint/ReloadPrefs");

@interface GTListController ()
@property (nonatomic, copy) NSString *gtPendingColorKey;
@property (nonatomic, copy) NSString *gtPendingColorDefault;
@end

static UIColor *GTColorFromHexString(NSString *hex) {
    if (![hex isKindOfClass:[NSString class]]) {
        hex = @"#0A84FF";
    }

    NSString *clean =
        [[[hex stringByTrimmingCharactersInSet:
           [NSCharacterSet whitespaceAndNewlineCharacterSet]]
           stringByReplacingOccurrencesOfString:@"#" withString:@""]
           uppercaseString];

    if (clean.length == 3) {
        unichar r = [clean characterAtIndex:0];
        unichar g = [clean characterAtIndex:1];
        unichar b = [clean characterAtIndex:2];
        clean = [NSString stringWithFormat:@"%C%C%C%C%C%C", r, r, g, g, b, b];
    }

    if (clean.length != 6) {
        clean = @"0A84FF";
    }

    unsigned long long value = 0;
    if (![[NSScanner scannerWithString:clean] scanHexLongLong:&value]) {
        value = 0x0A84FF;
    }

    return [UIColor colorWithRed:((value >> 16) & 0xFF) / 255.0
                           green:((value >> 8) & 0xFF) / 255.0
                            blue:(value & 0xFF) / 255.0
                           alpha:1.0];
}

static NSString *GTHexStringFromColor(UIColor *color) {
    CGFloat r = 0.0;
    CGFloat g = 0.0;
    CGFloat b = 0.0;
    CGFloat a = 0.0;

    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        r = 10.0 / 255.0;
        g = 132.0 / 255.0;
        b = 1.0;
    }

    NSInteger red =
        (NSInteger)llround(MAX(0.0, MIN(1.0, r)) * 255.0);
    NSInteger green =
        (NSInteger)llround(MAX(0.0, MIN(1.0, g)) * 255.0);
    NSInteger blue =
        (NSInteger)llround(MAX(0.0, MIN(1.0, b)) * 255.0);

    return [NSString stringWithFormat:@"#%02lX%02lX%02lX",
            (long)red,
            (long)green,
            (long)blue];
}

@implementation GTListController

#pragma mark - Preferences basics

- (HBPreferences *)preferences {
    return [[HBPreferences alloc] initWithIdentifier:GTPrefsIdentifier];
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

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    id defaultValue = [specifier propertyForKey:@"default"];

    if (key.length == 0) {
        return defaultValue;
    }

    id value = [[self preferences] objectForKey:key];
    return value ?: defaultValue;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];

    if (key.length == 0) {
        return;
    }

    HBPreferences *preferences = [self preferences];

    if (value) {
        [preferences setObject:value forKey:key];
    } else {
        [preferences removeObjectForKey:key];
    }

    [self postReloadNotification];
}

#pragma mark - Specifier builders

- (PSSpecifier *)switchSpecifierWithName:(NSString *)name
                                     key:(NSString *)key
                            defaultValue:(BOOL)defaultValue {

    PSSpecifier *specifier =
        [PSSpecifier preferenceSpecifierNamed:name
                                       target:self
                                          set:@selector(setPreferenceValue:specifier:)
                                          get:@selector(readPreferenceValue:)
                                       detail:nil
                                         cell:PSSwitchCell
                                         edit:nil];

    [specifier setProperty:key forKey:@"key"];
    [specifier setProperty:@(defaultValue) forKey:@"default"];

    return specifier;
}

- (NSString *)storedColorTextForKey:(NSString *)key
                       defaultValue:(NSString *)defaultValue
                      allowInherit:(BOOL)allowInherit {

    id value = [[self preferences] objectForKey:key];

    if ([value isKindOfClass:[NSString class]] &&
        [(NSString *)value length] > 0) {
        return [(NSString *)value uppercaseString];
    }

    if (allowInherit) {
        return @"跟随主色";
    }

    return defaultValue;
}

- (PSSpecifier *)colorButtonWithName:(NSString *)name
                                 key:(NSString *)key
                        defaultValue:(NSString *)defaultValue
                       allowInherit:(BOOL)allowInherit
                              action:(SEL)action {

    NSString *value =
        [self storedColorTextForKey:key
                       defaultValue:defaultValue
                      allowInherit:allowInherit];

    PSSpecifier *button =
        [PSSpecifier preferenceSpecifierNamed:
            [NSString stringWithFormat:@"%@ · %@", name, value]
                                       target:self
                                          set:nil
                                          get:nil
                                       detail:nil
                                         cell:PSButtonCell
                                         edit:nil];

    button.buttonAction = action;
    return button;
}

- (NSMutableArray *)buildSpecifiers {
    NSMutableArray *items = [NSMutableArray array];

    // General
    PSSpecifier *general =
        [PSSpecifier groupSpecifierWithName:@"GLOBAL TINT"];
    [general setProperty:
        @"V0.2：支持 App 排除、组件独立开关和组件独立颜色。"
        forKey:@"footerText"];
    [items addObject:general];

    [items addObject:
        [self switchSpecifierWithName:@"启用 Global Tint"
                                  key:@"Enabled"
                         defaultValue:YES]];

    [items addObject:
        [self colorButtonWithName:@"主主题色"
                              key:@"AccentColor"
                     defaultValue:@"#0A84FF"
                    allowInherit:NO
                           action:@selector(chooseAccentColor)]];


    PSSpecifier *compatGroup =
        [PSSpecifier groupSpecifierWithName:@"兼容模式"];
    [compatGroup setProperty:
        @"用于 App Store、Safari 等不完全跟随普通 UIKit tint 的系统 App。建议默认关闭，需要时逐项开启。"
        forKey:@"footerText"];
    [items addObject:compatGroup];

    [items addObject:
        [self switchSpecifierWithName:@"替换 System Blue"
                                  key:@"ReplaceSystemBlue"
                         defaultValue:NO]];

    [items addObject:
        [self switchSpecifierWithName:@"替换 Link Color"
                                  key:@"ReplaceLinkColor"
                         defaultValue:NO]];

    [items addObject:
        [self colorButtonWithName:@"语义蓝兼容色"
                              key:@"SemanticBlueColor"
                     defaultValue:@""
                    allowInherit:YES
                           action:@selector(chooseSemanticBlueColor)]];

    [items addObject:
        [self switchSpecifierWithName:@"显示注入测试边框"
                                  key:@"DebugInjectionBorder"
                         defaultValue:NO]];

    PSSpecifier *debugHelp = [PSSpecifier emptyGroupSpecifier];
    [debugHelp setProperty:
        @"开启“注入测试边框”后，成功加载 GlobalTint 的 App 窗口四周会出现 3pt 主题色边框。测试完请关闭。"
        forKey:@"footerText"];
    [items addObject:debugHelp];

    [items addObject:
        [self switchSpecifierWithName:@"启用组件独立颜色"
                                  key:@"UseSeparateColors"
                         defaultValue:NO]];

    PSSpecifier *colorHelp = [PSSpecifier emptyGroupSpecifier];
    [colorHelp setProperty:
        @"关闭“组件独立颜色”时，下面所有组件都会跟随主主题色；开启后，没有单独设置颜色的组件仍会自动跟随主色。"
        forKey:@"footerText"];
    [items addObject:colorHelp];

    // Component colors
    PSSpecifier *controlColors =
        [PSSpecifier groupSpecifierWithName:@"控件颜色"];
    [items addObject:controlColors];

    [items addObject:
        [self colorButtonWithName:@"Window Tint"
                              key:@"WindowColor"
                     defaultValue:@""
                    allowInherit:YES
                           action:@selector(chooseWindowColor)]];

    [items addObject:
        [self colorButtonWithName:@"Switch"
                              key:@"SwitchColor"
                     defaultValue:@""
                    allowInherit:YES
                           action:@selector(chooseSwitchColor)]];

    [items addObject:
        [self colorButtonWithName:@"Slider"
                              key:@"SliderColor"
                     defaultValue:@""
                    allowInherit:YES
                           action:@selector(chooseSliderColor)]];

    [items addObject:
        [self colorButtonWithName:@"Progress"
                              key:@"ProgressColor"
                     defaultValue:@""
                    allowInherit:YES
                           action:@selector(chooseProgressColor)]];

    [items addObject:
        [self colorButtonWithName:@"SegmentedControl"
                              key:@"SegmentedColor"
                     defaultValue:@""
                    allowInherit:YES
                           action:@selector(chooseSegmentedColor)]];

    [items addObject:
        [self colorButtonWithName:@"PageControl"
                              key:@"PageControlColor"
                     defaultValue:@""
                    allowInherit:YES
                           action:@selector(choosePageControlColor)]];

    [items addObject:
        [self colorButtonWithName:@"RefreshControl"
                              key:@"RefreshControlColor"
                     defaultValue:@""
                    allowInherit:YES
                           action:@selector(chooseRefreshControlColor)]];

    PSSpecifier *barColors =
        [PSSpecifier groupSpecifierWithName:@"导航 / Bar 颜色"];
    [items addObject:barColors];

    [items addObject:
        [self colorButtonWithName:@"NavigationBar"
                              key:@"NavigationBarColor"
                     defaultValue:@""
                    allowInherit:YES
                           action:@selector(chooseNavigationBarColor)]];

    [items addObject:
        [self colorButtonWithName:@"TabBar"
                              key:@"TabBarColor"
                     defaultValue:@""
                    allowInherit:YES
                           action:@selector(chooseTabBarColor)]];

    [items addObject:
        [self colorButtonWithName:@"Toolbar"
                              key:@"ToolbarColor"
                     defaultValue:@""
                    allowInherit:YES
                           action:@selector(chooseToolbarColor)]];

    [items addObject:
        [self colorButtonWithName:@"SearchBar"
                              key:@"SearchBarColor"
                     defaultValue:@""
                    allowInherit:YES
                           action:@selector(chooseSearchBarColor)]];

    PSSpecifier *clearColors =
        [PSSpecifier preferenceSpecifierNamed:@"清除全部组件独立颜色"
                                       target:self
                                          set:nil
                                          get:nil
                                       detail:nil
                                         cell:PSButtonCell
                                         edit:nil];
    clearColors.buttonAction = @selector(clearComponentColors);
    [items addObject:clearColors];

    // Component switches
    PSSpecifier *controlSwitches =
        [PSSpecifier groupSpecifierWithName:@"控件开关"];
    [controlSwitches setProperty:
        @"“标准控件总开关”关闭时，下面所有 UIKit 控件都会停止强制改色。"
        forKey:@"footerText"];
    [items addObject:controlSwitches];

    [items addObject:
        [self switchSpecifierWithName:@"Window 全局 Tint"
                                  key:@"ApplyWindowTint"
                         defaultValue:YES]];

    [items addObject:
        [self switchSpecifierWithName:@"标准控件总开关"
                                  key:@"ApplyControls"
                         defaultValue:YES]];

    [items addObject:
        [self switchSpecifierWithName:@"UISwitch"
                                  key:@"ApplySwitch"
                         defaultValue:YES]];

    [items addObject:
        [self switchSpecifierWithName:@"UISlider"
                                  key:@"ApplySlider"
                         defaultValue:YES]];

    [items addObject:
        [self switchSpecifierWithName:@"UIProgressView"
                                  key:@"ApplyProgress"
                         defaultValue:YES]];

    [items addObject:
        [self switchSpecifierWithName:@"UISegmentedControl"
                                  key:@"ApplySegmented"
                         defaultValue:YES]];

    [items addObject:
        [self switchSpecifierWithName:@"UIPageControl"
                                  key:@"ApplyPageControl"
                         defaultValue:YES]];

    [items addObject:
        [self switchSpecifierWithName:@"UIRefreshControl"
                                  key:@"ApplyRefreshControl"
                         defaultValue:YES]];

    PSSpecifier *barSwitches =
        [PSSpecifier groupSpecifierWithName:@"导航 / Bar 开关"];
    [barSwitches setProperty:
        @"“Bar 总开关”关闭时，下面所有 Navigation / Tab / Toolbar / SearchBar 都会停止强制改色。"
        forKey:@"footerText"];
    [items addObject:barSwitches];

    [items addObject:
        [self switchSpecifierWithName:@"Bar 总开关"
                                  key:@"ApplyBars"
                         defaultValue:YES]];

    [items addObject:
        [self switchSpecifierWithName:@"UINavigationBar"
                                  key:@"ApplyNavigationBar"
                         defaultValue:YES]];

    [items addObject:
        [self switchSpecifierWithName:@"UITabBar"
                                  key:@"ApplyTabBar"
                         defaultValue:YES]];

    [items addObject:
        [self switchSpecifierWithName:@"UIToolbar"
                                  key:@"ApplyToolbar"
                         defaultValue:YES]];

    [items addObject:
        [self switchSpecifierWithName:@"UISearchBar"
                                  key:@"ApplySearchBar"
                         defaultValue:YES]];

    // App exclusions
    PSSpecifier *exclusions =
        [PSSpecifier groupSpecifierWithName:@"App 排除"];
    [exclusions setProperty:
        @"输入要排除的 Bundle ID，多个项目用逗号分隔。例如：com.tencent.xin, com.apple.mobilesafari。仅对已经被 Relaxin / RootHide 注入 tweak 的进程生效。"
        forKey:@"footerText"];
    [items addObject:exclusions];

    PSSpecifier *excludedValue =
        [PSSpecifier preferenceSpecifierNamed:@"当前排除"
                                       target:self
                                          set:nil
                                          get:@selector(excludedBundleSummary:)
                                       detail:nil
                                         cell:PSTitleValueCell
                                         edit:nil];
    [items addObject:excludedValue];

    PSSpecifier *editExclusions =
        [PSSpecifier preferenceSpecifierNamed:@"编辑排除 Bundle ID"
                                       target:self
                                          set:nil
                                          get:nil
                                       detail:nil
                                         cell:PSButtonCell
                                         edit:nil];
    editExclusions.buttonAction = @selector(editExcludedBundleIDs);
    [items addObject:editExclusions];

    PSSpecifier *clearExclusions =
        [PSSpecifier preferenceSpecifierNamed:@"清空排除列表"
                                       target:self
                                          set:nil
                                          get:nil
                                       detail:nil
                                         cell:PSButtonCell
                                         edit:nil];
    clearExclusions.buttonAction = @selector(clearExcludedBundleIDs);
    [items addObject:clearExclusions];

    // Reset
    PSSpecifier *resetGroup = [PSSpecifier emptyGroupSpecifier];
    [resetGroup setProperty:
        @"V0.2 仍然只处理 UIKit 公共控件。SpringBoard、控制中心、锁屏和 SwiftUI 私有/语义颜色将在后续版本单独处理。"
        forKey:@"footerText"];
    [items addObject:resetGroup];

    PSSpecifier *reset =
        [PSSpecifier preferenceSpecifierNamed:@"恢复全部默认设置"
                                       target:self
                                          set:nil
                                          get:nil
                                       detail:nil
                                         cell:PSButtonCell
                                         edit:nil];
    reset.buttonAction = @selector(resetPreferences);
    [items addObject:reset];

    return items;
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        // V0.2 uses code-generated specifiers intentionally.
        // This avoids the RootHide/iOS 17 Root.plist loading issue seen in V0.1.x.
        _specifiers = [self buildSpecifiers];
    }

    return _specifiers;
}

#pragma mark - Color picker

- (void)presentColorPickerForKey:(NSString *)key
                    defaultValue:(NSString *)defaultValue
                           title:(NSString *)title {

    if (@available(iOS 14.0, *)) {
        self.gtPendingColorKey = key;
        self.gtPendingColorDefault = defaultValue;

        HBPreferences *preferences = [self preferences];
        NSString *stored = [preferences objectForKey:key];

        NSString *hex = nil;

        if ([stored isKindOfClass:[NSString class]] &&
            stored.length > 0) {
            hex = stored;
        } else if (defaultValue.length > 0) {
            hex = defaultValue;
        } else {
            NSString *accent = [preferences objectForKey:@"AccentColor"];
            hex =
                ([accent isKindOfClass:[NSString class]] && accent.length > 0)
                ? accent
                : @"#0A84FF";
        }

        UIColorPickerViewController *picker =
            [[UIColorPickerViewController alloc] init];

        picker.delegate = self;
        picker.supportsAlpha = NO;
        picker.title = title;
        picker.selectedColor = GTColorFromHexString(hex);

        [self presentViewController:picker animated:YES completion:nil];
    }
}

- (void)chooseAccentColor {
    [self presentColorPickerForKey:@"AccentColor"
                      defaultValue:@"#0A84FF"
                             title:@"主主题色"];
}

- (void)chooseWindowColor {
    [self presentColorPickerForKey:@"WindowColor"
                      defaultValue:@""
                             title:@"Window Tint"];
}

- (void)chooseSwitchColor {
    [self presentColorPickerForKey:@"SwitchColor"
                      defaultValue:@""
                             title:@"Switch"];
}

- (void)chooseSliderColor {
    [self presentColorPickerForKey:@"SliderColor"
                      defaultValue:@""
                             title:@"Slider"];
}

- (void)chooseProgressColor {
    [self presentColorPickerForKey:@"ProgressColor"
                      defaultValue:@""
                             title:@"Progress"];
}

- (void)chooseSegmentedColor {
    [self presentColorPickerForKey:@"SegmentedColor"
                      defaultValue:@""
                             title:@"SegmentedControl"];
}

- (void)choosePageControlColor {
    [self presentColorPickerForKey:@"PageControlColor"
                      defaultValue:@""
                             title:@"PageControl"];
}

- (void)chooseRefreshControlColor {
    [self presentColorPickerForKey:@"RefreshControlColor"
                      defaultValue:@""
                             title:@"RefreshControl"];
}

- (void)chooseNavigationBarColor {
    [self presentColorPickerForKey:@"NavigationBarColor"
                      defaultValue:@""
                             title:@"NavigationBar"];
}

- (void)chooseTabBarColor {
    [self presentColorPickerForKey:@"TabBarColor"
                      defaultValue:@""
                             title:@"TabBar"];
}

- (void)chooseToolbarColor {
    [self presentColorPickerForKey:@"ToolbarColor"
                      defaultValue:@""
                             title:@"Toolbar"];
}

- (void)chooseSearchBarColor {
    [self presentColorPickerForKey:@"SearchBarColor"
                      defaultValue:@""
                             title:@"SearchBar"];
}

- (void)colorPickerViewControllerDidSelectColor:
    (UIColorPickerViewController *)viewController API_AVAILABLE(ios(14.0)) {

    if (self.gtPendingColorKey.length == 0) {
        return;
    }

    NSString *hex = GTHexStringFromColor(viewController.selectedColor);

    HBPreferences *preferences = [self preferences];
    [preferences setObject:hex forKey:self.gtPendingColorKey];
    [self postReloadNotification];
}

- (void)colorPickerViewControllerDidFinish:
    (UIColorPickerViewController *)viewController API_AVAILABLE(ios(14.0)) {

    self.gtPendingColorKey = nil;
    self.gtPendingColorDefault = nil;

    [self reloadSpecifiers];
}

#pragma mark - Color management

- (void)clearComponentColors {
    NSArray<NSString *> *keys = @[
        @"WindowColor",
        @"SwitchColor",
        @"SliderColor",
        @"ProgressColor",
        @"SegmentedColor",
        @"PageControlColor",
        @"RefreshControlColor",
        @"NavigationBarColor",
        @"TabBarColor",
        @"ToolbarColor",
        @"SearchBarColor"
    ];

    HBPreferences *preferences = [self preferences];

    for (NSString *key in keys) {
        [preferences removeObjectForKey:key];
    }

    [self postReloadNotification];
    [self reloadSpecifiers];
}

#pragma mark - App exclusions

- (id)excludedBundleSummary:(PSSpecifier *)specifier {
    NSString *value =
        [[self preferences] objectForKey:@"ExcludedBundleIDs"];

    if (![value isKindOfClass:[NSString class]] ||
        value.length == 0) {
        return @"未设置";
    }

    NSCharacterSet *separators =
        [NSCharacterSet characterSetWithCharactersInString:@",;\n\r\t "];

    NSArray<NSString *> *parts =
        [value componentsSeparatedByCharactersInSet:separators];

    NSInteger count = 0;

    for (NSString *part in parts) {
        NSString *clean =
            [part stringByTrimmingCharactersInSet:
             [NSCharacterSet whitespaceAndNewlineCharacterSet]];

        if (clean.length > 0) {
            count++;
        }
    }

    return [NSString stringWithFormat:@"%ld 个", (long)count];
}

- (void)editExcludedBundleIDs {
    HBPreferences *preferences = [self preferences];

    NSString *existing =
        [preferences objectForKey:@"ExcludedBundleIDs"];

    if (![existing isKindOfClass:[NSString class]]) {
        existing = @"";
    }

    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"排除 App"
                                            message:@"输入 Bundle ID，多个项目用逗号分隔。"
                                     preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = existing;
        textField.placeholder =
            @"com.tencent.xin, com.apple.mobilesafari";
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.autocapitalizationType =
            UITextAutocapitalizationTypeNone;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];

    [alert addAction:
        [UIAlertAction actionWithTitle:@"取消"
                                 style:UIAlertActionStyleCancel
                               handler:nil]];

    __weak typeof(self) weakSelf = self;

    [alert addAction:
        [UIAlertAction actionWithTitle:@"保存"
                                 style:UIAlertActionStyleDefault
                               handler:^(__unused UIAlertAction *action) {

        NSString *value =
            alert.textFields.firstObject.text ?: @"";

        HBPreferences *prefs = [weakSelf preferences];
        [prefs setObject:value forKey:@"ExcludedBundleIDs"];

        [weakSelf postReloadNotification];
        [weakSelf reloadSpecifiers];
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)clearExcludedBundleIDs {
    HBPreferences *preferences = [self preferences];
    [preferences removeObjectForKey:@"ExcludedBundleIDs"];

    [self postReloadNotification];
    [self reloadSpecifiers];
}

#pragma mark - Reset

- (void)resetPreferences {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"恢复默认设置"
                                            message:@"将主色、组件颜色、组件开关以及 App 排除列表全部恢复为默认值。"
                                     preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:
        [UIAlertAction actionWithTitle:@"取消"
                                 style:UIAlertActionStyleCancel
                               handler:nil]];

    __weak typeof(self) weakSelf = self;

    [alert addAction:
        [UIAlertAction actionWithTitle:@"恢复"
                                 style:UIAlertActionStyleDestructive
                               handler:^(__unused UIAlertAction *action) {

        HBPreferences *preferences = [weakSelf preferences];
        [preferences removeAllObjects];

        [weakSelf postReloadNotification];
        [weakSelf reloadSpecifiers];
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

@end
