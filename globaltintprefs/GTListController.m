#import "GTListController.h"
#import "GTAppListController.h"

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
@property (nonatomic, copy) NSString *gtPendingAppBundleID;
@property (nonatomic, copy) NSString *gtPendingAppComponentKey;
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
        @"V0.4.0：新增 SpringBoard / System UI 基础支持，可分别控制 Control Center、Lock Screen 与系统菜单，并允许 GT 检查器直接检查 SpringBoard 私有界面。"
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

    PSSpecifier *managerGroup =
        [PSSpecifier groupSpecifierWithName:@"App 配置管理"];

    [managerGroup setProperty:
        @"推荐使用这里直接选择已安装 App。V0.3.4 支持 App 图标、名称/Bundle ID 搜索、配置状态和已配置优先排序；下面仍保留手动 Bundle ID 作为备用入口。"
        forKey:@"footerText"];

    [items addObject:managerGroup];

    PSSpecifier *appManager =
        [PSSpecifier preferenceSpecifierNamed:@"打开 App 配置管理器"
                                       target:self
                                          set:nil
                                          get:nil
                                       detail:[GTAppListController class]
                                         cell:PSLinkCell
                                         edit:nil];

    [items addObject:appManager];

    PSSpecifier *appProfiles =
        [PSSpecifier groupSpecifierWithName:@"App 独立主色（高级 / 手动）"];
    [appProfiles setProperty:
        @"为指定 Bundle ID 单独设置主主题色。组件独立颜色关闭时，该 App 的所有组件跟随此颜色；开启组件独立颜色后，已明确设置组件颜色的项目优先，未设置的项目继续跟随 App 独立主色。可通过 UI 元素检查器报告第一行查看 Bundle ID。"
        forKey:@"footerText"];
    [items addObject:appProfiles];

    [items addObject:
        [self switchSpecifierWithName:@"启用 App 独立主色"
                                  key:@"EnableAppColorOverrides"
                         defaultValue:YES]];

    PSSpecifier *profileSummary =
        [PSSpecifier preferenceSpecifierNamed:@"已配置 App"
                                       target:self
                                          set:nil
                                          get:@selector(appColorOverrideSummary:)
                                       detail:nil
                                         cell:PSTitleValueCell
                                         edit:nil];
    [items addObject:profileSummary];

    PSSpecifier *addProfile =
        [PSSpecifier preferenceSpecifierNamed:@"添加 / 修改 App 主色"
                                       target:self
                                          set:nil
                                          get:nil
                                       detail:nil
                                         cell:PSButtonCell
                                         edit:nil];
    addProfile.buttonAction = @selector(addOrEditAppColorOverride);
    [items addObject:addProfile];

    PSSpecifier *removeProfile =
        [PSSpecifier preferenceSpecifierNamed:@"删除 App 主色"
                                       target:self
                                          set:nil
                                          get:nil
                                       detail:nil
                                         cell:PSButtonCell
                                         edit:nil];
    removeProfile.buttonAction = @selector(removeAppColorOverride);
    [items addObject:removeProfile];

    PSSpecifier *clearProfiles =
        [PSSpecifier preferenceSpecifierNamed:@"清空全部 App 主色"
                                       target:self
                                          set:nil
                                          get:nil
                                       detail:nil
                                         cell:PSButtonCell
                                         edit:nil];
    clearProfiles.buttonAction = @selector(clearAppColorOverrides);
    [items addObject:clearProfiles];

    PSSpecifier *appComponentGroup =
        [PSSpecifier groupSpecifierWithName:@"App 独立组件颜色（高级 / 手动）"];
    [appComponentGroup setProperty:
        @"需要先开启“启用组件独立颜色”。优先级：App 独立组件颜色 > 全局组件颜色 > App 独立主色 > 全局主色。"
        forKey:@"footerText"];
    [items addObject:appComponentGroup];

    PSSpecifier *componentSummary =
        [PSSpecifier preferenceSpecifierNamed:@"已配置组件规则"
                                       target:self
                                          set:nil
                                          get:@selector(appComponentOverrideSummary:)
                                       detail:nil
                                         cell:PSTitleValueCell
                                         edit:nil];
    [items addObject:componentSummary];

    PSSpecifier *addComponent =
        [PSSpecifier preferenceSpecifierNamed:@"添加 / 修改 App 组件颜色"
                                       target:self
                                          set:nil
                                          get:nil
                                       detail:nil
                                         cell:PSButtonCell
                                         edit:nil];
    addComponent.buttonAction =
        @selector(addOrEditAppComponentColorOverride);
    [items addObject:addComponent];

    PSSpecifier *removeComponent =
        [PSSpecifier preferenceSpecifierNamed:@"删除 App 组件颜色"
                                       target:self
                                          set:nil
                                          get:nil
                                       detail:nil
                                         cell:PSButtonCell
                                         edit:nil];
    removeComponent.buttonAction =
        @selector(removeAppComponentColorOverride);
    [items addObject:removeComponent];

    PSSpecifier *clearComponents =
        [PSSpecifier preferenceSpecifierNamed:@"清空全部 App 组件颜色"
                                       target:self
                                          set:nil
                                          get:nil
                                       detail:nil
                                         cell:PSButtonCell
                                         edit:nil];
    clearComponents.buttonAction =
        @selector(clearAppComponentColorOverrides);
    [items addObject:clearComponents];

    PSSpecifier *appSwitchGroup =
        [PSSpecifier groupSpecifierWithName:@"App 独立组件开关（高级 / 手动）"];
    [appSwitchGroup setProperty:
        @"App 独立开关优先于单个全局组件开关；“标准控件总开关”和“Bar 总开关”仍作为组级总开关。选择“跟随全局”会删除该 App 的单项覆盖规则。"
        forKey:@"footerText"];
    [items addObject:appSwitchGroup];

    [items addObject:
        [self switchSpecifierWithName:@"启用 App 独立组件开关"
                                  key:@"EnableAppComponentSwitchOverrides"
                         defaultValue:YES]];

    PSSpecifier *switchSummary =
        [PSSpecifier preferenceSpecifierNamed:@"已配置开关规则"
                                       target:self
                                          set:nil
                                          get:@selector(appComponentSwitchOverrideSummary:)
                                       detail:nil
                                         cell:PSTitleValueCell
                                         edit:nil];
    [items addObject:switchSummary];

    PSSpecifier *editSwitch =
        [PSSpecifier preferenceSpecifierNamed:@"添加 / 修改 App 组件开关"
                                       target:self
                                          set:nil
                                          get:nil
                                       detail:nil
                                         cell:PSButtonCell
                                         edit:nil];
    editSwitch.buttonAction =
        @selector(addOrEditAppComponentSwitchOverride);
    [items addObject:editSwitch];

    PSSpecifier *removeSwitch =
        [PSSpecifier preferenceSpecifierNamed:@"删除 App 组件开关"
                                       target:self
                                          set:nil
                                          get:nil
                                       detail:nil
                                         cell:PSButtonCell
                                         edit:nil];
    removeSwitch.buttonAction =
        @selector(removeAppComponentSwitchOverride);
    [items addObject:removeSwitch];

    PSSpecifier *clearSwitches =
        [PSSpecifier preferenceSpecifierNamed:@"清空全部 App 组件开关"
                                       target:self
                                          set:nil
                                          get:nil
                                       detail:nil
                                         cell:PSButtonCell
                                         edit:nil];
    clearSwitches.buttonAction =
        @selector(clearAppComponentSwitchOverrides);
    [items addObject:clearSwitches];


    PSSpecifier *systemUIGroup =
        [PSSpecifier groupSpecifierWithName:@"System UI / SpringBoard"];

    [systemUIGroup setProperty:
        @"V0.4.0 先建立安全的 System UI 基础层：只对明确识别为 Control Center、Lock Screen 或系统菜单的 SpringBoard 视图应用 UIKit tint。系统界面总开关默认关闭。开启 UI 元素检查器后，也可以直接检查 SpringBoard 中的真实私有类。"
        forKey:@"footerText"];

    [items addObject:systemUIGroup];

    [items addObject:
        [self switchSpecifierWithName:@"启用 System UI 改色"
                                  key:@"EnableSystemUI"
                         defaultValue:NO]];

    [items addObject:
        [self switchSpecifierWithName:@"Control Center"
                                  key:@"EnableControlCenter"
                         defaultValue:YES]];

    [items addObject:
        [self switchSpecifierWithName:@"Lock Screen"
                                  key:@"EnableLockScreen"
                         defaultValue:YES]];

    [items addObject:
        [self switchSpecifierWithName:@"系统菜单 / Context Menu"
                                  key:@"EnableSystemMenus"
                         defaultValue:YES]];

    [items addObject:
        [self colorButtonWithName:@"System UI 主色"
                              key:@"SystemAccentColor"
                     defaultValue:@""
                    allowInherit:YES
                           action:@selector(chooseSystemAccentColor)]];

    [items addObject:
        [self colorButtonWithName:@"Control Center 色"
                              key:@"ControlCenterColor"
                     defaultValue:@""
                    allowInherit:YES
                           action:@selector(chooseControlCenterColor)]];

    [items addObject:
        [self colorButtonWithName:@"Lock Screen 色"
                              key:@"LockScreenColor"
                     defaultValue:@""
                    allowInherit:YES
                           action:@selector(chooseLockScreenColor)]];

    [items addObject:
        [self colorButtonWithName:@"System Menu 色"
                              key:@"SystemMenuColor"
                     defaultValue:@""
                    allowInherit:YES
                           action:@selector(chooseSystemMenuColor)]];


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


    [items addObject:
        [self switchSpecifierWithName:@"强制替换已解析蓝色"
                                  key:@"ForceResolvedBlue"
                         defaultValue:NO]];


    [items addObject:
        [self switchSpecifierWithName:@"UI 元素检查器"
                                  key:@"ElementInspector"
                         defaultValue:NO]];

    PSSpecifier *debugHelp = [PSSpecifier emptyGroupSpecifier];
    [debugHelp setProperty:
        @"“注入测试边框”仅用于确认当前进程中的 GlobalTint 窗口处理是否运行，测试后建议关闭。“强制替换已解析蓝色”用于少数仍直接写入系统蓝色的 UIKit 元素。开启“UI 元素检查器”后，普通 App 和 SpringBoard 都可以显示紫色 GT；点 GT，再点需要检查的 UI，即可生成视图层级与颜色报告并自动复制到剪贴板。检查器采用独立透明 UIWindowScene 覆盖层，不再使用长按或 sendEvent 事件 Hook。"
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
        @"V0.4.0 建立 SpringBoard / System UI 基础层，并开放 SpringBoard GT 检查器。Control Center、Lock Screen 与系统菜单目前使用保守的 UIKit tint 分类；下一步根据实际 GT 报告继续做精确私有类适配。"
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

- (void)chooseSemanticBlueColor {
    [self presentColorPickerForKey:@"SemanticBlueColor"
                      defaultValue:@""
                             title:@"语义蓝兼容色"];
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

- (void)chooseSystemAccentColor {
    [self presentColorPickerForKey:@"SystemAccentColor"
                      defaultValue:@""
                             title:@"System UI 主色"];
}

- (void)chooseControlCenterColor {
    [self presentColorPickerForKey:@"ControlCenterColor"
                      defaultValue:@""
                             title:@"Control Center"];
}

- (void)chooseLockScreenColor {
    [self presentColorPickerForKey:@"LockScreenColor"
                      defaultValue:@""
                             title:@"Lock Screen"];
}

- (void)chooseSystemMenuColor {
    [self presentColorPickerForKey:@"SystemMenuColor"
                      defaultValue:@""
                             title:@"System Menu"];
}

- (void)colorPickerViewControllerDidSelectColor:
    (UIColorPickerViewController *)viewController API_AVAILABLE(ios(14.0)) {

    NSString *hex =
        GTHexStringFromColor(viewController.selectedColor);

    HBPreferences *preferences = [self preferences];

    if (self.gtPendingAppBundleID.length > 0 &&
        self.gtPendingAppComponentKey.length > 0) {

        NSDictionary *stored =
            [preferences objectForKey:@"AppComponentColorOverrides"];

        NSMutableDictionary *allProfiles =
            [stored isKindOfClass:[NSDictionary class]]
            ? [stored mutableCopy]
            : [NSMutableDictionary dictionary];

        NSString *bundleID =
            self.gtPendingAppBundleID.lowercaseString;

        NSDictionary *existingRules =
            [allProfiles[bundleID]
             isKindOfClass:[NSDictionary class]]
            ? allProfiles[bundleID]
            : @{};

        NSMutableDictionary *rules =
            [existingRules mutableCopy];

        rules[self.gtPendingAppComponentKey] = hex;
        allProfiles[bundleID] = [rules copy];

        [preferences setObject:[allProfiles copy]
                        forKey:@"AppComponentColorOverrides"];

        [self postReloadNotification];
        return;
    }

    if (self.gtPendingAppBundleID.length > 0) {
        NSDictionary *stored =
            [preferences objectForKey:@"AppColorOverrides"];

        NSMutableDictionary *profiles =
            [stored isKindOfClass:[NSDictionary class]]
            ? [stored mutableCopy]
            : [NSMutableDictionary dictionary];

        profiles[self.gtPendingAppBundleID.lowercaseString] = hex;

        [preferences setObject:[profiles copy]
                        forKey:@"AppColorOverrides"];

        [self postReloadNotification];
        return;
    }

    if (self.gtPendingColorKey.length == 0) {
        return;
    }

    [preferences setObject:hex forKey:self.gtPendingColorKey];
    [self postReloadNotification];
}

- (void)colorPickerViewControllerDidFinish:
    (UIColorPickerViewController *)viewController API_AVAILABLE(ios(14.0)) {

    self.gtPendingColorKey = nil;
    self.gtPendingColorDefault = nil;
    self.gtPendingAppBundleID = nil;
    self.gtPendingAppComponentKey = nil;

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

#pragma mark - App color profiles

- (NSDictionary<NSString *, NSString *> *)appColorOverrides {
    id value =
        [[self preferences] objectForKey:@"AppColorOverrides"];

    if (![value isKindOfClass:[NSDictionary class]]) {
        return @{};
    }

    NSMutableDictionary<NSString *, NSString *> *result =
        [NSMutableDictionary dictionary];

    [(NSDictionary *)value enumerateKeysAndObjectsUsingBlock:
        ^(id rawKey, id rawValue, BOOL *stop) {

        if (![rawKey isKindOfClass:[NSString class]] ||
            ![rawValue isKindOfClass:[NSString class]]) {
            return;
        }

        NSString *bundleID =
            [[(NSString *)rawKey
              stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]]
             lowercaseString];

        NSString *hex =
            [(NSString *)rawValue uppercaseString];

        if (bundleID.length > 0 && hex.length > 0) {
            result[bundleID] = hex;
        }
    }];

    return [result copy];
}

- (id)appColorOverrideSummary:(PSSpecifier *)specifier {
    NSDictionary *profiles = [self appColorOverrides];

    if (profiles.count == 0) {
        return @"未设置";
    }

    return [NSString stringWithFormat:@"%ld 个",
            (long)profiles.count];
}

- (void)presentAppColorPickerForBundleID:(NSString *)bundleID {
    if (@available(iOS 14.0, *)) {
        NSString *normalized =
            [[bundleID
              stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]]
             lowercaseString];

        if (normalized.length == 0) {
            return;
        }

        self.gtPendingColorKey = nil;
        self.gtPendingColorDefault = nil;
        self.gtPendingAppBundleID = normalized;
        self.gtPendingAppComponentKey = nil;

        NSDictionary *profiles = [self appColorOverrides];
        NSString *stored = profiles[normalized];

        HBPreferences *preferences = [self preferences];
        NSString *accent =
            [preferences objectForKey:@"AccentColor"];

        NSString *hex =
            ([stored isKindOfClass:[NSString class]] &&
             stored.length > 0)
            ? stored
            : (([accent isKindOfClass:[NSString class]] &&
                accent.length > 0)
               ? accent
               : @"#0A84FF");

        UIColorPickerViewController *picker =
            [[UIColorPickerViewController alloc] init];

        picker.delegate = self;
        picker.supportsAlpha = NO;
        picker.title =
            [NSString stringWithFormat:@"App 主色 · %@", normalized];
        picker.selectedColor = GTColorFromHexString(hex);

        [self presentViewController:picker
                           animated:YES
                         completion:nil];
    }
}

- (void)addOrEditAppColorOverride {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"添加 / 修改 App 主色"
                                            message:@"输入 App 的 Bundle ID。下一步会打开系统颜色选择器。"
                                     preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:
        ^(UITextField *textField) {
        textField.placeholder = @"例如 com.apple.AppStore";
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.autocapitalizationType =
            UITextAutocapitalizationTypeNone;
        textField.clearButtonMode =
            UITextFieldViewModeWhileEditing;
    }];

    [alert addAction:
        [UIAlertAction actionWithTitle:@"取消"
                                 style:UIAlertActionStyleCancel
                               handler:nil]];

    __weak typeof(self) weakSelf = self;

    [alert addAction:
        [UIAlertAction actionWithTitle:@"选择颜色"
                                 style:UIAlertActionStyleDefault
                               handler:^(__unused UIAlertAction *action) {

        NSString *bundleID =
            alert.textFields.firstObject.text ?: @"";

        bundleID =
            [bundleID stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]];

        if (bundleID.length == 0) {
            return;
        }

        [weakSelf presentAppColorPickerForBundleID:bundleID];
    }]];

    [self presentViewController:alert
                       animated:YES
                     completion:nil];
}

- (void)removeAppColorOverride {
    NSDictionary<NSString *, NSString *> *profiles =
        [self appColorOverrides];

    if (profiles.count == 0) {
        UIAlertController *empty =
            [UIAlertController alertControllerWithTitle:@"没有 App 独立主色"
                                                message:@"当前没有可删除的配置。"
                                         preferredStyle:UIAlertControllerStyleAlert];

        [empty addAction:
            [UIAlertAction actionWithTitle:@"好"
                                     style:UIAlertActionStyleDefault
                                   handler:nil]];

        [self presentViewController:empty
                           animated:YES
                         completion:nil];
        return;
    }

    UIAlertController *sheet =
        [UIAlertController alertControllerWithTitle:@"删除 App 主色"
                                            message:@"选择要删除的 App 配置"
                                     preferredStyle:UIAlertControllerStyleActionSheet];

    NSArray<NSString *> *bundleIDs =
        [[profiles allKeys]
         sortedArrayUsingSelector:
            @selector(localizedCaseInsensitiveCompare:)];

    __weak typeof(self) weakSelf = self;

    for (NSString *bundleID in bundleIDs) {
        NSString *hex = profiles[bundleID] ?: @"";

        NSString *title =
            [NSString stringWithFormat:@"%@ · %@", bundleID, hex];

        [sheet addAction:
            [UIAlertAction actionWithTitle:title
                                     style:UIAlertActionStyleDestructive
                                   handler:^(__unused UIAlertAction *action) {

            HBPreferences *preferences = [weakSelf preferences];
            NSDictionary *stored =
                [preferences objectForKey:@"AppColorOverrides"];

            NSMutableDictionary *updated =
                [stored isKindOfClass:[NSDictionary class]]
                ? [stored mutableCopy]
                : [NSMutableDictionary dictionary];

            [updated removeObjectForKey:bundleID];

            [preferences setObject:[updated copy]
                            forKey:@"AppColorOverrides"];

            [weakSelf postReloadNotification];
            [weakSelf reloadSpecifiers];
        }]];
    }

    [sheet addAction:
        [UIAlertAction actionWithTitle:@"取消"
                                 style:UIAlertActionStyleCancel
                               handler:nil]];

    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = self.view;
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

- (void)clearAppColorOverrides {
    NSDictionary *profiles = [self appColorOverrides];

    if (profiles.count == 0) {
        return;
    }

    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"清空 App 独立主色"
                                            message:@"删除全部 App 独立主色配置？"
                                     preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:
        [UIAlertAction actionWithTitle:@"取消"
                                 style:UIAlertActionStyleCancel
                               handler:nil]];

    __weak typeof(self) weakSelf = self;

    [alert addAction:
        [UIAlertAction actionWithTitle:@"清空"
                                 style:UIAlertActionStyleDestructive
                               handler:^(__unused UIAlertAction *action) {

        HBPreferences *preferences = [weakSelf preferences];
        [preferences removeObjectForKey:@"AppColorOverrides"];

        [weakSelf postReloadNotification];
        [weakSelf reloadSpecifiers];
    }]];

    [self presentViewController:alert
                       animated:YES
                     completion:nil];
}

#pragma mark - App component color profiles

- (NSDictionary<NSString *,
                  NSDictionary<NSString *, NSString *> *> *)
appComponentColorOverrides {
    id value =
        [[self preferences]
         objectForKey:@"AppComponentColorOverrides"];

    if (![value isKindOfClass:[NSDictionary class]]) {
        return @{};
    }

    return [(NSDictionary *)value copy];
}

- (NSDictionary<NSString *, NSString *> *)appComponentNames {
    return @{
        @"WindowColor": @"Window",
        @"SwitchColor": @"Switch",
        @"SliderColor": @"Slider",
        @"ProgressColor": @"Progress",
        @"SegmentedColor": @"SegmentedControl",
        @"PageControlColor": @"PageControl",
        @"RefreshControlColor": @"RefreshControl",
        @"NavigationBarColor": @"NavigationBar",
        @"TabBarColor": @"TabBar",
        @"ToolbarColor": @"Toolbar",
        @"SearchBarColor": @"SearchBar"
    };
}

- (id)appComponentOverrideSummary:(PSSpecifier *)specifier {
    NSDictionary *profiles =
        [self appComponentColorOverrides];

    NSInteger ruleCount = 0;

    for (id value in profiles.allValues) {
        if ([value isKindOfClass:[NSDictionary class]]) {
            ruleCount += [(NSDictionary *)value count];
        }
    }

    if (ruleCount == 0) {
        return @"未设置";
    }

    return [NSString stringWithFormat:@"%ld 条",
            (long)ruleCount];
}

- (void)presentAppComponentColorPickerForBundleID:(NSString *)bundleID
                                      componentKey:(NSString *)componentKey {
    if (@available(iOS 14.0, *)) {
        NSString *normalized =
            [[bundleID
              stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]]
             lowercaseString];

        if (normalized.length == 0 ||
            componentKey.length == 0) {
            return;
        }

        NSDictionary *componentNames =
            [self appComponentNames];

        NSString *componentName =
            componentNames[componentKey];

        if (componentName.length == 0) {
            return;
        }

        self.gtPendingColorKey = nil;
        self.gtPendingColorDefault = nil;
        self.gtPendingAppBundleID = normalized;
        self.gtPendingAppComponentKey = componentKey;

        NSDictionary *profiles =
            [self appComponentColorOverrides];

        NSDictionary *rules =
            [profiles[normalized]
             isKindOfClass:[NSDictionary class]]
            ? profiles[normalized]
            : @{};

        NSString *stored = rules[componentKey];

        HBPreferences *preferences = [self preferences];

        NSDictionary *appAccents =
            [preferences objectForKey:@"AppColorOverrides"];

        NSString *appAccent =
            [appAccents isKindOfClass:[NSDictionary class]]
            ? appAccents[normalized]
            : nil;

        NSString *globalAccent =
            [preferences objectForKey:@"AccentColor"];

        NSString *hex =
            ([stored isKindOfClass:[NSString class]] &&
             stored.length > 0)
            ? stored
            : (([appAccent isKindOfClass:[NSString class]] &&
                appAccent.length > 0)
               ? appAccent
               : (([globalAccent isKindOfClass:[NSString class]] &&
                   globalAccent.length > 0)
                  ? globalAccent
                  : @"#0A84FF"));

        UIColorPickerViewController *picker =
            [[UIColorPickerViewController alloc] init];

        picker.delegate = self;
        picker.supportsAlpha = NO;

        picker.title =
            [NSString stringWithFormat:@"%@ · %@",
             normalized,
             componentName];

        picker.selectedColor =
            GTColorFromHexString(hex);

        [self presentViewController:picker
                           animated:YES
                         completion:nil];
    }
}

- (void)chooseAppComponentForBundleID:(NSString *)bundleID {
    UIAlertController *sheet =
        [UIAlertController alertControllerWithTitle:@"选择组件"
                                            message:bundleID
                                     preferredStyle:UIAlertControllerStyleActionSheet];

    NSDictionary<NSString *, NSString *> *names =
        [self appComponentNames];

    NSArray<NSString *> *orderedKeys = @[
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

    __weak typeof(self) weakSelf = self;

    for (NSString *key in orderedKeys) {
        NSString *title = names[key];

        [sheet addAction:
            [UIAlertAction actionWithTitle:title
                                     style:UIAlertActionStyleDefault
                                   handler:^(__unused UIAlertAction *action) {
            [weakSelf
                presentAppComponentColorPickerForBundleID:bundleID
                                             componentKey:key];
        }]];
    }

    [sheet addAction:
        [UIAlertAction actionWithTitle:@"取消"
                                 style:UIAlertActionStyleCancel
                               handler:nil]];

    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = self.view;
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

- (void)addOrEditAppComponentColorOverride {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"App 组件颜色"
                                            message:@"输入 Bundle ID，然后选择要单独改色的组件。"
                                     preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:
        ^(UITextField *textField) {
        textField.placeholder = @"例如 com.apple.AppStore";
        textField.autocorrectionType =
            UITextAutocorrectionTypeNo;
        textField.autocapitalizationType =
            UITextAutocapitalizationTypeNone;
        textField.clearButtonMode =
            UITextFieldViewModeWhileEditing;
    }];

    [alert addAction:
        [UIAlertAction actionWithTitle:@"取消"
                                 style:UIAlertActionStyleCancel
                               handler:nil]];

    __weak typeof(self) weakSelf = self;

    [alert addAction:
        [UIAlertAction actionWithTitle:@"下一步"
                                 style:UIAlertActionStyleDefault
                               handler:^(__unused UIAlertAction *action) {

        NSString *bundleID =
            alert.textFields.firstObject.text ?: @"";

        bundleID =
            [bundleID stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]];

        if (bundleID.length == 0) {
            return;
        }

        [weakSelf chooseAppComponentForBundleID:bundleID];
    }]];

    [self presentViewController:alert
                       animated:YES
                     completion:nil];
}

- (void)removeAppComponentColorOverride {
    NSDictionary *profiles =
        [self appComponentColorOverrides];

    NSMutableArray<NSDictionary *> *entries =
        [NSMutableArray array];

    NSDictionary *names =
        [self appComponentNames];

    for (NSString *bundleID in profiles) {
        id rawRules = profiles[bundleID];

        if (![rawRules isKindOfClass:[NSDictionary class]]) {
            continue;
        }

        NSDictionary *rules = rawRules;

        for (NSString *componentKey in rules) {
            NSString *hex = rules[componentKey];

            if (![hex isKindOfClass:[NSString class]]) {
                continue;
            }

            [entries addObject:@{
                @"bundleID": bundleID,
                @"componentKey": componentKey,
                @"componentName": names[componentKey] ?: componentKey,
                @"hex": hex
            }];
        }
    }

    if (entries.count == 0) {
        UIAlertController *empty =
            [UIAlertController alertControllerWithTitle:@"没有组件规则"
                                                message:@"当前没有可删除的 App 独立组件颜色。"
                                         preferredStyle:UIAlertControllerStyleAlert];

        [empty addAction:
            [UIAlertAction actionWithTitle:@"好"
                                     style:UIAlertActionStyleDefault
                                   handler:nil]];

        [self presentViewController:empty
                           animated:YES
                         completion:nil];
        return;
    }

    [entries sortUsingComparator:
        ^NSComparisonResult(NSDictionary *left,
                            NSDictionary *right) {
        NSString *a =
            [NSString stringWithFormat:@"%@ %@",
             left[@"bundleID"],
             left[@"componentName"]];

        NSString *b =
            [NSString stringWithFormat:@"%@ %@",
             right[@"bundleID"],
             right[@"componentName"]];

        return [a localizedCaseInsensitiveCompare:b];
    }];

    UIAlertController *sheet =
        [UIAlertController alertControllerWithTitle:@"删除 App 组件颜色"
                                            message:nil
                                     preferredStyle:UIAlertControllerStyleActionSheet];

    __weak typeof(self) weakSelf = self;

    for (NSDictionary *entry in entries) {
        NSString *bundleID = entry[@"bundleID"];
        NSString *componentKey = entry[@"componentKey"];

        NSString *title =
            [NSString stringWithFormat:@"%@ · %@ · %@",
             bundleID,
             entry[@"componentName"],
             entry[@"hex"]];

        [sheet addAction:
            [UIAlertAction actionWithTitle:title
                                     style:UIAlertActionStyleDestructive
                                   handler:^(__unused UIAlertAction *action) {

            HBPreferences *preferences =
                [weakSelf preferences];

            NSDictionary *stored =
                [preferences
                 objectForKey:@"AppComponentColorOverrides"];

            NSMutableDictionary *allProfiles =
                [stored isKindOfClass:[NSDictionary class]]
                ? [stored mutableCopy]
                : [NSMutableDictionary dictionary];

            NSDictionary *existingRules =
                [allProfiles[bundleID]
                 isKindOfClass:[NSDictionary class]]
                ? allProfiles[bundleID]
                : @{};

            NSMutableDictionary *rules =
                [existingRules mutableCopy];

            [rules removeObjectForKey:componentKey];

            if (rules.count == 0) {
                [allProfiles removeObjectForKey:bundleID];
            } else {
                allProfiles[bundleID] = [rules copy];
            }

            [preferences setObject:[allProfiles copy]
                            forKey:@"AppComponentColorOverrides"];

            [weakSelf postReloadNotification];
            [weakSelf reloadSpecifiers];
        }]];
    }

    [sheet addAction:
        [UIAlertAction actionWithTitle:@"取消"
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

- (void)clearAppComponentColorOverrides {
    NSDictionary *profiles =
        [self appComponentColorOverrides];

    if (profiles.count == 0) {
        return;
    }

    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"清空 App 组件颜色"
                                            message:@"删除全部 App 独立组件颜色配置？"
                                     preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:
        [UIAlertAction actionWithTitle:@"取消"
                                 style:UIAlertActionStyleCancel
                               handler:nil]];

    __weak typeof(self) weakSelf = self;

    [alert addAction:
        [UIAlertAction actionWithTitle:@"清空"
                                 style:UIAlertActionStyleDestructive
                               handler:^(__unused UIAlertAction *action) {

        HBPreferences *preferences =
            [weakSelf preferences];

        [preferences
            removeObjectForKey:@"AppComponentColorOverrides"];

        [weakSelf postReloadNotification];
        [weakSelf reloadSpecifiers];
    }]];

    [self presentViewController:alert
                       animated:YES
                     completion:nil];
}

#pragma mark - App component switch profiles

- (NSDictionary<NSString *,
                  NSDictionary<NSString *, NSNumber *> *> *)
appComponentSwitchOverrides {
    id value =
        [[self preferences]
         objectForKey:@"AppComponentSwitchOverrides"];

    if (![value isKindOfClass:[NSDictionary class]]) {
        return @{};
    }

    return [(NSDictionary *)value copy];
}

- (NSDictionary<NSString *, NSString *> *)appComponentSwitchNames {
    return @{
        @"Window": @"Window 全局 Tint",
        @"Switch": @"UISwitch",
        @"Slider": @"UISlider",
        @"Progress": @"UIProgressView",
        @"Segmented": @"UISegmentedControl",
        @"PageControl": @"UIPageControl",
        @"RefreshControl": @"UIRefreshControl",
        @"NavigationBar": @"UINavigationBar",
        @"TabBar": @"UITabBar",
        @"Toolbar": @"UIToolbar",
        @"SearchBar": @"UISearchBar"
    };
}

- (NSArray<NSString *> *)orderedAppComponentSwitchKeys {
    return @[
        @"Window",
        @"Switch",
        @"Slider",
        @"Progress",
        @"Segmented",
        @"PageControl",
        @"RefreshControl",
        @"NavigationBar",
        @"TabBar",
        @"Toolbar",
        @"SearchBar"
    ];
}

- (id)appComponentSwitchOverrideSummary:(PSSpecifier *)specifier {
    NSDictionary *profiles =
        [self appComponentSwitchOverrides];

    NSInteger ruleCount = 0;

    for (id value in profiles.allValues) {
        if ([value isKindOfClass:[NSDictionary class]]) {
            ruleCount += [(NSDictionary *)value count];
        }
    }

    if (ruleCount == 0) {
        return @"未设置";
    }

    return [NSString stringWithFormat:@"%ld 条",
            (long)ruleCount];
}

- (void)setAppComponentSwitchOverrideForBundleID:(NSString *)bundleID
                                    componentKey:(NSString *)componentKey
                                           value:(NSNumber *)value {
    NSString *normalized =
        [[bundleID
          stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]]
         lowercaseString];

    if (normalized.length == 0 ||
        componentKey.length == 0) {
        return;
    }

    HBPreferences *preferences = [self preferences];

    NSDictionary *stored =
        [preferences objectForKey:@"AppComponentSwitchOverrides"];

    NSMutableDictionary *allProfiles =
        [stored isKindOfClass:[NSDictionary class]]
        ? [stored mutableCopy]
        : [NSMutableDictionary dictionary];

    NSDictionary *existingRules =
        [allProfiles[normalized]
         isKindOfClass:[NSDictionary class]]
        ? allProfiles[normalized]
        : @{};

    NSMutableDictionary *rules =
        [existingRules mutableCopy];

    if (value) {
        rules[componentKey] = @([value boolValue]);
    } else {
        [rules removeObjectForKey:componentKey];
    }

    if (rules.count == 0) {
        [allProfiles removeObjectForKey:normalized];
    } else {
        allProfiles[normalized] = [rules copy];
    }

    [preferences setObject:[allProfiles copy]
                    forKey:@"AppComponentSwitchOverrides"];

    [self postReloadNotification];
    [self reloadSpecifiers];
}

- (void)chooseAppComponentSwitchValueForBundleID:(NSString *)bundleID
                                     componentKey:(NSString *)componentKey {
    NSDictionary *names =
        [self appComponentSwitchNames];

    NSString *componentName =
        names[componentKey] ?: componentKey;

    UIAlertController *sheet =
        [UIAlertController alertControllerWithTitle:componentName
                                            message:bundleID
                                     preferredStyle:UIAlertControllerStyleActionSheet];

    __weak typeof(self) weakSelf = self;

    [sheet addAction:
        [UIAlertAction actionWithTitle:@"强制开启"
                                 style:UIAlertActionStyleDefault
                               handler:^(__unused UIAlertAction *action) {
        [weakSelf
            setAppComponentSwitchOverrideForBundleID:bundleID
                                        componentKey:componentKey
                                               value:@YES];
    }]];

    [sheet addAction:
        [UIAlertAction actionWithTitle:@"强制关闭"
                                 style:UIAlertActionStyleDestructive
                               handler:^(__unused UIAlertAction *action) {
        [weakSelf
            setAppComponentSwitchOverrideForBundleID:bundleID
                                        componentKey:componentKey
                                               value:@NO];
    }]];

    [sheet addAction:
        [UIAlertAction actionWithTitle:@"跟随全局"
                                 style:UIAlertActionStyleDefault
                               handler:^(__unused UIAlertAction *action) {
        [weakSelf
            setAppComponentSwitchOverrideForBundleID:bundleID
                                        componentKey:componentKey
                                               value:nil];
    }]];

    [sheet addAction:
        [UIAlertAction actionWithTitle:@"取消"
                                 style:UIAlertActionStyleCancel
                               handler:nil]];

    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = self.view;
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

- (void)chooseAppComponentSwitchForBundleID:(NSString *)bundleID {
    UIAlertController *sheet =
        [UIAlertController alertControllerWithTitle:@"选择组件"
                                            message:bundleID
                                     preferredStyle:UIAlertControllerStyleActionSheet];

    NSDictionary *names =
        [self appComponentSwitchNames];

    __weak typeof(self) weakSelf = self;

    for (NSString *key in [self orderedAppComponentSwitchKeys]) {
        NSString *title = names[key] ?: key;

        [sheet addAction:
            [UIAlertAction actionWithTitle:title
                                     style:UIAlertActionStyleDefault
                                   handler:^(__unused UIAlertAction *action) {
            [weakSelf
                chooseAppComponentSwitchValueForBundleID:bundleID
                                             componentKey:key];
        }]];
    }

    [sheet addAction:
        [UIAlertAction actionWithTitle:@"取消"
                                 style:UIAlertActionStyleCancel
                               handler:nil]];

    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = self.view;
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

- (void)addOrEditAppComponentSwitchOverride {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"App 组件开关"
                                            message:@"输入 Bundle ID，然后选择组件以及强制开启 / 强制关闭 / 跟随全局。"
                                     preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:
        ^(UITextField *textField) {
        textField.placeholder = @"例如 com.apple.AppStore";
        textField.autocorrectionType =
            UITextAutocorrectionTypeNo;
        textField.autocapitalizationType =
            UITextAutocapitalizationTypeNone;
        textField.clearButtonMode =
            UITextFieldViewModeWhileEditing;
    }];

    [alert addAction:
        [UIAlertAction actionWithTitle:@"取消"
                                 style:UIAlertActionStyleCancel
                               handler:nil]];

    __weak typeof(self) weakSelf = self;

    [alert addAction:
        [UIAlertAction actionWithTitle:@"下一步"
                                 style:UIAlertActionStyleDefault
                               handler:^(__unused UIAlertAction *action) {

        NSString *bundleID =
            alert.textFields.firstObject.text ?: @"";

        bundleID =
            [bundleID stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]];

        if (bundleID.length == 0) {
            return;
        }

        [weakSelf chooseAppComponentSwitchForBundleID:bundleID];
    }]];

    [self presentViewController:alert
                       animated:YES
                     completion:nil];
}

- (void)removeAppComponentSwitchOverride {
    NSDictionary *profiles =
        [self appComponentSwitchOverrides];

    NSDictionary *names =
        [self appComponentSwitchNames];

    NSMutableArray<NSDictionary *> *entries =
        [NSMutableArray array];

    for (NSString *bundleID in profiles) {
        id rawRules = profiles[bundleID];

        if (![rawRules isKindOfClass:[NSDictionary class]]) {
            continue;
        }

        NSDictionary *rules = rawRules;

        for (NSString *componentKey in rules) {
            id rawValue = rules[componentKey];

            if (![rawValue respondsToSelector:@selector(boolValue)]) {
                continue;
            }

            [entries addObject:@{
                @"bundleID": bundleID,
                @"componentKey": componentKey,
                @"componentName": names[componentKey] ?: componentKey,
                @"enabled": @([rawValue boolValue])
            }];
        }
    }

    if (entries.count == 0) {
        UIAlertController *empty =
            [UIAlertController alertControllerWithTitle:@"没有开关规则"
                                                message:@"当前没有可删除的 App 独立组件开关。"
                                         preferredStyle:UIAlertControllerStyleAlert];

        [empty addAction:
            [UIAlertAction actionWithTitle:@"好"
                                     style:UIAlertActionStyleDefault
                                   handler:nil]];

        [self presentViewController:empty
                           animated:YES
                         completion:nil];
        return;
    }

    [entries sortUsingComparator:
        ^NSComparisonResult(NSDictionary *left,
                            NSDictionary *right) {
        NSString *a =
            [NSString stringWithFormat:@"%@ %@",
             left[@"bundleID"],
             left[@"componentName"]];

        NSString *b =
            [NSString stringWithFormat:@"%@ %@",
             right[@"bundleID"],
             right[@"componentName"]];

        return [a localizedCaseInsensitiveCompare:b];
    }];

    UIAlertController *sheet =
        [UIAlertController alertControllerWithTitle:@"删除 App 组件开关"
                                            message:nil
                                     preferredStyle:UIAlertControllerStyleActionSheet];

    __weak typeof(self) weakSelf = self;

    for (NSDictionary *entry in entries) {
        NSString *bundleID = entry[@"bundleID"];
        NSString *componentKey = entry[@"componentKey"];
        BOOL enabled = [entry[@"enabled"] boolValue];

        NSString *title =
            [NSString stringWithFormat:@"%@ · %@ · %@",
             bundleID,
             entry[@"componentName"],
             enabled ? @"开" : @"关"];

        [sheet addAction:
            [UIAlertAction actionWithTitle:title
                                     style:UIAlertActionStyleDestructive
                                   handler:^(__unused UIAlertAction *action) {
            [weakSelf
                setAppComponentSwitchOverrideForBundleID:bundleID
                                            componentKey:componentKey
                                                   value:nil];
        }]];
    }

    [sheet addAction:
        [UIAlertAction actionWithTitle:@"取消"
                                 style:UIAlertActionStyleCancel
                               handler:nil]];

    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = self.view;
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

- (void)clearAppComponentSwitchOverrides {
    NSDictionary *profiles =
        [self appComponentSwitchOverrides];

    if (profiles.count == 0) {
        return;
    }

    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"清空 App 组件开关"
                                            message:@"删除全部 App 独立组件开关配置？"
                                     preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:
        [UIAlertAction actionWithTitle:@"取消"
                                 style:UIAlertActionStyleCancel
                               handler:nil]];

    __weak typeof(self) weakSelf = self;

    [alert addAction:
        [UIAlertAction actionWithTitle:@"清空"
                                 style:UIAlertActionStyleDestructive
                               handler:^(__unused UIAlertAction *action) {
        HBPreferences *preferences =
            [weakSelf preferences];

        [preferences
            removeObjectForKey:@"AppComponentSwitchOverrides"];

        [weakSelf postReloadNotification];
        [weakSelf reloadSpecifiers];
    }]];

    [self presentViewController:alert
                       animated:YES
                     completion:nil];
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
                                            message:@"将主色、App 独立主色、App 独立组件颜色、App 独立组件开关、全局组件颜色、组件开关以及 App 排除列表全部恢复为默认值。"
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
