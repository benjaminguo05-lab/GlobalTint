#import <UIKit/UIKit.h>
#import <Cephei/HBPreferences.h>
#import <objc/runtime.h>

static NSString * const GTPrefsIdentifier = @"com.benja.globaltint";

static HBPreferences *GTPreferences = nil;
static NSHashTable<UIWindow *> *GTWindows = nil;

static BOOL GTEnabled = YES;
static BOOL GTApplyWindowTint = YES;
static BOOL GTApplyControls = YES;
static BOOL GTApplyBars = YES;
static NSString *GTAccentHex = @"#0A84FF";
static UIColor *GTAccentColor = nil;

// Associated-object keys used to remember original colors.
// This lets us restore most properties when GlobalTint is disabled.
static char GTOriginalTintColorKey;
static char GTOriginalSwitchOnTintColorKey;
static char GTOriginalSliderMinimumTrackTintColorKey;
static char GTOriginalProgressTintColorKey;
static char GTOriginalSegmentTintColorKey;
static char GTOriginalPageCurrentTintColorKey;

#pragma mark - Color helpers

static UIColor *GTColorFromHex(NSString *hex) {
    if (![hex isKindOfClass:[NSString class]]) {
        return [UIColor colorWithRed:10.0/255.0
                               green:132.0/255.0
                                blue:1.0
                               alpha:1.0];
    }

    NSString *clean = [[hex stringByTrimmingCharactersInSet:
                        [NSCharacterSet whitespaceAndNewlineCharacterSet]]
                        stringByReplacingOccurrencesOfString:@"#" withString:@""];

    if (clean.length == 3) {
        unichar r = [clean characterAtIndex:0];
        unichar g = [clean characterAtIndex:1];
        unichar b = [clean characterAtIndex:2];
        clean = [NSString stringWithFormat:@"%C%C%C%C%C%C", r, r, g, g, b, b];
    }

    if (clean.length != 6 && clean.length != 8) {
        return [UIColor colorWithRed:10.0/255.0
                               green:132.0/255.0
                                blue:1.0
                               alpha:1.0];
    }

    unsigned long long value = 0;
    NSScanner *scanner = [NSScanner scannerWithString:clean];
    if (![scanner scanHexLongLong:&value]) {
        return [UIColor colorWithRed:10.0/255.0
                               green:132.0/255.0
                                blue:1.0
                               alpha:1.0];
    }

    CGFloat r = 0.0, g = 0.0, b = 0.0, a = 1.0;

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

static void GTRunOnMain(dispatch_block_t block) {
    if (!block) return;

    if ([NSThread isMainThread]) {
        block();
    } else {
        dispatch_async(dispatch_get_main_queue(), block);
    }
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
    if (!object || !key) return;

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
    if (!object || !key) return;
    objc_setAssociatedObject(object, key, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - Tint application / restoration

static void GTApplyOrRestoreTint(UIView *view, BOOL shouldApply) {
    if (!view) return;

    if (shouldApply && GTAccentColor) {
        GTRememberColorOnce(view, &GTOriginalTintColorKey, view.tintColor);
        view.tintColor = GTAccentColor;
    } else if (GTHasRememberedColor(view, &GTOriginalTintColorKey)) {
        view.tintColor = GTRememberedColor(view, &GTOriginalTintColorKey);
        GTClearRememberedColor(view, &GTOriginalTintColorKey);
    }
}

static void GTApplySwitch(UISwitch *control) {
    BOOL shouldApply = GTEnabled && GTApplyControls;

    if (shouldApply && GTAccentColor) {
        GTRememberColorOnce(control,
                            &GTOriginalSwitchOnTintColorKey,
                            control.onTintColor);
        control.onTintColor = GTAccentColor;
    } else if (GTHasRememberedColor(control, &GTOriginalSwitchOnTintColorKey)) {
        control.onTintColor =
            GTRememberedColor(control, &GTOriginalSwitchOnTintColorKey);
        GTClearRememberedColor(control, &GTOriginalSwitchOnTintColorKey);
    }
}

static void GTApplySlider(UISlider *control) {
    BOOL shouldApply = GTEnabled && GTApplyControls;

    GTApplyOrRestoreTint(control, shouldApply);

    if (shouldApply && GTAccentColor) {
        GTRememberColorOnce(control,
                            &GTOriginalSliderMinimumTrackTintColorKey,
                            control.minimumTrackTintColor);
        control.minimumTrackTintColor = GTAccentColor;
    } else if (GTHasRememberedColor(control,
                                    &GTOriginalSliderMinimumTrackTintColorKey)) {
        control.minimumTrackTintColor =
            GTRememberedColor(control, &GTOriginalSliderMinimumTrackTintColorKey);
        GTClearRememberedColor(control, &GTOriginalSliderMinimumTrackTintColorKey);
    }
}

static void GTApplyProgress(UIProgressView *control) {
    BOOL shouldApply = GTEnabled && GTApplyControls;

    if (shouldApply && GTAccentColor) {
        GTRememberColorOnce(control,
                            &GTOriginalProgressTintColorKey,
                            control.progressTintColor);
        control.progressTintColor = GTAccentColor;
    } else if (GTHasRememberedColor(control, &GTOriginalProgressTintColorKey)) {
        control.progressTintColor =
            GTRememberedColor(control, &GTOriginalProgressTintColorKey);
        GTClearRememberedColor(control, &GTOriginalProgressTintColorKey);
    }
}

static void GTApplySegmented(UISegmentedControl *control) {
    BOOL shouldApply = GTEnabled && GTApplyControls;

    GTApplyOrRestoreTint(control, shouldApply);

    if (@available(iOS 13.0, *)) {
        if (shouldApply && GTAccentColor) {
            GTRememberColorOnce(control,
                                &GTOriginalSegmentTintColorKey,
                                control.selectedSegmentTintColor);
            control.selectedSegmentTintColor = GTAccentColor;
        } else if (GTHasRememberedColor(control, &GTOriginalSegmentTintColorKey)) {
            control.selectedSegmentTintColor =
                GTRememberedColor(control, &GTOriginalSegmentTintColorKey);
            GTClearRememberedColor(control, &GTOriginalSegmentTintColorKey);
        }
    }
}

static void GTApplyPageControl(UIPageControl *control) {
    BOOL shouldApply = GTEnabled && GTApplyControls;

    if (shouldApply && GTAccentColor) {
        GTRememberColorOnce(control,
                            &GTOriginalPageCurrentTintColorKey,
                            control.currentPageIndicatorTintColor);
        control.currentPageIndicatorTintColor = GTAccentColor;
    } else if (GTHasRememberedColor(control, &GTOriginalPageCurrentTintColorKey)) {
        control.currentPageIndicatorTintColor =
            GTRememberedColor(control, &GTOriginalPageCurrentTintColorKey);
        GTClearRememberedColor(control, &GTOriginalPageCurrentTintColorKey);
    }
}

static void GTApplyGenericControlTint(UIView *view) {
    GTApplyOrRestoreTint(view, GTEnabled && GTApplyControls);
}

static void GTApplyBarTint(UIView *view) {
    GTApplyOrRestoreTint(view, GTEnabled && GTApplyBars);
}

static void GTApplyManagedPropertiesToView(UIView *view) {
    if (!view) return;

    if ([view isKindOfClass:[UIWindow class]]) {
        GTApplyOrRestoreTint(view, GTEnabled && GTApplyWindowTint);
    }

    if ([view isKindOfClass:[UISwitch class]]) {
        GTApplySwitch((UISwitch *)view);
    } else if ([view isKindOfClass:[UISlider class]]) {
        GTApplySlider((UISlider *)view);
    } else if ([view isKindOfClass:[UIProgressView class]]) {
        GTApplyProgress((UIProgressView *)view);
    } else if ([view isKindOfClass:[UISegmentedControl class]]) {
        GTApplySegmented((UISegmentedControl *)view);
    } else if ([view isKindOfClass:[UIPageControl class]]) {
        GTApplyPageControl((UIPageControl *)view);
    } else if ([view isKindOfClass:[UIRefreshControl class]]) {
        GTApplyGenericControlTint(view);
    }

    if ([view isKindOfClass:[UINavigationBar class]] ||
        [view isKindOfClass:[UITabBar class]] ||
        [view isKindOfClass:[UIToolbar class]] ||
        [view isKindOfClass:[UISearchBar class]]) {
        GTApplyBarTint(view);
    }
}

static void GTApplyRecursively(UIView *view) {
    if (!view) return;

    GTApplyManagedPropertiesToView(view);

    for (UIView *subview in view.subviews) {
        GTApplyRecursively(subview);
    }
}

static void GTRegisterAndApplyWindow(UIWindow *window) {
    if (!window) return;

    if (!GTWindows) {
        GTWindows = [NSHashTable weakObjectsHashTable];
    }

    [GTWindows addObject:window];
    GTApplyRecursively(window);
}

static void GTRefreshKnownWindows(void) {
    GTRunOnMain(^{
        NSArray<UIWindow *> *windows = GTWindows.allObjects;
        for (UIWindow *window in windows) {
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
    GTApplySwitch(self);
}
%end

%hook UISlider
- (void)didMoveToWindow {
    %orig;
    GTApplySlider(self);
}
%end

%hook UIProgressView
- (void)didMoveToWindow {
    %orig;
    GTApplyProgress(self);
}
%end

%hook UISegmentedControl
- (void)didMoveToWindow {
    %orig;
    GTApplySegmented(self);
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
    GTApplyGenericControlTint(self);
}
%end

#pragma mark - Navigation / bars

%hook UINavigationBar
- (void)didMoveToWindow {
    %orig;
    GTApplyBarTint(self);
}
%end

%hook UITabBar
- (void)didMoveToWindow {
    %orig;
    GTApplyBarTint(self);
}
%end

%hook UIToolbar
- (void)didMoveToWindow {
    %orig;
    GTApplyBarTint(self);
}
%end

%hook UISearchBar
- (void)didMoveToWindow {
    %orig;
    GTApplyBarTint(self);
}
%end

#pragma mark - Bootstrap

%ctor {
    @autoreleasepool {
        // Keep V1 conservative: do not inject behavior into app extensions
        // (widgets, share extensions, keyboards, etc.).
        NSString *bundleExtension =
            NSBundle.mainBundle.bundleURL.pathExtension.lowercaseString;

        if ([bundleExtension isEqualToString:@"appex"]) {
            return;
        }

        GTWindows = [NSHashTable weakObjectsHashTable];

        GTPreferences =
            [[HBPreferences alloc] initWithIdentifier:GTPrefsIdentifier];

        [GTPreferences registerBool:&GTEnabled
                           default:YES
                            forKey:@"Enabled"];

        [GTPreferences registerBool:&GTApplyWindowTint
                           default:YES
                            forKey:@"ApplyWindowTint"];

        [GTPreferences registerBool:&GTApplyControls
                           default:YES
                            forKey:@"ApplyControls"];

        [GTPreferences registerBool:&GTApplyBars
                           default:YES
                            forKey:@"ApplyBars"];

        [GTPreferences registerObject:(id *)&GTAccentHex
                              default:@"#0A84FF"
                               forKey:@"AccentColor"];

        [GTPreferences registerPreferenceChangeBlock:^{
            GTAccentColor = GTColorFromHex(GTAccentHex);
            GTRefreshKnownWindows();
        }];

        // A custom Logos constructor is used, so initialize the default hook group explicitly.
        %init;
    }
}
