#import <UIKit/UIKit.h>
#import <Cephei/HBPreferences.h>
#import <objc/runtime.h>

static NSString * const GTPrefsIdentifier = @"com.benja.globaltint";

static HBPreferences *GTPreferences = nil;
static NSHashTable<UIWindow *> *GTWindows = nil;
static NSSet<NSString *> *GTExcludedBundles = nil;

// Master
static BOOL GTEnabled = YES;

// Compatibility master switches from V0.1.x
static BOOL GTApplyControls = YES;
static BOOL GTApplyBars = YES;

// V0.2 component switches
static BOOL GTEnableWindowTint = YES;

static BOOL GTEnableSwitch = YES;
static BOOL GTEnableSlider = YES;
static BOOL GTEnableProgress = YES;
static BOOL GTEnableSegmented = YES;
static BOOL GTEnablePageControl = YES;
static BOOL GTEnableRefreshControl = YES;

static BOOL GTEnableNavigationBar = YES;
static BOOL GTEnableTabBar = YES;
static BOOL GTEnableToolbar = YES;
static BOOL GTEnableSearchBar = YES;

// Color mode
static BOOL GTUseSeparateColors = NO;

// Preferences strings
static NSString *GTAccentHex = @"#0A84FF";
static NSString *GTWindowHex = @"";

static NSString *GTSwitchHex = @"";
static NSString *GTSliderHex = @"";
static NSString *GTProgressHex = @"";
static NSString *GTSegmentedHex = @"";
static NSString *GTPageControlHex = @"";
static NSString *GTRefreshControlHex = @"";

static NSString *GTNavigationBarHex = @"";
static NSString *GTTabBarHex = @"";
static NSString *GTToolbarHex = @"";
static NSString *GTSearchBarHex = @"";

static NSString *GTExcludedBundleIDs = @"";

static UIColor *GTAccentColor = nil;

// Remember original values so toggles / exclusions can restore UI.
static char GTOriginalTintColorKey;
static char GTOriginalSwitchOnTintColorKey;
static char GTOriginalSliderMinimumTrackTintColorKey;
static char GTOriginalProgressTintColorKey;
static char GTOriginalSegmentTintColorKey;
static char GTOriginalPageCurrentTintColorKey;

#pragma mark - Color helpers

static UIColor *GTDefaultAccentColor(void) {
    return [UIColor colorWithRed:10.0/255.0
                           green:132.0/255.0
                            blue:1.0
                           alpha:1.0];
}

static UIColor *GTColorFromHexOrNil(NSString *hex) {
    if (![hex isKindOfClass:[NSString class]]) {
        return nil;
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

    if (clean.length != 6 && clean.length != 8) {
        return nil;
    }

    unsigned long long value = 0;
    if (![[NSScanner scannerWithString:clean] scanHexLongLong:&value]) {
        return nil;
    }

    CGFloat r = 0.0;
    CGFloat g = 0.0;
    CGFloat b = 0.0;
    CGFloat a = 1.0;

    if (clean.length == 6) {
        r = ((value >> 16) & 0xFF) / 255.0;
        g = ((value >> 8) & 0xFF) / 255.0;
        b = (value & 0xFF) / 255.0;
    } else {
        r = ((value >> 24) & 0xFF) / 255.0;
        g = ((value >> 16) & 0xFF) / 255.0;
        b = ((value >> 8) & 0xFF) / 255.0;
        a = (value & 0xFF) / 255.0;
    }

    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

static UIColor *GTColorForComponentHex(NSString *componentHex) {
    if (!GTAccentColor) {
        GTAccentColor = GTColorFromHexOrNil(GTAccentHex) ?: GTDefaultAccentColor();
    }

    if (!GTUseSeparateColors) {
        return GTAccentColor;
    }

    return GTColorFromHexOrNil(componentHex) ?: GTAccentColor;
}

static void GTRunOnMain(dispatch_block_t block) {
    if (!block) {
        return;
    }

    if ([NSThread isMainThread]) {
        block();
    } else {
        dispatch_async(dispatch_get_main_queue(), block);
    }
}

#pragma mark - App exclusions

static void GTRebuildExcludedBundles(void) {
    NSMutableSet<NSString *> *result = [NSMutableSet set];

    if ([GTExcludedBundleIDs isKindOfClass:[NSString class]] &&
        GTExcludedBundleIDs.length > 0) {

        NSCharacterSet *separators =
            [NSCharacterSet characterSetWithCharactersInString:@",;\n\r\t "];

        NSArray<NSString *> *parts =
            [GTExcludedBundleIDs componentsSeparatedByCharactersInSet:separators];

        for (NSString *part in parts) {
            NSString *clean =
                [[part stringByTrimmingCharactersInSet:
                  [NSCharacterSet whitespaceAndNewlineCharacterSet]]
                  lowercaseString];

            if (clean.length > 0) {
                [result addObject:clean];
            }
        }
    }

    GTExcludedBundles = [result copy];
}

static BOOL GTCurrentProcessIsExcluded(void) {
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier.lowercaseString;

    if (bundleID.length == 0 || GTExcludedBundles.count == 0) {
        return NO;
    }

    return [GTExcludedBundles containsObject:bundleID];
}

static BOOL GTShouldApplyBase(void) {
    return GTEnabled && !GTCurrentProcessIsExcluded();
}

#pragma mark - Original color storage

static id GTBoxColor(UIColor *color) {
    return color ?: (id)[NSNull null];
}

static UIColor *GTUnboxColor(id value) {
    if (!value || value == [NSNull null]) {
        return nil;
    }

    return [value isKindOfClass:[UIColor class]] ? value : nil;
}

static void GTRememberColorOnce(id object, const void *key, UIColor *color) {
    if (!object || !key) {
        return;
    }

    if (!objc_getAssociatedObject(object, key)) {
        objc_setAssociatedObject(object,
                                 key,
                                 GTBoxColor(color),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static BOOL GTHasRememberedColor(id object, const void *key) {
    return object && key && objc_getAssociatedObject(object, key) != nil;
}

static UIColor *GTRememberedColor(id object, const void *key) {
    return GTUnboxColor(objc_getAssociatedObject(object, key));
}

static void GTClearRememberedColor(id object, const void *key) {
    if (!object || !key) {
        return;
    }

    objc_setAssociatedObject(object, key, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - Apply / restore helpers

static void GTApplyOrRestoreTint(UIView *view,
                                 BOOL shouldApply,
                                 UIColor *color) {
    if (!view) {
        return;
    }

    if (shouldApply && color) {
        GTRememberColorOnce(view, &GTOriginalTintColorKey, view.tintColor);
        view.tintColor = color;
    } else if (GTHasRememberedColor(view, &GTOriginalTintColorKey)) {
        view.tintColor = GTRememberedColor(view, &GTOriginalTintColorKey);
        GTClearRememberedColor(view, &GTOriginalTintColorKey);
    }
}

static void GTApplyWindow(UIWindow *window) {
    BOOL apply = GTShouldApplyBase() && GTEnableWindowTint;
    GTApplyOrRestoreTint(window, apply, GTColorForComponentHex(GTWindowHex));
}

static void GTApplySwitchControl(UISwitch *control) {
    BOOL apply =
        GTShouldApplyBase() &&
        GTApplyControls &&
        GTEnableSwitch;

    UIColor *color = GTColorForComponentHex(GTSwitchHex);

    if (apply && color) {
        GTRememberColorOnce(control,
                            &GTOriginalSwitchOnTintColorKey,
                            control.onTintColor);
        control.onTintColor = color;
    } else if (GTHasRememberedColor(control,
                                    &GTOriginalSwitchOnTintColorKey)) {
        control.onTintColor =
            GTRememberedColor(control, &GTOriginalSwitchOnTintColorKey);
        GTClearRememberedColor(control, &GTOriginalSwitchOnTintColorKey);
    }
}

static void GTApplySliderControl(UISlider *control) {
    BOOL apply =
        GTShouldApplyBase() &&
        GTApplyControls &&
        GTEnableSlider;

    UIColor *color = GTColorForComponentHex(GTSliderHex);

    GTApplyOrRestoreTint(control, apply, color);

    if (apply && color) {
        GTRememberColorOnce(control,
                            &GTOriginalSliderMinimumTrackTintColorKey,
                            control.minimumTrackTintColor);
        control.minimumTrackTintColor = color;
    } else if (GTHasRememberedColor(control,
                                    &GTOriginalSliderMinimumTrackTintColorKey)) {
        control.minimumTrackTintColor =
            GTRememberedColor(control,
                              &GTOriginalSliderMinimumTrackTintColorKey);
        GTClearRememberedColor(control,
                               &GTOriginalSliderMinimumTrackTintColorKey);
    }
}

static void GTApplyProgressControl(UIProgressView *control) {
    BOOL apply =
        GTShouldApplyBase() &&
        GTApplyControls &&
        GTEnableProgress;

    UIColor *color = GTColorForComponentHex(GTProgressHex);

    if (apply && color) {
        GTRememberColorOnce(control,
                            &GTOriginalProgressTintColorKey,
                            control.progressTintColor);
        control.progressTintColor = color;
    } else if (GTHasRememberedColor(control,
                                    &GTOriginalProgressTintColorKey)) {
        control.progressTintColor =
            GTRememberedColor(control, &GTOriginalProgressTintColorKey);
        GTClearRememberedColor(control, &GTOriginalProgressTintColorKey);
    }
}

static void GTApplySegmentedControl(UISegmentedControl *control) {
    BOOL apply =
        GTShouldApplyBase() &&
        GTApplyControls &&
        GTEnableSegmented;

    UIColor *color = GTColorForComponentHex(GTSegmentedHex);

    GTApplyOrRestoreTint(control, apply, color);

    if (@available(iOS 13.0, *)) {
        if (apply && color) {
            GTRememberColorOnce(control,
                                &GTOriginalSegmentTintColorKey,
                                control.selectedSegmentTintColor);
            control.selectedSegmentTintColor = color;
        } else if (GTHasRememberedColor(control,
                                        &GTOriginalSegmentTintColorKey)) {
            control.selectedSegmentTintColor =
                GTRememberedColor(control, &GTOriginalSegmentTintColorKey);
            GTClearRememberedColor(control, &GTOriginalSegmentTintColorKey);
        }
    }
}

static void GTApplyPageControl(UIPageControl *control) {
    BOOL apply =
        GTShouldApplyBase() &&
        GTApplyControls &&
        GTEnablePageControl;

    UIColor *color = GTColorForComponentHex(GTPageControlHex);

    if (apply && color) {
        GTRememberColorOnce(control,
                            &GTOriginalPageCurrentTintColorKey,
                            control.currentPageIndicatorTintColor);
        control.currentPageIndicatorTintColor = color;
    } else if (GTHasRememberedColor(control,
                                    &GTOriginalPageCurrentTintColorKey)) {
        control.currentPageIndicatorTintColor =
            GTRememberedColor(control, &GTOriginalPageCurrentTintColorKey);
        GTClearRememberedColor(control, &GTOriginalPageCurrentTintColorKey);
    }
}

static void GTApplyRefreshControl(UIRefreshControl *control) {
    BOOL apply =
        GTShouldApplyBase() &&
        GTApplyControls &&
        GTEnableRefreshControl;

    GTApplyOrRestoreTint(control,
                         apply,
                         GTColorForComponentHex(GTRefreshControlHex));
}

static void GTApplyNavigationBar(UINavigationBar *bar) {
    BOOL apply =
        GTShouldApplyBase() &&
        GTApplyBars &&
        GTEnableNavigationBar;

    GTApplyOrRestoreTint(bar,
                         apply,
                         GTColorForComponentHex(GTNavigationBarHex));
}

static void GTApplyTabBar(UITabBar *bar) {
    BOOL apply =
        GTShouldApplyBase() &&
        GTApplyBars &&
        GTEnableTabBar;

    GTApplyOrRestoreTint(bar,
                         apply,
                         GTColorForComponentHex(GTTabBarHex));
}

static void GTApplyToolbar(UIToolbar *bar) {
    BOOL apply =
        GTShouldApplyBase() &&
        GTApplyBars &&
        GTEnableToolbar;

    GTApplyOrRestoreTint(bar,
                         apply,
                         GTColorForComponentHex(GTToolbarHex));
}

static void GTApplySearchBar(UISearchBar *bar) {
    BOOL apply =
        GTShouldApplyBase() &&
        GTApplyBars &&
        GTEnableSearchBar;

    GTApplyOrRestoreTint(bar,
                         apply,
                         GTColorForComponentHex(GTSearchBarHex));
}

static void GTApplyManagedPropertiesToView(UIView *view) {
    if (!view) {
        return;
    }

    if ([view isKindOfClass:[UIWindow class]]) {
        GTApplyWindow((UIWindow *)view);
    }

    if ([view isKindOfClass:[UISwitch class]]) {
        GTApplySwitchControl((UISwitch *)view);
    } else if ([view isKindOfClass:[UISlider class]]) {
        GTApplySliderControl((UISlider *)view);
    } else if ([view isKindOfClass:[UIProgressView class]]) {
        GTApplyProgressControl((UIProgressView *)view);
    } else if ([view isKindOfClass:[UISegmentedControl class]]) {
        GTApplySegmentedControl((UISegmentedControl *)view);
    } else if ([view isKindOfClass:[UIPageControl class]]) {
        GTApplyPageControl((UIPageControl *)view);
    } else if ([view isKindOfClass:[UIRefreshControl class]]) {
        GTApplyRefreshControl((UIRefreshControl *)view);
    }

    if ([view isKindOfClass:[UINavigationBar class]]) {
        GTApplyNavigationBar((UINavigationBar *)view);
    } else if ([view isKindOfClass:[UITabBar class]]) {
        GTApplyTabBar((UITabBar *)view);
    } else if ([view isKindOfClass:[UIToolbar class]]) {
        GTApplyToolbar((UIToolbar *)view);
    } else if ([view isKindOfClass:[UISearchBar class]]) {
        GTApplySearchBar((UISearchBar *)view);
    }
}

static void GTApplyRecursively(UIView *view) {
    if (!view) {
        return;
    }

    GTApplyManagedPropertiesToView(view);

    for (UIView *subview in view.subviews) {
        GTApplyRecursively(subview);
    }
}

static void GTRegisterAndApplyWindow(UIWindow *window) {
    if (!window) {
        return;
    }

    if (!GTWindows) {
        GTWindows = [NSHashTable weakObjectsHashTable];
    }

    [GTWindows addObject:window];
    GTApplyRecursively(window);
}

static void GTRefreshKnownWindows(void) {
    GTRunOnMain(^{
        for (UIWindow *window in GTWindows.allObjects) {
            GTApplyRecursively(window);
        }
    });
}

#pragma mark - UIWindow

%hook UIWindow

- (void)makeKeyAndVisible {
    %orig;
    GTRegisterAndApplyWindow(self);
}

- (void)becomeKeyWindow {
    %orig;
    GTRegisterAndApplyWindow(self);
}

- (void)setHidden:(BOOL)hidden {
    %orig(hidden);

    if (!hidden) {
        GTRegisterAndApplyWindow(self);
    }
}

- (void)setRootViewController:(UIViewController *)rootViewController {
    %orig(rootViewController);
    GTRegisterAndApplyWindow(self);
}

%end

#pragma mark - Standard UIKit controls

%hook UISwitch
- (void)didMoveToWindow {
    %orig;
    GTApplySwitchControl(self);
}
%end

%hook UISlider
- (void)didMoveToWindow {
    %orig;
    GTApplySliderControl(self);
}
%end

%hook UIProgressView
- (void)didMoveToWindow {
    %orig;
    GTApplyProgressControl(self);
}
%end

%hook UISegmentedControl
- (void)didMoveToWindow {
    %orig;
    GTApplySegmentedControl(self);
}
%end

%hook UIPageControl
- (void)didMoveToWindow {
    %orig;
    GTApplyPageControl(self);
}
%end

%hook UIRefreshControl
- (void)didMoveToWindow {
    %orig;
    GTApplyRefreshControl(self);
}
%end

#pragma mark - Navigation / bars

%hook UINavigationBar
- (void)didMoveToWindow {
    %orig;
    GTApplyNavigationBar(self);
}
%end

%hook UITabBar
- (void)didMoveToWindow {
    %orig;
    GTApplyTabBar(self);
}
%end

%hook UIToolbar
- (void)didMoveToWindow {
    %orig;
    GTApplyToolbar(self);
}
%end

%hook UISearchBar
- (void)didMoveToWindow {
    %orig;
    GTApplySearchBar(self);
}
%end

#pragma mark - Preferences

static void GTRegisterPreferences(void) {
    GTPreferences =
        [[HBPreferences alloc] initWithIdentifier:GTPrefsIdentifier];

    [GTPreferences registerBool:&GTEnabled
                         default:YES
                          forKey:@"Enabled"];

    [GTPreferences registerBool:&GTEnableWindowTint
                         default:YES
                          forKey:@"ApplyWindowTint"];

    // Keep V0.1.x master switches for upgrade compatibility.
    [GTPreferences registerBool:&GTApplyControls
                         default:YES
                          forKey:@"ApplyControls"];

    [GTPreferences registerBool:&GTApplyBars
                         default:YES
                          forKey:@"ApplyBars"];

    [GTPreferences registerBool:&GTUseSeparateColors
                         default:NO
                          forKey:@"UseSeparateColors"];

    [GTPreferences registerBool:&GTEnableSwitch
                         default:YES
                          forKey:@"ApplySwitch"];

    [GTPreferences registerBool:&GTEnableSlider
                         default:YES
                          forKey:@"ApplySlider"];

    [GTPreferences registerBool:&GTEnableProgress
                         default:YES
                          forKey:@"ApplyProgress"];

    [GTPreferences registerBool:&GTEnableSegmented
                         default:YES
                          forKey:@"ApplySegmented"];

    [GTPreferences registerBool:&GTEnablePageControl
                         default:YES
                          forKey:@"ApplyPageControl"];

    [GTPreferences registerBool:&GTEnableRefreshControl
                         default:YES
                          forKey:@"ApplyRefreshControl"];

    [GTPreferences registerBool:&GTEnableNavigationBar
                         default:YES
                          forKey:@"ApplyNavigationBar"];

    [GTPreferences registerBool:&GTEnableTabBar
                         default:YES
                          forKey:@"ApplyTabBar"];

    [GTPreferences registerBool:&GTEnableToolbar
                         default:YES
                          forKey:@"ApplyToolbar"];

    [GTPreferences registerBool:&GTEnableSearchBar
                         default:YES
                          forKey:@"ApplySearchBar"];

    [GTPreferences registerObject:(id *)&GTAccentHex
                          default:@"#0A84FF"
                           forKey:@"AccentColor"];

    [GTPreferences registerObject:(id *)&GTWindowHex
                          default:@""
                           forKey:@"WindowColor"];

    [GTPreferences registerObject:(id *)&GTSwitchHex
                          default:@""
                           forKey:@"SwitchColor"];

    [GTPreferences registerObject:(id *)&GTSliderHex
                          default:@""
                           forKey:@"SliderColor"];

    [GTPreferences registerObject:(id *)&GTProgressHex
                          default:@""
                           forKey:@"ProgressColor"];

    [GTPreferences registerObject:(id *)&GTSegmentedHex
                          default:@""
                           forKey:@"SegmentedColor"];

    [GTPreferences registerObject:(id *)&GTPageControlHex
                          default:@""
                           forKey:@"PageControlColor"];

    [GTPreferences registerObject:(id *)&GTRefreshControlHex
                          default:@""
                           forKey:@"RefreshControlColor"];

    [GTPreferences registerObject:(id *)&GTNavigationBarHex
                          default:@""
                           forKey:@"NavigationBarColor"];

    [GTPreferences registerObject:(id *)&GTTabBarHex
                          default:@""
                           forKey:@"TabBarColor"];

    [GTPreferences registerObject:(id *)&GTToolbarHex
                          default:@""
                           forKey:@"ToolbarColor"];

    [GTPreferences registerObject:(id *)&GTSearchBarHex
                          default:@""
                           forKey:@"SearchBarColor"];

    [GTPreferences registerObject:(id *)&GTExcludedBundleIDs
                          default:@""
                           forKey:@"ExcludedBundleIDs"];

    GTAccentColor = GTColorFromHexOrNil(GTAccentHex) ?: GTDefaultAccentColor();
    GTRebuildExcludedBundles();

    [GTPreferences registerPreferenceChangeBlock:^{
        GTAccentColor =
            GTColorFromHexOrNil(GTAccentHex) ?: GTDefaultAccentColor();

        GTRebuildExcludedBundles();
        GTRefreshKnownWindows();
    }];
}

#pragma mark - Bootstrap

%ctor {
    @autoreleasepool {
        // Keep app extensions out of V0.2 as well.
        NSString *bundleExtension =
            NSBundle.mainBundle.bundleURL.pathExtension.lowercaseString;

        if ([bundleExtension isEqualToString:@"appex"]) {
            return;
        }

        GTWindows = [NSHashTable weakObjectsHashTable];
        GTRegisterPreferences();

        // A custom Logos constructor is used, so initialize hooks explicitly.
        %init;
    }
}
