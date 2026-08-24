#import <UIKit/UIKit.h>
#import <Cephei/HBPreferences.h>
#import <objc/runtime.h>
#import <objc/message.h>


@interface BrowserToolbar : UIView
@end

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

// V0.2.2 compatibility / diagnostics
static BOOL GTReplaceSystemBlue = NO;
static BOOL GTReplaceLinkColor = NO;
static BOOL GTDebugInjectionBorder = NO;
static BOOL GTForceResolvedBlue = NO;
static NSString *GTSemanticBlueHex = @"";

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

// V0.2.1: UITabBarAppearance / UITabBarItem appearance restoration.
static char GTOriginalTabBarStandardAppearanceKey;
static char GTOriginalTabBarScrollEdgeAppearanceKey;
static char GTOriginalTabItemStandardAppearanceKey;
static char GTOriginalTabItemScrollEdgeAppearanceKey;
static char GTApplyingTabAppearanceKey;
static char GTOriginalWindowBorderWidthKey;
static char GTOriginalWindowBorderColorKey;
static char GTOriginalResolvedTintKey;
static char GTOriginalResolvedTextColorKey;

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


static UIColor *GTSemanticBlueColor(void) {
    if (!GTAccentColor) {
        GTAccentColor = GTColorFromHexOrNil(GTAccentHex) ?: GTDefaultAccentColor();
    }

    return GTColorFromHexOrNil(GTSemanticBlueHex) ?: GTAccentColor;
}


static BOOL GTExtractRGBA(UIColor *color,
                          CGFloat *red,
                          CGFloat *green,
                          CGFloat *blue,
                          CGFloat *alpha) {
    if (!color) {
        return NO;
    }

    CGFloat r = 0.0;
    CGFloat g = 0.0;
    CGFloat b = 0.0;
    CGFloat a = 0.0;

    if ([color getRed:&r green:&g blue:&b alpha:&a]) {
        if (red) *red = r;
        if (green) *green = g;
        if (blue) *blue = b;
        if (alpha) *alpha = a;
        return YES;
    }

    CGFloat white = 0.0;

    if ([color getWhite:&white alpha:&a]) {
        if (red) *red = white;
        if (green) *green = white;
        if (blue) *blue = white;
        if (alpha) *alpha = a;
        return YES;
    }

    return NO;
}

// Conservative detector for Apple's common light/dark system blue family.
// #007AFF and #0A84FF both match. Brand blues that are far away do not.
static BOOL GTLooksLikeResolvedSystemBlue(UIColor *color) {
    CGFloat r = 0.0;
    CGFloat g = 0.0;
    CGFloat b = 0.0;
    CGFloat a = 0.0;

    if (!GTExtractRGBA(color, &r, &g, &b, &a)) {
        return NO;
    }

    if (a <= 0.01) {
        return NO;
    }

    BOOL blueDominant =
        b >= 0.82 &&
        r <= 0.20 &&
        g >= 0.32 &&
        g <= 0.64 &&
        (b - r) >= 0.62 &&
        (b - g) >= 0.25;

    return blueDominant;
}

static UIColor *GTReplacementPreservingAlpha(UIColor *source) {
    UIColor *replacement = GTSemanticBlueColor();

    CGFloat sourceAlpha = 1.0;
    CGFloat rr = 0.0;
    CGFloat rg = 0.0;
    CGFloat rb = 0.0;
    CGFloat ra = 1.0;

    GTExtractRGBA(source, NULL, NULL, NULL, &sourceAlpha);

    if (!GTExtractRGBA(replacement, &rr, &rg, &rb, &ra)) {
        return replacement;
    }

    return [UIColor colorWithRed:rr
                           green:rg
                            blue:rb
                           alpha:(sourceAlpha * ra)];
}

static UIColor *GTMaybeReplaceResolvedBlue(UIColor *color) {
    if (!GTShouldApplyBase() ||
        !GTForceResolvedBlue ||
        !GTLooksLikeResolvedSystemBlue(color)) {
        return color;
    }

    return GTReplacementPreservingAlpha(color);
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

static void GTApplyDebugBorder(UIWindow *window) {
    if (!window) {
        return;
    }

    BOOL apply =
        GTShouldApplyBase() &&
        GTDebugInjectionBorder;

    if (apply) {
        if (!objc_getAssociatedObject(window, &GTOriginalWindowBorderWidthKey)) {
            objc_setAssociatedObject(
                window,
                &GTOriginalWindowBorderWidthKey,
                @(window.layer.borderWidth),
                OBJC_ASSOCIATION_RETAIN_NONATOMIC
            );
        }

        if (!objc_getAssociatedObject(window, &GTOriginalWindowBorderColorKey)) {
            id color =
                window.layer.borderColor
                ? (id)[UIColor colorWithCGColor:window.layer.borderColor]
                : (id)[NSNull null];

            objc_setAssociatedObject(
                window,
                &GTOriginalWindowBorderColorKey,
                color,
                OBJC_ASSOCIATION_RETAIN_NONATOMIC
            );
        }

        window.layer.borderWidth = 3.0;
        window.layer.borderColor = GTSemanticBlueColor().CGColor;
    } else {
        NSNumber *width =
            objc_getAssociatedObject(window, &GTOriginalWindowBorderWidthKey);

        id boxedColor =
            objc_getAssociatedObject(window, &GTOriginalWindowBorderColorKey);

        if (width) {
            window.layer.borderWidth = width.doubleValue;
            objc_setAssociatedObject(
                window,
                &GTOriginalWindowBorderWidthKey,
                nil,
                OBJC_ASSOCIATION_RETAIN_NONATOMIC
            );
        }

        if (boxedColor) {
            UIColor *color =
                boxedColor == [NSNull null]
                ? nil
                : ([boxedColor isKindOfClass:[UIColor class]] ? boxedColor : nil);

            window.layer.borderColor = color.CGColor;

            objc_setAssociatedObject(
                window,
                &GTOriginalWindowBorderColorKey,
                nil,
                OBJC_ASSOCIATION_RETAIN_NONATOMIC
            );
        }
    }
}

static void GTApplyWindow(UIWindow *window) {
    BOOL apply = GTShouldApplyBase() && GTEnableWindowTint;
    GTApplyOrRestoreTint(window, apply, GTColorForComponentHex(GTWindowHex));
    GTApplyDebugBorder(window);
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

static NSDictionary *GTTitleAttributesWithColor(NSDictionary *attributes,
                                                   UIColor *color) {
    NSMutableDictionary *result =
        attributes ? [attributes mutableCopy] : [NSMutableDictionary dictionary];

    if (color) {
        result[NSForegroundColorAttributeName] = color;
    }

    return result;
}

static void GTColorTabBarItemAppearance(UITabBarItemAppearance *appearance,
                                        UIColor *color) {
    if (!appearance || !color) {
        return;
    }

    appearance.selected.iconColor = color;
    appearance.selected.titleTextAttributes =
        GTTitleAttributesWithColor(appearance.selected.titleTextAttributes,
                                   color);
}

static UITabBarAppearance *GTColoredTabBarAppearance(UITabBarAppearance *source,
                                                     UIColor *color) {
    if (!source || !color) {
        return source;
    }

    UITabBarAppearance *appearance = [source copy];

    GTColorTabBarItemAppearance(appearance.stackedLayoutAppearance, color);
    GTColorTabBarItemAppearance(appearance.inlineLayoutAppearance, color);
    GTColorTabBarItemAppearance(appearance.compactInlineLayoutAppearance, color);

    appearance.selectionIndicatorTintColor = color;

    return appearance;
}

static void GTRememberTabBarAppearances(UITabBar *bar) {
    if (!objc_getAssociatedObject(bar, &GTOriginalTabBarStandardAppearanceKey)) {
        objc_setAssociatedObject(
            bar,
            &GTOriginalTabBarStandardAppearanceKey,
            [bar.standardAppearance copy],
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
    }

    if (!objc_getAssociatedObject(bar, &GTOriginalTabBarScrollEdgeAppearanceKey)) {
        id boxed =
            bar.scrollEdgeAppearance
            ? (id)[bar.scrollEdgeAppearance copy]
            : (id)[NSNull null];

        objc_setAssociatedObject(
            bar,
            &GTOriginalTabBarScrollEdgeAppearanceKey,
            boxed,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
    }
}

static void GTRememberTabBarItemAppearances(UITabBarItem *item) {
    if (!item) {
        return;
    }

    if (@available(iOS 15.0, *)) {
        if (!objc_getAssociatedObject(item,
                                      &GTOriginalTabItemStandardAppearanceKey)) {
            id boxed =
                item.standardAppearance
                ? (id)[item.standardAppearance copy]
                : (id)[NSNull null];

            objc_setAssociatedObject(
                item,
                &GTOriginalTabItemStandardAppearanceKey,
                boxed,
                OBJC_ASSOCIATION_RETAIN_NONATOMIC
            );
        }

        if (!objc_getAssociatedObject(item,
                                      &GTOriginalTabItemScrollEdgeAppearanceKey)) {
            id boxed =
                item.scrollEdgeAppearance
                ? (id)[item.scrollEdgeAppearance copy]
                : (id)[NSNull null];

            objc_setAssociatedObject(
                item,
                &GTOriginalTabItemScrollEdgeAppearanceKey,
                boxed,
                OBJC_ASSOCIATION_RETAIN_NONATOMIC
            );
        }
    }
}

static UITabBarAppearance *GTUnboxTabAppearance(id value) {
    if (!value || value == [NSNull null]) {
        return nil;
    }

    return [value isKindOfClass:[UITabBarAppearance class]]
        ? value
        : nil;
}

static void GTRestoreTabBarAppearances(UITabBar *bar) {
    id standard =
        objc_getAssociatedObject(bar, &GTOriginalTabBarStandardAppearanceKey);

    id scrollEdge =
        objc_getAssociatedObject(bar, &GTOriginalTabBarScrollEdgeAppearanceKey);

    objc_setAssociatedObject(bar,
                             &GTApplyingTabAppearanceKey,
                             @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    if (standard) {
        UITabBarAppearance *appearance = GTUnboxTabAppearance(standard);
        if (appearance) {
            bar.standardAppearance = [appearance copy];
        }
    }

    if (scrollEdge) {
        UITabBarAppearance *appearance = GTUnboxTabAppearance(scrollEdge);
        bar.scrollEdgeAppearance = appearance ? [appearance copy] : nil;
    }

    if (@available(iOS 15.0, *)) {
        for (UITabBarItem *item in bar.items) {
            id itemStandard =
                objc_getAssociatedObject(
                    item,
                    &GTOriginalTabItemStandardAppearanceKey
                );

            id itemScrollEdge =
                objc_getAssociatedObject(
                    item,
                    &GTOriginalTabItemScrollEdgeAppearanceKey
                );

            if (itemStandard) {
                UITabBarAppearance *appearance =
                    GTUnboxTabAppearance(itemStandard);

                item.standardAppearance =
                    appearance ? [appearance copy] : nil;
            }

            if (itemScrollEdge) {
                UITabBarAppearance *appearance =
                    GTUnboxTabAppearance(itemScrollEdge);

                item.scrollEdgeAppearance =
                    appearance ? [appearance copy] : nil;
            }

            objc_setAssociatedObject(
                item,
                &GTOriginalTabItemStandardAppearanceKey,
                nil,
                OBJC_ASSOCIATION_RETAIN_NONATOMIC
            );

            objc_setAssociatedObject(
                item,
                &GTOriginalTabItemScrollEdgeAppearanceKey,
                nil,
                OBJC_ASSOCIATION_RETAIN_NONATOMIC
            );
        }
    }

    objc_setAssociatedObject(bar,
                             &GTApplyingTabAppearanceKey,
                             nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    objc_setAssociatedObject(bar,
                             &GTOriginalTabBarStandardAppearanceKey,
                             nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    objc_setAssociatedObject(bar,
                             &GTOriginalTabBarScrollEdgeAppearanceKey,
                             nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void GTApplyTabBar(UITabBar *bar) {
    BOOL apply =
        GTShouldApplyBase() &&
        GTApplyBars &&
        GTEnableTabBar;

    UIColor *color = GTColorForComponentHex(GTTabBarHex);

    // Legacy/public tint path.
    GTApplyOrRestoreTint(bar, apply, color);

    if (!apply || !color) {
        GTRestoreTabBarAppearances(bar);
        return;
    }

    GTRememberTabBarAppearances(bar);

    objc_setAssociatedObject(bar,
                             &GTApplyingTabAppearanceKey,
                             @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // iOS 13+ appearance path. This is what apps such as App Store commonly use.
    UITabBarAppearance *standard =
        GTColoredTabBarAppearance(bar.standardAppearance, color);

    if (standard) {
        bar.standardAppearance = standard;
    }

    if (bar.scrollEdgeAppearance) {
        UITabBarAppearance *scrollEdge =
            GTColoredTabBarAppearance(bar.scrollEdgeAppearance, color);

        if (scrollEdge) {
            bar.scrollEdgeAppearance = scrollEdge;
        }
    }

    // iOS 15+: an individual UITabBarItem can override the whole tab bar
    // appearance, so modify explicit per-item appearances as well.
    if (@available(iOS 15.0, *)) {
        for (UITabBarItem *item in bar.items) {
            GTRememberTabBarItemAppearances(item);

            if (item.standardAppearance) {
                item.standardAppearance =
                    GTColoredTabBarAppearance(item.standardAppearance, color);
            }

            if (item.scrollEdgeAppearance) {
                item.scrollEdgeAppearance =
                    GTColoredTabBarAppearance(item.scrollEdgeAppearance, color);
            }
        }
    }

    objc_setAssociatedObject(bar,
                             &GTApplyingTabAppearanceKey,
                             nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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

static void GTApplyResolvedBlueCompatibilityToView(UIView *view) {
    if (!view) {
        return;
    }

    BOOL active =
        GTShouldApplyBase() &&
        GTForceResolvedBlue;

    if (active) {
        UIColor *currentTint = view.tintColor;

        if (GTLooksLikeResolvedSystemBlue(currentTint)) {
            if (!objc_getAssociatedObject(view, &GTOriginalResolvedTintKey)) {
                objc_setAssociatedObject(
                    view,
                    &GTOriginalResolvedTintKey,
                    currentTint ?: (id)[NSNull null],
                    OBJC_ASSOCIATION_RETAIN_NONATOMIC
                );
            }

            view.tintColor = GTReplacementPreservingAlpha(currentTint);
        }

        if ([view isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)view;
            UIColor *textColor = label.textColor;

            if (GTLooksLikeResolvedSystemBlue(textColor)) {
                if (!objc_getAssociatedObject(label,
                                              &GTOriginalResolvedTextColorKey)) {
                    objc_setAssociatedObject(
                        label,
                        &GTOriginalResolvedTextColorKey,
                        textColor ?: (id)[NSNull null],
                        OBJC_ASSOCIATION_RETAIN_NONATOMIC
                    );
                }

                label.textColor =
                    GTReplacementPreservingAlpha(textColor);
            }
        }
    } else {
        id tint =
            objc_getAssociatedObject(view, &GTOriginalResolvedTintKey);

        if (tint) {
            view.tintColor =
                tint == [NSNull null] ? nil : (UIColor *)tint;

            objc_setAssociatedObject(
                view,
                &GTOriginalResolvedTintKey,
                nil,
                OBJC_ASSOCIATION_RETAIN_NONATOMIC
            );
        }

        if ([view isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)view;

            id textColor =
                objc_getAssociatedObject(label,
                                         &GTOriginalResolvedTextColorKey);

            if (textColor) {
                label.textColor =
                    textColor == [NSNull null]
                    ? nil
                    : (UIColor *)textColor;

                objc_setAssociatedObject(
                    label,
                    &GTOriginalResolvedTextColorKey,
                    nil,
                    OBJC_ASSOCIATION_RETAIN_NONATOMIC
                );
            }
        }
    }
}

static void GTApplyManagedPropertiesToView(UIView *view) {
    if (!view) {
        return;
    }

    // V0.2.4 catches blue colors that have already been resolved to concrete
    // UIColor values by SwiftUI/private system UI.
    GTApplyResolvedBlueCompatibilityToView(view);

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

#pragma mark - Resolved color compatibility

%hook UIView

- (void)setTintColor:(UIColor *)tintColor {
    UIColor *incoming = tintColor;

    if (GTShouldApplyBase() &&
        GTForceResolvedBlue &&
        GTLooksLikeResolvedSystemBlue(incoming)) {

        if (!objc_getAssociatedObject(self, &GTOriginalResolvedTintKey)) {
            objc_setAssociatedObject(
                self,
                &GTOriginalResolvedTintKey,
                incoming ?: (id)[NSNull null],
                OBJC_ASSOCIATION_RETAIN_NONATOMIC
            );
        }

        incoming = GTReplacementPreservingAlpha(incoming);
    } else if (GTForceResolvedBlue &&
               incoming &&
               !GTLooksLikeResolvedSystemBlue(incoming)) {

        // The host app deliberately changed to a non-system-blue color.
        objc_setAssociatedObject(
            self,
            &GTOriginalResolvedTintKey,
            nil,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
    }

    %orig(incoming);
}

%end

%hook UILabel

- (void)setTextColor:(UIColor *)textColor {
    UIColor *incoming = textColor;

    if (GTShouldApplyBase() &&
        GTForceResolvedBlue &&
        GTLooksLikeResolvedSystemBlue(incoming)) {

        if (!objc_getAssociatedObject(self,
                                      &GTOriginalResolvedTextColorKey)) {
            objc_setAssociatedObject(
                self,
                &GTOriginalResolvedTextColorKey,
                incoming ?: (id)[NSNull null],
                OBJC_ASSOCIATION_RETAIN_NONATOMIC
            );
        }

        incoming = GTReplacementPreservingAlpha(incoming);
    } else if (GTForceResolvedBlue &&
               incoming &&
               !GTLooksLikeResolvedSystemBlue(incoming)) {

        objc_setAssociatedObject(
            self,
            &GTOriginalResolvedTextColorKey,
            nil,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
    }

    %orig(incoming);
}

%end

#pragma mark - Semantic UIKit colors

%hook UIColor

+ (UIColor *)systemBlueColor {
    if (GTShouldApplyBase() && GTReplaceSystemBlue) {
        return GTSemanticBlueColor();
    }

    return %orig;
}

+ (UIColor *)linkColor {
    if (GTShouldApplyBase() && GTReplaceLinkColor) {
        return GTSemanticBlueColor();
    }

    return %orig;
}

- (UIColor *)resolvedColorWithTraitCollection:(UITraitCollection *)traitCollection {
    UIColor *resolved = %orig(traitCollection);

    if (GTShouldApplyBase() &&
        GTForceResolvedBlue &&
        GTLooksLikeResolvedSystemBlue(resolved)) {
        return GTReplacementPreservingAlpha(resolved);
    }

    return resolved;
}

%end

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

- (void)setItems:(NSArray<UITabBarItem *> *)items animated:(BOOL)animated {
    %orig(items, animated);
    GTApplyTabBar(self);
}

- (void)setSelectedItem:(UITabBarItem *)selectedItem {
    %orig(selectedItem);
    GTApplyTabBar(self);
}

- (void)setStandardAppearance:(UITabBarAppearance *)appearance {
    BOOL internalApply =
        [objc_getAssociatedObject(self, &GTApplyingTabAppearanceKey) boolValue];

    // If the host app changes its appearance while GlobalTint is active,
    // remember the newest host-provided appearance as the restoration target.
    if (!internalApply &&
        GTShouldApplyBase() &&
        GTApplyBars &&
        GTEnableTabBar) {

        objc_setAssociatedObject(
            self,
            &GTOriginalTabBarStandardAppearanceKey,
            appearance ? (id)[appearance copy] : (id)[NSNull null],
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
    }

    %orig(appearance);

    if (!internalApply) {
        GTApplyTabBar(self);
    }
}

- (void)setScrollEdgeAppearance:(UITabBarAppearance *)appearance {
    BOOL internalApply =
        [objc_getAssociatedObject(self, &GTApplyingTabAppearanceKey) boolValue];

    if (!internalApply &&
        GTShouldApplyBase() &&
        GTApplyBars &&
        GTEnableTabBar) {

        objc_setAssociatedObject(
            self,
            &GTOriginalTabBarScrollEdgeAppearanceKey,
            appearance ? (id)[appearance copy] : (id)[NSNull null],
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
    }

    %orig(appearance);

    if (!internalApply) {
        GTApplyTabBar(self);
    }
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


#pragma mark - MobileSafari private toolbar compatibility

%hook BrowserToolbar

- (void)didMoveToWindow {
    %orig;

    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier.lowercaseString;

    if (![bundleID isEqualToString:@"com.apple.mobilesafari"]) {
        return;
    }

    if (!GTShouldApplyBase() ||
        !GTApplyBars ||
        !GTEnableToolbar) {
        return;
    }

    UIColor *color = GTColorForComponentHex(GTToolbarHex);
    self.tintColor = color;

    SEL selector = NSSelectorFromString(@"setInteractionTintColor:");

    if ([self respondsToSelector:selector]) {
        ((void (*)(id, SEL, id))objc_msgSend)(self, selector, color);
    }
}

- (void)layoutSubviews {
    %orig;

    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier.lowercaseString;

    if (![bundleID isEqualToString:@"com.apple.mobilesafari"]) {
        return;
    }

    if (!GTShouldApplyBase() ||
        !GTApplyBars ||
        !GTEnableToolbar) {
        return;
    }

    UIColor *color = GTColorForComponentHex(GTToolbarHex);
    self.tintColor = color;

    SEL selector = NSSelectorFromString(@"setInteractionTintColor:");

    if ([self respondsToSelector:selector]) {
        ((void (*)(id, SEL, id))objc_msgSend)(self, selector, color);
    }
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


    [GTPreferences registerBool:&GTReplaceSystemBlue
                         default:NO
                          forKey:@"ReplaceSystemBlue"];

    [GTPreferences registerBool:&GTReplaceLinkColor
                         default:NO
                          forKey:@"ReplaceLinkColor"];

    [GTPreferences registerBool:&GTDebugInjectionBorder
                         default:NO
                          forKey:@"DebugInjectionBorder"];


    [GTPreferences registerBool:&GTForceResolvedBlue
                         default:NO
                          forKey:@"ForceResolvedBlue"];

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
