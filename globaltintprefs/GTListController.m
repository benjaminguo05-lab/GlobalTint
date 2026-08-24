#import "GTListController.h"

#import <Cephei/HBPreferences.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>

static NSString * const GTPrefsIdentifier = @"com.benja.globaltint";
static CFStringRef const GTReloadNotification =
    CFSTR("com.benja.globaltint/ReloadPrefs");

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
    CGFloat r = 0.0, g = 0.0, b = 0.0, a = 0.0;

    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        // UIColorPickerViewController normally returns an RGB-compatible UIColor.
        // Fall back to the default accent if conversion unexpectedly fails.
        r = 10.0 / 255.0;
        g = 132.0 / 255.0;
        b = 1.0;
    }

    NSInteger red = (NSInteger)llround(MAX(0.0, MIN(1.0, r)) * 255.0);
    NSInteger green = (NSInteger)llround(MAX(0.0, MIN(1.0, g)) * 255.0);
    NSInteger blue = (NSInteger)llround(MAX(0.0, MIN(1.0, b)) * 255.0);

    return [NSString stringWithFormat:@"#%02lX%02lX%02lX",
            (long)red, (long)green, (long)blue];
}

@implementation GTListController

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

- (NSMutableArray *)fallbackSpecifiers {
    NSMutableArray *items = [NSMutableArray array];

    PSSpecifier *mainGroup = [PSSpecifier groupSpecifierWithName:@"Global Tint"];
    [mainGroup setProperty:
        @"V0.1.6：修改 UIKit 全局 Tint，并可强制覆盖常见标准控件。"
        forKey:@"footerText"];
    [items addObject:mainGroup];

    [items addObject:
        [self switchSpecifierWithName:@"启用 Global Tint"
                                  key:@"Enabled"
                         defaultValue:YES]];

    PSSpecifier *colorValue =
        [PSSpecifier preferenceSpecifierNamed:@"当前主题色"
                                       target:self
                                          set:nil
                                          get:@selector(accentColorValue:)
                                       detail:nil
                                         cell:PSTitleValueCell
                                         edit:nil];
    [items addObject:colorValue];

    PSSpecifier *colorButton =
        [PSSpecifier preferenceSpecifierNamed:@"选择主题颜色"
                                       target:self
                                          set:nil
                                          get:nil
                                       detail:nil
                                         cell:PSButtonCell
                                         edit:nil];
    colorButton.buttonAction = @selector(chooseAccentColor);
    [items addObject:colorButton];

    PSSpecifier *scopeGroup = [PSSpecifier groupSpecifierWithName:@"应用范围"];
    [scopeGroup setProperty:
        @"“窗口全局 Tint”最稳定，建议保持开启。下面两项用于覆盖 App 自己显式设置的标准 UIKit 控件颜色。"
        forKey:@"footerText"];
    [items addObject:scopeGroup];

    [items addObject:
        [self switchSpecifierWithName:@"窗口全局 Tint"
                                  key:@"ApplyWindowTint"
                         defaultValue:YES]];

    [items addObject:
        [self switchSpecifierWithName:@"强制标准控件"
                                  key:@"ApplyControls"
                         defaultValue:YES]];

    [items addObject:
        [self switchSpecifierWithName:@"强制导航 / Tab Bar"
                                  key:@"ApplyBars"
                         defaultValue:YES]];

    PSSpecifier *infoGroup = [PSSpecifier emptyGroupSpecifier];
    [infoGroup setProperty:
        @"当前强制控件：UISwitch、UISlider、UIProgressView、UISegmentedControl、UIPageControl、UIRefreshControl；导航类包括 UINavigationBar、UITabBar、UIToolbar、UISearchBar。"
        forKey:@"footerText"];
    [items addObject:infoGroup];

    PSSpecifier *reset =
        [PSSpecifier preferenceSpecifierNamed:@"恢复默认设置"
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
        // On some RootHide/iOS 17 setups, the default loader may search the
        // wrong bundle. Explicitly point PSListController at our preference bundle.
        NSBundle *bundle = [NSBundle bundleForClass:[self class]];

        NSMutableArray *loaded =
            [self loadSpecifiersFromPlistName:@"Root"
                                       target:self
                                       bundle:bundle];

        if (loaded.count > 0) {
            _specifiers = loaded;
        } else {
            // Do not leave the page blank if plist loading fails.
            _specifiers = [self fallbackSpecifiers];
        }
    }

    return _specifiers;
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

- (id)accentColorValue:(PSSpecifier *)specifier {
    NSString *value = [[self preferences] objectForKey:@"AccentColor"];
    return [value isKindOfClass:[NSString class]] ? value : @"#0A84FF";
}

- (void)chooseAccentColor {
    if (@available(iOS 14.0, *)) {
        UIColorPickerViewController *picker =
            [[UIColorPickerViewController alloc] init];

        picker.delegate = self;
        picker.supportsAlpha = NO;

        NSString *hex = [[self preferences] objectForKey:@"AccentColor"];
        picker.selectedColor =
            GTColorFromHexString([hex isKindOfClass:[NSString class]]
                                 ? hex
                                 : @"#0A84FF");

        [self presentViewController:picker animated:YES completion:nil];
    }
}

- (void)colorPickerViewControllerDidSelectColor:
    (UIColorPickerViewController *)viewController API_AVAILABLE(ios(14.0)) {

    NSString *hex = GTHexStringFromColor(viewController.selectedColor);

    HBPreferences *preferences = [self preferences];
    [preferences setObject:hex forKey:@"AccentColor"];
    [self postReloadNotification];
}

- (void)colorPickerViewControllerDidFinish:
    (UIColorPickerViewController *)viewController API_AVAILABLE(ios(14.0)) {

    [self reloadSpecifiers];
}

- (void)resetPreferences {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"恢复默认设置"
                                            message:@"将主题色和所有开关恢复为默认值。"
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
