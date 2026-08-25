#import <UIKit/UIKit.h>
#include <roothide.h>
#include <dlfcn.h>
#include <math.h>
#include <substrate.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <QuartzCore/QuartzCore.h>


@interface BrowserToolbar : UIView
@end

static NSUserDefaults *GTPreferences = nil;
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
static BOOL GTEnableTabBarBadge = NO;
static BOOL GTEnableToolbar = YES;
static BOOL GTEnableSearchBar = YES;

// Color mode
static BOOL GTUseSeparateColors = NO;
static BOOL GTEnableAppColorOverrides = YES;
static BOOL GTEnableAppComponentSwitchOverrides = YES;

// Compatibility / diagnostics
static BOOL GTReplaceSystemBlue = NO;
static BOOL GTReplaceLinkColor = NO;
static BOOL GTDebugInjectionBorder = NO;
static BOOL GTForceResolvedBlue = NO;
static BOOL GTElementInspector = NO;
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
static NSString *GTBadgeBackgroundHex = @"";
static NSString *GTBadgeTextHex = @"";
static NSString *GTToolbarHex = @"";
static NSString *GTSearchBarHex = @"";

static NSString *GTExcludedBundleIDs = @"";
static NSDictionary<NSString *, NSString *> *GTAppColorOverrides = nil;
static NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *GTAppComponentColorOverrides = nil;
static NSDictionary<NSString *, NSDictionary<NSString *, NSNumber *> *> *GTAppComponentSwitchOverrides = nil;

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
static char GTOriginalBadgeColorKey;
static char GTOriginalBadgeNormalTextAttributesKey;
static char GTOriginalBadgeSelectedTextAttributesKey;
static char GTApplyingBadgeAppearanceKey;
static char GTOriginalWindowBorderWidthKey;
static char GTOriginalWindowBorderColorKey;
static char GTOriginalResolvedTintKey;
static char GTOriginalResolvedTextColorKey;
static char GTOriginalResolvedBackgroundColorKey;
static char GTOriginalLayerBackgroundColorKey;

// Re-entrancy guard used by the multi-layer color engine. Some replacement
// paths convert UIColor <-> CGColor, which can re-enter our own hooks.
static __thread NSUInteger GTColorEngineBypassDepth = 0;
static BOOL GTColorEngineHasLayerState = NO;

static BOOL GTShouldApplyBase(void);
static BOOL GTInspectorProcessIsEligible(void);
static BOOL GTInspectorWindowIsEligible(UIWindow *window);
static BOOL GTInspectorViewIsEligible(UIView *view);

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

static UIColor *GTGlobalAccentColor(void) {
    if (!GTAccentColor) {
        GTAccentColor =
            GTColorFromHexOrNil(GTAccentHex) ?: GTDefaultAccentColor();
    }

    return GTAccentColor;
}

static NSString *GTCurrentBundleIdentifier(void) {
    NSString *bundleID =
        NSBundle.mainBundle.bundleIdentifier.lowercaseString;

    return bundleID ?: @"";
}

static UIColor *GTCurrentAppAccentColor(void) {
    UIColor *globalAccent = GTGlobalAccentColor();

    if (!GTEnableAppColorOverrides ||
        GTAppColorOverrides.count == 0) {
        return globalAccent;
    }

    NSString *bundleID = GTCurrentBundleIdentifier();

    if (bundleID.length == 0) {
        return globalAccent;
    }

    NSString *overrideHex = GTAppColorOverrides[bundleID];
    UIColor *overrideColor = GTColorFromHexOrNil(overrideHex);

    return overrideColor ?: globalAccent;
}

static NSNumber *
GTCurrentAppComponentSwitchOverride(NSString *componentKey) {
    if (!GTEnableAppComponentSwitchOverrides ||
        componentKey.length == 0 ||
        GTAppComponentSwitchOverrides.count == 0) {
        return nil;
    }

    NSString *bundleID = GTCurrentBundleIdentifier();

    if (bundleID.length == 0) {
        return nil;
    }

    NSDictionary<NSString *, NSNumber *> *appRules =
        GTAppComponentSwitchOverrides[bundleID];

    if (![appRules isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    id value = appRules[componentKey];

    if (![value respondsToSelector:@selector(boolValue)]) {
        return nil;
    }

    return @([value boolValue]);
}

static BOOL GTShouldApplyComponent(NSString *componentKey,
                                   BOOL globalComponentEnabled,
                                   BOOL groupEnabled) {
    if (!GTShouldApplyBase() || !groupEnabled) {
        return NO;
    }

    NSNumber *appOverride =
        GTCurrentAppComponentSwitchOverride(componentKey);

    if (appOverride) {
        return appOverride.boolValue;
    }

    return globalComponentEnabled;
}

static NSString *
GTCurrentAppComponentOverrideHex(NSString *componentKey) {
    if (!GTEnableAppColorOverrides ||
        componentKey.length == 0 ||
        GTAppComponentColorOverrides.count == 0) {
        return nil;
    }

    NSString *bundleID = GTCurrentBundleIdentifier();

    if (bundleID.length == 0) {
        return nil;
    }

    NSDictionary<NSString *, NSString *> *appRules =
        GTAppComponentColorOverrides[bundleID];

    if (![appRules isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    NSString *hex = appRules[componentKey];

    if (![hex isKindOfClass:[NSString class]] ||
        !GTColorFromHexOrNil(hex)) {
        return nil;
    }

    return hex;
}

static UIColor *GTColorForComponent(NSString *componentKey,
                                    NSString *componentHex) {
    UIColor *baseAccent = GTCurrentAppAccentColor();

    if (!GTUseSeparateColors) {
        return baseAccent;
    }

    NSString *appComponentHex =
        GTCurrentAppComponentOverrideHex(componentKey);

    UIColor *appComponentColor =
        GTColorFromHexOrNil(appComponentHex);

    if (appComponentColor) {
        return appComponentColor;
    }

    UIColor *globalComponentColor =
        GTColorFromHexOrNil(componentHex);

    return globalComponentColor ?: baseAccent;
}

static UIColor *GTBadgeBackgroundColor(void) {
    UIColor *baseAccent = GTCurrentAppAccentColor();

    if (!GTUseSeparateColors) {
        return baseAccent;
    }

    UIColor *appColor =
        GTColorFromHexOrNil(
            GTCurrentAppComponentOverrideHex(
                @"BadgeBackgroundColor"
            )
        );

    if (appColor) {
        return appColor;
    }

    return
        GTColorFromHexOrNil(GTBadgeBackgroundHex)
        ?: baseAccent;
}

static UIColor *GTBadgeTextColor(void) {
    UIColor *fallback = UIColor.whiteColor;

    if (!GTUseSeparateColors) {
        return fallback;
    }

    UIColor *appColor =
        GTColorFromHexOrNil(
            GTCurrentAppComponentOverrideHex(
                @"BadgeTextColor"
            )
        );

    if (appColor) {
        return appColor;
    }

    return
        GTColorFromHexOrNil(GTBadgeTextHex)
        ?: fallback;
}


static UIColor *GTSemanticBlueColor(void) {
    UIColor *baseAccent = GTCurrentAppAccentColor();

    return GTColorFromHexOrNil(GTSemanticBlueHex) ?: baseAccent;
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

static BOOL GTExtractCGColorRGBA(CGColorRef color,
                                 CGFloat *red,
                                 CGFloat *green,
                                 CGFloat *blue,
                                 CGFloat *alpha) {
    if (!color) {
        return NO;
    }

    CGColorSpaceRef colorSpace = CGColorGetColorSpace(color);
    CGColorSpaceModel model = colorSpace
        ? CGColorSpaceGetModel(colorSpace)
        : kCGColorSpaceModelUnknown;

    size_t count = CGColorGetNumberOfComponents(color);
    const CGFloat *components = CGColorGetComponents(color);

    if (!components || count == 0) {
        return NO;
    }

    CGFloat r = 0.0, g = 0.0, b = 0.0, a = 1.0;

    if (model == kCGColorSpaceModelMonochrome && count >= 2) {
        r = g = b = components[0];
        a = components[1];
    } else if (model == kCGColorSpaceModelRGB && count >= 4) {
        r = components[0];
        g = components[1];
        b = components[2];
        a = components[count - 1];
    } else {
        return NO;
    }

    if (red) *red = r;
    if (green) *green = g;
    if (blue) *blue = b;
    if (alpha) *alpha = a;
    return YES;
}

static UIColor *GTConcreteColorFromCGColor(CGColorRef color) {
    CGFloat r = 0.0, g = 0.0, b = 0.0, a = 1.0;

    if (!GTExtractCGColorRGBA(color, &r, &g, &b, &a)) {
        return nil;
    }

    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

// Tolerant color matching, modeled after the analyzed reference tweak.
// The reference implementation does not require exact RGB equality; it allows
// small per-channel differences so dynamic/anti-aliased variants still match.
static BOOL GTColorMatchesRGBA(UIColor *color,
                               CGFloat targetR,
                               CGFloat targetG,
                               CGFloat targetB,
                               CGFloat targetA,
                               CGFloat toleranceR,
                               CGFloat toleranceG,
                               CGFloat toleranceB,
                               CGFloat toleranceA) {
    CGFloat r = 0.0, g = 0.0, b = 0.0, a = 0.0;

    if (!GTExtractRGBA(color, &r, &g, &b, &a)) {
        return NO;
    }

    return fabs(r - targetR) < toleranceR &&
           fabs(g - targetG) < toleranceG &&
           fabs(b - targetB) < toleranceB &&
           fabs(a - targetA) < toleranceA;
}

static BOOL GTColorsApproximatelyEqual(UIColor *left,
                                        UIColor *right,
                                        CGFloat tolerance) {
    if (left == right) {
        return YES;
    }

    CGFloat lr = 0.0, lg = 0.0, lb = 0.0, la = 0.0;
    CGFloat rr = 0.0, rg = 0.0, rb = 0.0, ra = 0.0;

    if (!GTExtractRGBA(left, &lr, &lg, &lb, &la) ||
        !GTExtractRGBA(right, &rr, &rg, &rb, &ra)) {
        return NO;
    }

    return fabs(lr - rr) <= tolerance &&
           fabs(lg - rg) <= tolerance &&
           fabs(lb - rb) <= tolerance &&
           fabs(la - ra) <= MAX(tolerance, 0.05);
}

// Conservative detector for the common Apple/system-blue accent family.
// It first uses the same tolerance-style matching as the analyzed tweak for
// #007AFF / #0A84FF, then falls back to a hue/saturation check to catch nearby
// concrete blues emitted by SwiftUI/private UIKit implementations. Semantic
// red/green/orange/yellow are deliberately excluded.
static BOOL GTLooksLikeResolvedSystemBlue(UIColor *color) {
    if (!color) {
        return NO;
    }

    // iOS light system blue: #007AFF
    if (GTColorMatchesRGBA(color,
                           0.0,
                           122.0 / 255.0,
                           1.0,
                           1.0,
                           0.08, 0.07, 0.08, 0.10)) {
        return YES;
    }

    // iOS dark system blue: #0A84FF
    if (GTColorMatchesRGBA(color,
                           10.0 / 255.0,
                           132.0 / 255.0,
                           1.0,
                           1.0,
                           0.08, 0.07, 0.08, 0.10)) {
        return YES;
    }

    CGFloat r = 0.0, g = 0.0, b = 0.0, a = 0.0;

    if (!GTExtractRGBA(color, &r, &g, &b, &a) || a <= 0.01) {
        return NO;
    }

    CGFloat maximum = MAX(r, MAX(g, b));
    CGFloat minimum = MIN(r, MIN(g, b));
    CGFloat delta = maximum - minimum;

    if (maximum < 0.32 || delta < 0.16 || b < g || b < r) {
        return NO;
    }

    CGFloat saturation = maximum > 0.0 ? delta / maximum : 0.0;
    if (saturation < 0.42) {
        return NO;
    }

    // HSV hue in degrees. We only arrive here when blue is the max channel.
    CGFloat hue = 60.0 * (((r - g) / delta) + 4.0);
    if (hue < 0.0) {
        hue += 360.0;
    }

    // Cover cyan-blue through Apple-blue/purple-blue, but not teal/green or
    // broad violet. This is intentionally narrower than "all blue-looking".
    return hue >= 195.0 && hue <= 232.0;
}

static BOOL GTColorMatchesConfiguredOutputHex(UIColor *color, NSString *hex) {
    if (![hex isKindOfClass:[NSString class]] || hex.length == 0) {
        return NO;
    }

    UIColor *configured = GTColorFromHexOrNil(hex);
    return configured && GTColorsApproximatelyEqual(color, configured, 0.025);
}

// Prevent the generic compatibility engine from re-coloring a color that the
// user explicitly chose as a GlobalTint output (for example a blue per-control
// override). The test only runs after the source has already matched the blue
// family, so its cost stays low in normal UI traffic.
static BOOL GTColorIsConfiguredGlobalTintOutput(UIColor *color) {
    if (!color) {
        return NO;
    }

    if (GTColorsApproximatelyEqual(color, GTCurrentAppAccentColor(), 0.025) ||
        GTColorsApproximatelyEqual(color, GTSemanticBlueColor(), 0.025)) {
        return YES;
    }

    NSArray<NSString *> *globalHexes = @[
        GTWindowHex ?: @"",
        GTSwitchHex ?: @"",
        GTSliderHex ?: @"",
        GTProgressHex ?: @"",
        GTSegmentedHex ?: @"",
        GTPageControlHex ?: @"",
        GTRefreshControlHex ?: @"",
        GTNavigationBarHex ?: @"",
        GTTabBarHex ?: @"",
        GTBadgeBackgroundHex ?: @"",
        GTBadgeTextHex ?: @"",
        GTToolbarHex ?: @"",
        GTSearchBarHex ?: @""
    ];

    for (NSString *hex in globalHexes) {
        if (GTColorMatchesConfiguredOutputHex(color, hex)) {
            return YES;
        }
    }

    NSString *bundleID = GTCurrentBundleIdentifier();
    NSString *appAccentHex = GTAppColorOverrides[bundleID];

    if (GTColorMatchesConfiguredOutputHex(color, appAccentHex)) {
        return YES;
    }

    NSDictionary<NSString *, NSString *> *componentColors =
        GTAppComponentColorOverrides[bundleID];

    if ([componentColors isKindOfClass:[NSDictionary class]]) {
        for (id value in componentColors.allValues) {
            if ([value isKindOfClass:[NSString class]] &&
                GTColorMatchesConfiguredOutputHex(color, (NSString *)value)) {
                return YES;
            }
        }
    }

    return NO;
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

// Central replacement pipeline used by every new interception layer. Keeping
// all matching in one function mirrors the reference tweak and prevents the
// individual hooks from slowly drifting into different behavior.
static UIColor *GTColorEngineReplaceColor(UIColor *source) {
    if (!source ||
        GTColorEngineBypassDepth > 0 ||
        !GTForceResolvedBlue ||
        !GTShouldApplyBase()) {
        return source;
    }

    if (!GTLooksLikeResolvedSystemBlue(source)) {
        return source;
    }

    if (GTColorIsConfiguredGlobalTintOutput(source)) {
        return source;
    }

    UIColor *replacement = GTReplacementPreservingAlpha(source);

    if (!replacement ||
        GTColorsApproximatelyEqual(source, replacement, 0.01)) {
        return source;
    }

    return replacement;
}

static CGColorRef GTColorEngineReplaceCGColor(CGColorRef source) {
    if (!source ||
        GTColorEngineBypassDepth > 0 ||
        !GTForceResolvedBlue ||
        !GTShouldApplyBase()) {
        return source;
    }

    // Do not wrap the source with +colorWithCGColor: here. Some private UIColor
    // implementations may consult -CGColor while extracting their components,
    // which would re-enter this hook. Read CoreGraphics components directly and
    // build a plain RGB UIColor for the shared matcher instead.
    UIColor *sourceColor = GTConcreteColorFromCGColor(source);

    if (!sourceColor) {
        return source;
    }

    UIColor *replacement = GTColorEngineReplaceColor(sourceColor);

    if (!replacement || replacement == sourceColor ||
        GTColorsApproximatelyEqual(sourceColor, replacement, 0.01)) {
        return source;
    }

    GTColorEngineBypassDepth++;
    CGColorRef replacementCGColor = replacement.CGColor;
    GTColorEngineBypassDepth--;

    return replacementCGColor ?: source;
}

static void GTSetLayerBackgroundColorBypassingEngine(CALayer *layer,
                                                     CGColorRef color) {
    if (!layer) {
        return;
    }

    GTColorEngineBypassDepth++;
    layer.backgroundColor = color;
    GTColorEngineBypassDepth--;
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

static NSString *GTInspectorDescribeColor(UIColor *color) {
    if (!color) {
        return @"nil";
    }

    CGFloat r = 0.0, g = 0.0, b = 0.0, a = 0.0;

    if ([color getRed:&r green:&g blue:&b alpha:&a]) {
        return [NSString stringWithFormat:@"#%02lX%02lX%02lX a=%.2f",
                (long)llround(MAX(0.0, MIN(1.0, r)) * 255.0),
                (long)llround(MAX(0.0, MIN(1.0, g)) * 255.0),
                (long)llround(MAX(0.0, MIN(1.0, b)) * 255.0),
                a];
    }

    CGFloat white = 0.0;

    if ([color getWhite:&white alpha:&a]) {
        return [NSString stringWithFormat:@"gray=%.3f a=%.2f", white, a];
    }

    return color.description ?: @"<dynamic UIColor>";
}

static UIViewController *GTInspectorTopController(UIViewController *controller) {
    if (!controller) {
        return nil;
    }

    if (controller.presentedViewController) {
        return GTInspectorTopController(controller.presentedViewController);
    }

    if ([controller isKindOfClass:[UINavigationController class]]) {
        return GTInspectorTopController(
            ((UINavigationController *)controller).visibleViewController
        );
    }

    if ([controller isKindOfClass:[UITabBarController class]]) {
        return GTInspectorTopController(
            ((UITabBarController *)controller).selectedViewController
        );
    }

    return controller;
}

static NSString *GTInspectorLayerDescription(CALayer *layer) {
    if (!layer) {
        return @"";
    }

    NSMutableArray<NSString *> *parts = [NSMutableArray array];

    [parts addObject:
        [NSString stringWithFormat:@"layer=%@",
         NSStringFromClass(layer.class)]];

    if (layer.backgroundColor) {
        [parts addObject:
            [NSString stringWithFormat:@"bg=%@",
             GTInspectorDescribeColor(
                 [UIColor colorWithCGColor:layer.backgroundColor]
             )]];
    }

    if (layer.borderColor) {
        [parts addObject:
            [NSString stringWithFormat:@"border=%@",
             GTInspectorDescribeColor(
                 [UIColor colorWithCGColor:layer.borderColor]
             )]];
    }

    if ([layer isKindOfClass:[CAShapeLayer class]]) {
        CAShapeLayer *shape = (CAShapeLayer *)layer;

        if (shape.fillColor) {
            [parts addObject:
                [NSString stringWithFormat:@"fill=%@",
                 GTInspectorDescribeColor(
                     [UIColor colorWithCGColor:shape.fillColor]
                 )]];
        }

        if (shape.strokeColor) {
            [parts addObject:
                [NSString stringWithFormat:@"stroke=%@",
                 GTInspectorDescribeColor(
                     [UIColor colorWithCGColor:shape.strokeColor]
                 )]];
        }
    }

    return [parts componentsJoinedByString:@", "];
}

static NSString *GTInspectorViewDescription(UIView *view) {
    if (!view) {
        return @"<nil>";
    }

    NSMutableArray<NSString *> *parts = [NSMutableArray array];

    [parts addObject:NSStringFromClass(view.class)];

    [parts addObject:
        [NSString stringWithFormat:@"frame=(%.0f,%.0f %.0fx%.0f)",
         view.frame.origin.x,
         view.frame.origin.y,
         view.frame.size.width,
         view.frame.size.height]];

    [parts addObject:
        [NSString stringWithFormat:@"tint=%@",
         GTInspectorDescribeColor(view.tintColor)]];

    if ([view isKindOfClass:[UILabel class]]) {
        UILabel *label = (UILabel *)view;

        [parts addObject:
            [NSString stringWithFormat:@"textColor=%@",
             GTInspectorDescribeColor(label.textColor)]];

        if (label.text.length > 0) {
            NSString *displayText = label.text;

            if (displayText.length > 30) {
                displayText =
                    [[displayText substringToIndex:30]
                     stringByAppendingString:@"…"];
            }

            [parts addObject:
                [NSString stringWithFormat:@"text=\"%@\"", displayText]];
        }
    }

    if ([view isKindOfClass:[UIImageView class]]) {
        UIImageView *imageView = (UIImageView *)view;

        if (imageView.image) {
            [parts addObject:
                [NSString stringWithFormat:@"imageMode=%ld",
                 (long)imageView.image.renderingMode]];
        }
    }

    NSString *layerInfo = GTInspectorLayerDescription(view.layer);

    if (layerInfo.length > 0) {
        [parts addObject:layerInfo];
    }

    return [parts componentsJoinedByString:@" | "];
}

static void GTInspectorPresent(UIWindow *window, UIView *hitView) {
    if (!window || !hitView) {
        return;
    }

    NSMutableString *report = [NSMutableString string];

    [report appendFormat:@"Bundle: %@\n",
     NSBundle.mainBundle.bundleIdentifier ?: @"(nil)"];

    [report appendFormat:@"Hit class: %@\n\n",
     NSStringFromClass(hitView.class)];

    UIView *current = hitView;

    for (NSInteger depth = 0; current && depth < 16; depth++) {
        [report appendFormat:@"%ld. %@\n\n",
         (long)depth,
         GTInspectorViewDescription(current)];

        current = current.superview;
    }

    if (hitView.layer.sublayers.count > 0) {
        [report appendString:@"Hit-view sublayers:\n"];

        NSInteger count = 0;

        for (CALayer *layer in hitView.layer.sublayers) {
            if (count >= 10) {
                break;
            }

            [report appendFormat:@"- %@\n",
             GTInspectorLayerDescription(layer)];

            count++;
        }
    }

    UIPasteboard.generalPasteboard.string = report;

    UIViewController *presenter =
        GTInspectorTopController(window.rootViewController);

    if (!presenter) {
        return;
    }

    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"GlobalTint UI Inspector"
                                            message:report
                                     preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:
        [UIAlertAction actionWithTitle:@"关闭"
                                 style:UIAlertActionStyleCancel
                               handler:nil]];

    [presenter presentViewController:alert
                            animated:YES
                          completion:nil];
}

static BOOL GTInspectorProcessIsEligible(void) {
    NSString *bundleID =
        NSBundle.mainBundle.bundleIdentifier.lowercaseString;

    // SpringBoard receives system-gesture overlay touches through
    // UISystemGestureView/_UISystemGestureWindow. Those are not the app UI
    // elements we are trying to inspect.
    if ([bundleID isEqualToString:@"com.apple.springboard"]) {
        return NO;
    }

    return YES;
}

static BOOL GTInspectorWindowIsEligible(UIWindow *window) {
    if (!window) {
        return NO;
    }

    NSString *windowClass = NSStringFromClass(window.class);

    if ([windowClass containsString:@"SystemGesture"] ||
        [windowClass containsString:@"UISystemGesture"]) {
        return NO;
    }

    if (window.hidden || window.alpha <= 0.01) {
        return NO;
    }

    return YES;
}

static BOOL GTInspectorViewIsEligible(UIView *view) {
    if (!view) {
        return NO;
    }

    NSString *viewClass = NSStringFromClass(view.class);

    if ([viewClass containsString:@"SystemGesture"] ||
        [viewClass containsString:@"UISystemGesture"]) {
        return NO;
    }

    return YES;
}

@interface GTInspectorOverlayWindow : UIWindow
@property (nonatomic, weak) UIWindow *gtSourceWindow;
@property (nonatomic, strong) UIButton *gtButton;
@property (nonatomic, strong) UIView *gtCaptureView;
@property (nonatomic, assign) BOOL gtCaptureActive;
@end

@implementation GTInspectorOverlayWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden ||
        self.alpha <= 0.01 ||
        !self.userInteractionEnabled) {
        return nil;
    }

    UIView *hit = [super hitTest:point withEvent:event];

    if (self.gtCaptureActive) {
        return hit;
    }

    // When not inspecting, this extra window must be completely transparent
    // to the app except for the small GT button.
    if (hit == self.gtButton ||
        [hit isDescendantOfView:self.gtButton]) {
        return hit;
    }

    return nil;
}

@end

static NSMapTable<UIWindowScene *, GTInspectorOverlayWindow *>
    *GTInspectorWindowsByScene = nil;

static BOOL GTInspectorCanUseSourceWindow(UIWindow *window) {
    if (!window ||
        !GTInspectorProcessIsEligible() ||
        !GTInspectorWindowIsEligible(window)) {
        return NO;
    }

    if ([window isKindOfClass:[GTInspectorOverlayWindow class]]) {
        return NO;
    }

    // Accept normal app windows even if the system uses a small non-zero
    // windowLevel internally. Reject obvious overlays/alerts.
    if (window.windowLevel >= UIWindowLevelAlert) {
        return NO;
    }

    if (window.bounds.size.width < 200.0 ||
        window.bounds.size.height < 300.0) {
        return NO;
    }

    if (!window.windowScene) {
        return NO;
    }

    return YES;
}

static UIWindow *GTInspectorBestSourceWindow(UIWindowScene *scene) {
    if (!scene) {
        return nil;
    }

    UIWindow *keyCandidate = nil;
    UIWindow *fallback = nil;

    for (UIWindow *window in scene.windows) {
        if (!GTInspectorCanUseSourceWindow(window)) {
            continue;
        }

        if (window.isKeyWindow) {
            keyCandidate = window;
            break;
        }

        if (!fallback ||
            window.windowLevel < fallback.windowLevel) {
            fallback = window;
        }
    }

    return keyCandidate ?: fallback;
}

static void GTRemoveInspectorCapture(GTInspectorOverlayWindow *overlayWindow) {
    if (!overlayWindow) {
        return;
    }

    if (overlayWindow.gtCaptureView) {
        [overlayWindow.gtCaptureView removeFromSuperview];
        overlayWindow.gtCaptureView = nil;
    }

    overlayWindow.gtCaptureActive = NO;
    overlayWindow.gtButton.hidden = NO;
}

@interface UIApplication (GlobalTintSceneInspector)
- (void)gt_sceneInspectorButtonTapped:(UIButton *)sender;
- (void)gt_sceneInspectorCaptureTapped:(UITapGestureRecognizer *)gesture;
@end

@implementation UIApplication (GlobalTintSceneInspector)

- (void)gt_sceneInspectorButtonTapped:(UIButton *)sender {
    GTInspectorOverlayWindow *overlayWindow =
        (GTInspectorOverlayWindow *)sender.window;

    if (![overlayWindow isKindOfClass:[GTInspectorOverlayWindow class]]) {
        return;
    }

    UIWindow *sourceWindow =
        GTInspectorBestSourceWindow(overlayWindow.windowScene);

    if (!sourceWindow) {
        return;
    }

    overlayWindow.gtSourceWindow = sourceWindow;

    GTRemoveInspectorCapture(overlayWindow);

    UIView *capture =
        [[UIView alloc] initWithFrame:overlayWindow.bounds];

    capture.autoresizingMask =
        UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleHeight;

    capture.backgroundColor =
        [UIColor colorWithWhite:0.0 alpha:0.055];

    UILabel *hint =
        [[UILabel alloc] initWithFrame:CGRectZero];

    hint.text = @"点一下要检查的 UI";
    hint.textAlignment = NSTextAlignmentCenter;
    hint.textColor = UIColor.whiteColor;
    hint.backgroundColor =
        [UIColor colorWithWhite:0.0 alpha:0.76];

    hint.font =
        [UIFont systemFontOfSize:14.0
                         weight:UIFontWeightSemibold];

    hint.layer.cornerRadius = 12.0;
    hint.layer.masksToBounds = YES;

    CGFloat hintWidth =
        MIN(overlayWindow.bounds.size.width - 40.0, 220.0);

    CGFloat hintY =
        MAX(overlayWindow.safeAreaInsets.top + 12.0, 18.0);

    hint.frame =
        CGRectMake(
            (overlayWindow.bounds.size.width - hintWidth) / 2.0,
            hintY,
            hintWidth,
            38.0
        );

    hint.autoresizingMask =
        UIViewAutoresizingFlexibleLeftMargin |
        UIViewAutoresizingFlexibleRightMargin |
        UIViewAutoresizingFlexibleBottomMargin;

    [capture addSubview:hint];

    UITapGestureRecognizer *tap =
        [[UITapGestureRecognizer alloc]
         initWithTarget:self
         action:@selector(gt_sceneInspectorCaptureTapped:)];

    tap.cancelsTouchesInView = YES;
    [capture addGestureRecognizer:tap];

    overlayWindow.gtCaptureView = capture;
    overlayWindow.gtCaptureActive = YES;
    overlayWindow.gtButton.hidden = YES;

    [overlayWindow.rootViewController.view addSubview:capture];
}

- (void)gt_sceneInspectorCaptureTapped:
    (UITapGestureRecognizer *)gesture {

    if (gesture.state != UIGestureRecognizerStateEnded) {
        return;
    }

    UIView *capture = gesture.view;
    GTInspectorOverlayWindow *overlayWindow =
        (GTInspectorOverlayWindow *)capture.window;

    if (![overlayWindow isKindOfClass:[GTInspectorOverlayWindow class]]) {
        return;
    }

    CGPoint screenPoint =
        [gesture locationInView:overlayWindow];

    UIWindow *sourceWindow = overlayWindow.gtSourceWindow;

    if (!GTInspectorCanUseSourceWindow(sourceWindow)) {
        sourceWindow =
            GTInspectorBestSourceWindow(overlayWindow.windowScene);
    }

    // Remove the capture layer/window interception before asking the real
    // application window which view is underneath this exact point.
    GTRemoveInspectorCapture(overlayWindow);

    if (!sourceWindow) {
        return;
    }

    CGPoint sourcePoint =
        [overlayWindow convertPoint:screenPoint
                           toWindow:sourceWindow];

    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *hitView =
            [sourceWindow hitTest:sourcePoint withEvent:nil];

        if (!GTInspectorViewIsEligible(hitView)) {
            return;
        }

        GTInspectorPresent(sourceWindow, hitView);
    });
}

@end

static GTInspectorOverlayWindow *
GTInspectorWindowForScene(UIWindowScene *scene, BOOL createIfNeeded) {
    if (!scene) {
        return nil;
    }

    if (!GTInspectorWindowsByScene) {
        GTInspectorWindowsByScene =
            [NSMapTable weakToStrongObjectsMapTable];
    }

    GTInspectorOverlayWindow *overlayWindow =
        [GTInspectorWindowsByScene objectForKey:scene];

    if (!overlayWindow && createIfNeeded) {
        overlayWindow =
            [[GTInspectorOverlayWindow alloc]
             initWithWindowScene:scene];

        overlayWindow.frame = scene.coordinateSpace.bounds;
        overlayWindow.backgroundColor = UIColor.clearColor;

        // High enough to remain above dynamic App Store/Safari content,
        // but below the very high system alert range.
        overlayWindow.windowLevel = UIWindowLevelAlert - 1.0;

        UIViewController *rootController =
            [[UIViewController alloc] init];

        rootController.view.backgroundColor = UIColor.clearColor;
        overlayWindow.rootViewController = rootController;

        UIButton *button =
            [UIButton buttonWithType:UIButtonTypeSystem];

        button.frame =
            CGRectMake(
                MAX(10.0, overlayWindow.bounds.size.width - 58.0),
                MAX(overlayWindow.safeAreaInsets.top + 8.0, 16.0),
                44.0,
                44.0
            );

        button.autoresizingMask =
            UIViewAutoresizingFlexibleLeftMargin |
            UIViewAutoresizingFlexibleBottomMargin;

        [button setTitle:@"GT"
                forState:UIControlStateNormal];

        [button setTitleColor:UIColor.whiteColor
                     forState:UIControlStateNormal];

        button.titleLabel.font =
            [UIFont systemFontOfSize:14.0
                             weight:UIFontWeightBold];

        button.backgroundColor =
            [UIColor colorWithRed:0.82
                           green:0.12
                            blue:0.95
                           alpha:0.92];

        button.layer.cornerRadius = 22.0;
        button.layer.borderWidth = 1.0;
        button.layer.borderColor =
            [UIColor colorWithWhite:1.0 alpha:0.65].CGColor;

        button.layer.shadowOpacity = 0.25;
        button.layer.shadowRadius = 6.0;
        button.layer.shadowOffset = CGSizeMake(0.0, 2.0);

        [button addTarget:UIApplication.sharedApplication
                   action:@selector(gt_sceneInspectorButtonTapped:)
         forControlEvents:UIControlEventTouchUpInside];

        [rootController.view addSubview:button];

        overlayWindow.gtButton = button;
        overlayWindow.gtCaptureActive = NO;

        [GTInspectorWindowsByScene setObject:overlayWindow
                                      forKey:scene];
    }

    return overlayWindow;
}

static void GTUpdateSceneInspectorForSourceWindow(UIWindow *sourceWindow) {
    if (!sourceWindow ||
        [sourceWindow isKindOfClass:[GTInspectorOverlayWindow class]]) {
        return;
    }

    UIWindowScene *scene = sourceWindow.windowScene;

    if (!scene) {
        return;
    }

    BOOL shouldShow =
        GTElementInspector &&
        GTShouldApplyBase() &&
        GTInspectorProcessIsEligible();

    GTInspectorOverlayWindow *overlayWindow =
        GTInspectorWindowForScene(scene, shouldShow);

    if (!overlayWindow) {
        return;
    }

    if (shouldShow) {
        if (GTInspectorCanUseSourceWindow(sourceWindow) &&
            (sourceWindow.isKeyWindow ||
             !GTInspectorCanUseSourceWindow(overlayWindow.gtSourceWindow))) {
            overlayWindow.gtSourceWindow = sourceWindow;
        }

        overlayWindow.frame = scene.coordinateSpace.bounds;
        overlayWindow.hidden = NO;
        overlayWindow.alpha = 1.0;
        overlayWindow.userInteractionEnabled = YES;

        [overlayWindow.rootViewController.view
            bringSubviewToFront:overlayWindow.gtButton];
    } else {
        GTRemoveInspectorCapture(overlayWindow);
        overlayWindow.hidden = YES;
        overlayWindow.gtSourceWindow = nil;
    }
}

static void GTRefreshInspectorAcrossAllScenes(void) {
    if (!GTElementInspector ||
        !GTShouldApplyBase() ||
        !GTInspectorProcessIsEligible()) {
        // Hide any previously-created inspector windows if the feature is off.
        if (GTInspectorWindowsByScene) {
            NSEnumerator *keyEnumerator =
                GTInspectorWindowsByScene.keyEnumerator;

            UIWindowScene *scene = nil;

            while ((scene = [keyEnumerator nextObject])) {
                GTInspectorOverlayWindow *overlayWindow =
                    [GTInspectorWindowsByScene objectForKey:scene];

                if (overlayWindow) {
                    GTRemoveInspectorCapture(overlayWindow);
                    overlayWindow.hidden = YES;
                    overlayWindow.gtSourceWindow = nil;
                }
            }
        }

        return;
    }

    UIApplication *application = UIApplication.sharedApplication;

    if (!application) {
        return;
    }

    NSSet<UIScene *> *connectedScenes = application.connectedScenes;

    for (UIScene *sceneObject in connectedScenes) {
        if (![sceneObject isKindOfClass:[UIWindowScene class]]) {
            continue;
        }

        UIWindowScene *scene = (UIWindowScene *)sceneObject;

        if (scene.activationState == UISceneActivationStateUnattached) {
            continue;
        }

        UIWindow *sourceWindow =
            GTInspectorBestSourceWindow(scene);

        if (sourceWindow) {
            GTUpdateSceneInspectorForSourceWindow(sourceWindow);
            continue;
        }

        // Even if no best source was selected yet, walk every eligible window.
        for (UIWindow *window in scene.windows) {
            if (GTInspectorCanUseSourceWindow(window)) {
                GTUpdateSceneInspectorForSourceWindow(window);
                break;
            }
        }
    }
}

static void GTScheduleInspectorRefreshes(void) {
    if (!GTElementInspector) {
        return;
    }

    NSArray<NSNumber *> *delays = @[
        @0.0,
        @0.20,
        @0.60,
        @1.20,
        @2.50
    ];

    for (NSNumber *delayValue in delays) {
        NSTimeInterval delay = delayValue.doubleValue;

        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                (int64_t)(delay * NSEC_PER_SEC)
            ),
            dispatch_get_main_queue(),
            ^{
                GTRefreshInspectorAcrossAllScenes();
            }
        );
    }
}

@interface UIApplication (GlobalTintInspectorLifecycle)
- (void)gt_inspectorLifecycleRefresh:(NSNotification *)notification;
@end

@implementation UIApplication (GlobalTintInspectorLifecycle)

- (void)gt_inspectorLifecycleRefresh:(NSNotification *)notification {
    GTScheduleInspectorRefreshes();
}

@end

static void GTInstallInspectorLifecycleObservers(void) {
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        NSNotificationCenter *center =
            NSNotificationCenter.defaultCenter;

        UIApplication *application =
            UIApplication.sharedApplication;

        if (!application) {
            return;
        }

        NSArray<NSNotificationName> *names = @[
            UIApplicationDidBecomeActiveNotification,
            UIWindowDidBecomeKeyNotification,
            UIWindowDidBecomeVisibleNotification
        ];

        for (NSNotificationName name in names) {
            [center addObserver:application
                       selector:@selector(gt_inspectorLifecycleRefresh:)
                           name:name
                         object:nil];
        }
    });
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
    if ([window isKindOfClass:[GTInspectorOverlayWindow class]]) {
        return;
    }

    BOOL apply = GTShouldApplyComponent(@"Window", GTEnableWindowTint, YES);
    GTApplyOrRestoreTint(window, apply, GTColorForComponent(@"WindowColor", GTWindowHex));
    GTApplyDebugBorder(window);
    GTUpdateSceneInspectorForSourceWindow(window);
}

static void GTApplySwitchControl(UISwitch *control) {
    BOOL apply = GTShouldApplyComponent(@"Switch", GTEnableSwitch, GTApplyControls);

    UIColor *color = GTColorForComponent(@"SwitchColor", GTSwitchHex);

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
    BOOL apply = GTShouldApplyComponent(@"Slider", GTEnableSlider, GTApplyControls);

    UIColor *color = GTColorForComponent(@"SliderColor", GTSliderHex);

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
    BOOL apply = GTShouldApplyComponent(@"Progress", GTEnableProgress, GTApplyControls);

    UIColor *color = GTColorForComponent(@"ProgressColor", GTProgressHex);

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
    BOOL apply = GTShouldApplyComponent(@"Segmented", GTEnableSegmented, GTApplyControls);

    UIColor *color = GTColorForComponent(@"SegmentedColor", GTSegmentedHex);

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
    BOOL apply = GTShouldApplyComponent(@"PageControl", GTEnablePageControl, GTApplyControls);

    UIColor *color = GTColorForComponent(@"PageControlColor", GTPageControlHex);

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
    BOOL apply = GTShouldApplyComponent(@"RefreshControl", GTEnableRefreshControl, GTApplyControls);

    GTApplyOrRestoreTint(control,
                         apply,
                         GTColorForComponent(@"RefreshControlColor", GTRefreshControlHex));
}

static void GTApplyNavigationBar(UINavigationBar *bar) {
    BOOL apply = GTShouldApplyComponent(@"NavigationBar", GTEnableNavigationBar, GTApplyBars);

    GTApplyOrRestoreTint(bar,
                         apply,
                         GTColorForComponent(@"NavigationBarColor", GTNavigationBarHex));
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

static void GTColorTabBarBadgeState(
    UITabBarItemStateAppearance *state,
    UIColor *backgroundColor,
    UIColor *textColor
) {
    if (!state) {
        return;
    }

    if (backgroundColor) {
        state.badgeBackgroundColor = backgroundColor;
    }

    if (textColor) {
        state.badgeTextAttributes =
            GTTitleAttributesWithColor(
                state.badgeTextAttributes,
                textColor
            );
    }
}

static void GTColorTabBarItemAppearance(
    UITabBarItemAppearance *appearance,
    UIColor *tabColor,
    BOOL applyTabColor,
    UIColor *badgeBackgroundColor,
    UIColor *badgeTextColor,
    BOOL applyBadge
) {
    if (!appearance) {
        return;
    }

    if (applyTabColor && tabColor) {
        appearance.selected.iconColor = tabColor;
        appearance.selected.titleTextAttributes =
            GTTitleAttributesWithColor(
                appearance.selected.titleTextAttributes,
                tabColor
            );
    }

    if (applyBadge) {
        GTColorTabBarBadgeState(
            appearance.normal,
            badgeBackgroundColor,
            badgeTextColor
        );

        GTColorTabBarBadgeState(
            appearance.selected,
            badgeBackgroundColor,
            badgeTextColor
        );

        GTColorTabBarBadgeState(
            appearance.disabled,
            badgeBackgroundColor,
            badgeTextColor
        );

        GTColorTabBarBadgeState(
            appearance.focused,
            badgeBackgroundColor,
            badgeTextColor
        );
    }
}

static UITabBarAppearance *GTColoredTabBarAppearance(
    UITabBarAppearance *source,
    UIColor *tabColor,
    BOOL applyTabColor,
    UIColor *badgeBackgroundColor,
    UIColor *badgeTextColor,
    BOOL applyBadge
) {
    if (!source) {
        return source;
    }

    UITabBarAppearance *appearance = [source copy];

    GTColorTabBarItemAppearance(
        appearance.stackedLayoutAppearance,
        tabColor,
        applyTabColor,
        badgeBackgroundColor,
        badgeTextColor,
        applyBadge
    );

    GTColorTabBarItemAppearance(
        appearance.inlineLayoutAppearance,
        tabColor,
        applyTabColor,
        badgeBackgroundColor,
        badgeTextColor,
        applyBadge
    );

    GTColorTabBarItemAppearance(
        appearance.compactInlineLayoutAppearance,
        tabColor,
        applyTabColor,
        badgeBackgroundColor,
        badgeTextColor,
        applyBadge
    );

    if (applyTabColor && tabColor) {
        appearance.selectionIndicatorTintColor = tabColor;
    }

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

static id GTBoxNullableObject(id value) {
    return value ?: (id)[NSNull null];
}

static id GTUnboxNullableObject(id value) {
    return (value && value != [NSNull null])
        ? value
        : nil;
}

static void GTRememberTabBarBadgeItem(UITabBarItem *item) {
    if (!item) {
        return;
    }

    if (!objc_getAssociatedObject(
            item,
            &GTOriginalBadgeColorKey)) {

        objc_setAssociatedObject(
            item,
            &GTOriginalBadgeColorKey,
            GTBoxNullableObject(item.badgeColor),
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
    }

    if (!objc_getAssociatedObject(
            item,
            &GTOriginalBadgeNormalTextAttributesKey)) {

        NSDictionary *attributes =
            [item badgeTextAttributesForState:
                UIControlStateNormal];

        objc_setAssociatedObject(
            item,
            &GTOriginalBadgeNormalTextAttributesKey,
            GTBoxNullableObject(
                attributes ? [attributes copy] : nil
            ),
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
    }

    if (!objc_getAssociatedObject(
            item,
            &GTOriginalBadgeSelectedTextAttributesKey)) {

        NSDictionary *attributes =
            [item badgeTextAttributesForState:
                UIControlStateSelected];

        objc_setAssociatedObject(
            item,
            &GTOriginalBadgeSelectedTextAttributesKey,
            GTBoxNullableObject(
                attributes ? [attributes copy] : nil
            ),
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
    }
}

static void GTRestoreTabBarBadgeItem(UITabBarItem *item) {
    if (!item) {
        return;
    }

    id originalColor =
        objc_getAssociatedObject(
            item,
            &GTOriginalBadgeColorKey
        );

    id normalAttributes =
        objc_getAssociatedObject(
            item,
            &GTOriginalBadgeNormalTextAttributesKey
        );

    id selectedAttributes =
        objc_getAssociatedObject(
            item,
            &GTOriginalBadgeSelectedTextAttributesKey
        );

    if (!originalColor &&
        !normalAttributes &&
        !selectedAttributes) {
        return;
    }

    objc_setAssociatedObject(
        item,
        &GTApplyingBadgeAppearanceKey,
        @YES,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );

    if (originalColor) {
        item.badgeColor =
            GTUnboxNullableObject(originalColor);
    }

    if (normalAttributes) {
        [item setBadgeTextAttributes:
            GTUnboxNullableObject(normalAttributes)
            forState:UIControlStateNormal];
    }

    if (selectedAttributes) {
        [item setBadgeTextAttributes:
            GTUnboxNullableObject(selectedAttributes)
            forState:UIControlStateSelected];
    }

    objc_setAssociatedObject(
        item,
        &GTApplyingBadgeAppearanceKey,
        nil,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );

    objc_setAssociatedObject(
        item,
        &GTOriginalBadgeColorKey,
        nil,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );

    objc_setAssociatedObject(
        item,
        &GTOriginalBadgeNormalTextAttributesKey,
        nil,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );

    objc_setAssociatedObject(
        item,
        &GTOriginalBadgeSelectedTextAttributesKey,
        nil,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
}

static void GTApplyTabBarBadgeItem(
    UITabBarItem *item,
    BOOL apply,
    UIColor *backgroundColor,
    UIColor *textColor
) {
    if (!item) {
        return;
    }

    if (!apply) {
        GTRestoreTabBarBadgeItem(item);
        return;
    }

    GTRememberTabBarBadgeItem(item);

    objc_setAssociatedObject(
        item,
        &GTApplyingBadgeAppearanceKey,
        @YES,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );

    if (backgroundColor) {
        item.badgeColor = backgroundColor;
    }

    if (textColor) {
        NSDictionary *normal =
            GTTitleAttributesWithColor(
                [item badgeTextAttributesForState:
                    UIControlStateNormal],
                textColor
            );

        NSDictionary *selected =
            GTTitleAttributesWithColor(
                [item badgeTextAttributesForState:
                    UIControlStateSelected],
                textColor
            );

        [item setBadgeTextAttributes:normal
                            forState:UIControlStateNormal];

        [item setBadgeTextAttributes:selected
                            forState:UIControlStateSelected];
    }

    objc_setAssociatedObject(
        item,
        &GTApplyingBadgeAppearanceKey,
        nil,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
}

static UITabBarAppearance *GTBaseTabBarAppearance(
    id storedOriginal,
    UITabBarAppearance *current
) {
    UITabBarAppearance *original =
        GTUnboxTabAppearance(storedOriginal);

    if (original) {
        return [original copy];
    }

    return current ? [current copy] : nil;
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
            GTRestoreTabBarBadgeItem(item);

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
    BOOL applyTab =
        GTShouldApplyComponent(
            @"TabBar",
            GTEnableTabBar,
            GTApplyBars
        );

    BOOL applyBadge =
        GTShouldApplyComponent(
            @"TabBarBadge",
            GTEnableTabBarBadge,
            GTApplyBars
        );

    UIColor *tabColor =
        GTColorForComponent(
            @"TabBarColor",
            GTTabBarHex
        );

    UIColor *badgeBackgroundColor =
        GTBadgeBackgroundColor();

    UIColor *badgeTextColor =
        GTBadgeTextColor();

    // Legacy/public tint path for selected tab item.
    GTApplyOrRestoreTint(
        bar,
        applyTab,
        tabColor
    );

    if (!applyTab && !applyBadge) {
        GTRestoreTabBarAppearances(bar);
        return;
    }

    GTRememberTabBarAppearances(bar);

    objc_setAssociatedObject(
        bar,
        &GTApplyingTabAppearanceKey,
        @YES,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );

    id originalStandard =
        objc_getAssociatedObject(
            bar,
            &GTOriginalTabBarStandardAppearanceKey
        );

    UITabBarAppearance *standardSource =
        GTBaseTabBarAppearance(
            originalStandard,
            bar.standardAppearance
        );

    UITabBarAppearance *standard =
        GTColoredTabBarAppearance(
            standardSource,
            tabColor,
            applyTab,
            badgeBackgroundColor,
            badgeTextColor,
            applyBadge
        );

    if (standard) {
        bar.standardAppearance = standard;
    }

    id originalScrollEdge =
        objc_getAssociatedObject(
            bar,
            &GTOriginalTabBarScrollEdgeAppearanceKey
        );

    UITabBarAppearance *scrollSource =
        GTBaseTabBarAppearance(
            originalScrollEdge,
            bar.scrollEdgeAppearance
        );

    if (scrollSource) {
        UITabBarAppearance *scrollEdge =
            GTColoredTabBarAppearance(
                scrollSource,
                tabColor,
                applyTab,
                badgeBackgroundColor,
                badgeTextColor,
                applyBadge
            );

        if (scrollEdge) {
            bar.scrollEdgeAppearance = scrollEdge;
        }
    }

    if (@available(iOS 15.0, *)) {
        for (UITabBarItem *item in bar.items) {
            GTApplyTabBarBadgeItem(
                item,
                applyBadge,
                badgeBackgroundColor,
                badgeTextColor
            );

            GTRememberTabBarItemAppearances(item);

            id originalItemStandard =
                objc_getAssociatedObject(
                    item,
                    &GTOriginalTabItemStandardAppearanceKey
                );

            UITabBarAppearance *itemStandardSource =
                GTBaseTabBarAppearance(
                    originalItemStandard,
                    item.standardAppearance
                );

            if (itemStandardSource) {
                item.standardAppearance =
                    GTColoredTabBarAppearance(
                        itemStandardSource,
                        tabColor,
                        applyTab,
                        badgeBackgroundColor,
                        badgeTextColor,
                        applyBadge
                    );
            }

            id originalItemScroll =
                objc_getAssociatedObject(
                    item,
                    &GTOriginalTabItemScrollEdgeAppearanceKey
                );

            UITabBarAppearance *itemScrollSource =
                GTBaseTabBarAppearance(
                    originalItemScroll,
                    item.scrollEdgeAppearance
                );

            if (itemScrollSource) {
                item.scrollEdgeAppearance =
                    GTColoredTabBarAppearance(
                        itemScrollSource,
                        tabColor,
                        applyTab,
                        badgeBackgroundColor,
                        badgeTextColor,
                        applyBadge
                    );
            }
        }
    } else {
        for (UITabBarItem *item in bar.items) {
            GTApplyTabBarBadgeItem(
                item,
                applyBadge,
                badgeBackgroundColor,
                badgeTextColor
            );
        }
    }

    objc_setAssociatedObject(
        bar,
        &GTApplyingTabAppearanceKey,
        nil,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
}

static void GTApplyToolbar(UIToolbar *bar) {
    BOOL apply = GTShouldApplyComponent(@"Toolbar", GTEnableToolbar, GTApplyBars);

    GTApplyOrRestoreTint(bar,
                         apply,
                         GTColorForComponent(@"ToolbarColor", GTToolbarHex));
}

static void GTApplySearchBar(UISearchBar *bar) {
    BOOL apply = GTShouldApplyComponent(@"SearchBar", GTEnableSearchBar, GTApplyBars);

    GTApplyOrRestoreTint(bar,
                         apply,
                         GTColorForComponent(@"SearchBarColor", GTSearchBarHex));
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
        UIColor *replacementTint =
            GTColorEngineReplaceColor(currentTint);

        if (replacementTint && replacementTint != currentTint) {
            GTRememberColorOnce(
                view,
                &GTOriginalResolvedTintKey,
                currentTint
            );
            view.tintColor = replacementTint;
        }

        UIColor *backgroundColor = view.backgroundColor;
        UIColor *replacementBackground =
            GTColorEngineReplaceColor(backgroundColor);

        if (replacementBackground &&
            replacementBackground != backgroundColor) {
            GTRememberColorOnce(
                view,
                &GTOriginalResolvedBackgroundColorKey,
                backgroundColor
            );
            view.backgroundColor = replacementBackground;
        }

        if ([view isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)view;
            UIColor *textColor = label.textColor;
            UIColor *replacementText =
                GTColorEngineReplaceColor(textColor);

            if (replacementText && replacementText != textColor) {
                GTRememberColorOnce(
                    label,
                    &GTOriginalResolvedTextColorKey,
                    textColor
                );
                label.textColor = replacementText;
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

        id background =
            objc_getAssociatedObject(
                view,
                &GTOriginalResolvedBackgroundColorKey
            );

        if (background) {
            view.backgroundColor =
                background == [NSNull null]
                ? nil
                : (UIColor *)background;

            objc_setAssociatedObject(
                view,
                &GTOriginalResolvedBackgroundColorKey,
                nil,
                OBJC_ASSOCIATION_RETAIN_NONATOMIC
            );
        }

        if ([view isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)view;

            id textColor =
                objc_getAssociatedObject(
                    label,
                    &GTOriginalResolvedTextColorKey
                );

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

static void GTApplyResolvedBlueCompatibilityToLayerTree(CALayer *layer) {
    if (!layer) {
        return;
    }

    if (!GTForceResolvedBlue && !GTColorEngineHasLayerState) {
        return;
    }

    BOOL active =
        GTShouldApplyBase() &&
        GTForceResolvedBlue;

    if (active && layer.backgroundColor) {
        UIColor *sourceColor =
            GTConcreteColorFromCGColor(layer.backgroundColor);

        UIColor *replacement =
            GTColorEngineReplaceColor(sourceColor);

        if (replacement && replacement != sourceColor &&
            !GTColorsApproximatelyEqual(sourceColor, replacement, 0.01)) {
            GTRememberColorOnce(
                layer,
                &GTOriginalLayerBackgroundColorKey,
                sourceColor
            );
            GTColorEngineHasLayerState = YES;

            GTColorEngineBypassDepth++;
            CGColorRef replacementCGColor = replacement.CGColor;
            GTColorEngineBypassDepth--;

            GTSetLayerBackgroundColorBypassingEngine(
                layer,
                replacementCGColor
            );
        }
    } else if (!active &&
               GTHasRememberedColor(
                   layer,
                   &GTOriginalLayerBackgroundColorKey
               )) {
        UIColor *original =
            GTRememberedColor(
                layer,
                &GTOriginalLayerBackgroundColorKey
            );

        GTColorEngineBypassDepth++;
        CGColorRef originalCGColor = original.CGColor;
        GTColorEngineBypassDepth--;

        GTSetLayerBackgroundColorBypassingEngine(
            layer,
            originalCGColor
        );

        GTClearRememberedColor(
            layer,
            &GTOriginalLayerBackgroundColorKey
        );
    }

    for (CALayer *sublayer in layer.sublayers) {
        GTApplyResolvedBlueCompatibilityToLayerTree(sublayer);
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
    GTApplyResolvedBlueCompatibilityToLayerTree(window.layer);
    GTApplyRecursively(window);
}

static void GTRefreshKnownWindows(void) {
    GTRunOnMain(^{
        for (UIWindow *window in GTWindows.allObjects) {
            GTApplyResolvedBlueCompatibilityToLayerTree(window.layer);
            GTApplyRecursively(window);
        }

        if (!GTForceResolvedBlue || !GTShouldApplyBase()) {
            GTColorEngineHasLayerState = NO;
        }
    });
}

#pragma mark - Dynamic UIColor interception

// Private UIColor subclasses override resolution/CGColor methods, so hooking
// UIColor alone does not see every path. The analyzed reference tweak hooks
// these concrete classes explicitly. We do the same, but only inside the
// already app-only GlobalTintCore and every hook is a pass-through while the
// compatibility switch is off.
#define GT_DEFINE_DYNAMIC_COLOR_HOOK(SLOT) \
    static UIColor *(*GTOrigResolved_##SLOT)(id, SEL, UITraitCollection *) = NULL; \
    static CGColorRef (*GTOrigCGColor_##SLOT)(id, SEL) = NULL; \
    static UIColor *GTHookResolved_##SLOT(id self, SEL _cmd, UITraitCollection *traits) { \
        UIColor *resolved = GTOrigResolved_##SLOT \
            ? GTOrigResolved_##SLOT(self, _cmd, traits) \
            : (UIColor *)self; \
        return GTColorEngineReplaceColor(resolved); \
    } \
    static CGColorRef GTHookCGColor_##SLOT(id self, SEL _cmd) { \
        CGColorRef original = GTOrigCGColor_##SLOT \
            ? GTOrigCGColor_##SLOT(self, _cmd) \
            : NULL; \
        return GTColorEngineReplaceCGColor(original); \
    }

GT_DEFINE_DYNAMIC_COLOR_HOOK(DeviceRGB)
GT_DEFINE_DYNAMIC_COLOR_HOOK(CGColorBacked)
GT_DEFINE_DYNAMIC_COLOR_HOOK(Dynamic)
GT_DEFINE_DYNAMIC_COLOR_HOOK(DynamicCatalogSystem)
GT_DEFINE_DYNAMIC_COLOR_HOOK(DynamicAppDefined)
GT_DEFINE_DYNAMIC_COLOR_HOOK(DynamicProvider)
GT_DEFINE_DYNAMIC_COLOR_HOOK(DynamicModified)
GT_DEFINE_DYNAMIC_COLOR_HOOK(DynamicCatalog)

static void GTInstallDynamicColorHook(Class cls,
                                      IMP resolvedHook,
                                      IMP *resolvedOriginal,
                                      IMP cgColorHook,
                                      IMP *cgColorOriginal) {
    if (!cls) {
        return;
    }

    SEL resolvedSelector =
        @selector(resolvedColorWithTraitCollection:);

    SEL cgColorSelector =
        @selector(CGColor);

    if (resolvedHook &&
        resolvedOriginal &&
        class_getInstanceMethod(cls, resolvedSelector)) {
        MSHookMessageEx(
            cls,
            resolvedSelector,
            resolvedHook,
            resolvedOriginal
        );
    }

    if (cgColorHook &&
        cgColorOriginal &&
        class_getInstanceMethod(cls, cgColorSelector)) {
        MSHookMessageEx(
            cls,
            cgColorSelector,
            cgColorHook,
            cgColorOriginal
        );
    }
}

#define GT_INSTALL_DYNAMIC_COLOR_HOOK(CLASS_NAME, SLOT) \
    GTInstallDynamicColorHook( \
        objc_getClass(CLASS_NAME), \
        (IMP)GTHookResolved_##SLOT, \
        (IMP *)&GTOrigResolved_##SLOT, \
        (IMP)GTHookCGColor_##SLOT, \
        (IMP *)&GTOrigCGColor_##SLOT \
    )

static void GTInstallDynamicColorHooks(void) {
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        GT_INSTALL_DYNAMIC_COLOR_HOOK("UIDeviceRGBColor", DeviceRGB);
        GT_INSTALL_DYNAMIC_COLOR_HOOK("UICGColor", CGColorBacked);
        GT_INSTALL_DYNAMIC_COLOR_HOOK("UIDynamicColor", Dynamic);
        GT_INSTALL_DYNAMIC_COLOR_HOOK("UIDynamicCatalogSystemColor", DynamicCatalogSystem);
        GT_INSTALL_DYNAMIC_COLOR_HOOK("UIDynamicAppDefinedColor", DynamicAppDefined);
        GT_INSTALL_DYNAMIC_COLOR_HOOK("UIDynamicProviderColor", DynamicProvider);
        GT_INSTALL_DYNAMIC_COLOR_HOOK("UIDynamicModifiedColor", DynamicModified);
        GT_INSTALL_DYNAMIC_COLOR_HOOK("UIDynamicCatalogColor", DynamicCatalog);
    });
}

#undef GT_INSTALL_DYNAMIC_COLOR_HOOK
#undef GT_DEFINE_DYNAMIC_COLOR_HOOK

#pragma mark - Resolved color compatibility

%hook UIView

- (void)setTintColor:(UIColor *)tintColor {
    if (GTColorEngineBypassDepth > 0) {
        %orig(tintColor);
        return;
    }

    UIColor *incoming = tintColor;
    UIColor *replacement = GTColorEngineReplaceColor(incoming);

    if (replacement && replacement != incoming) {
        GTRememberColorOnce(
            self,
            &GTOriginalResolvedTintKey,
            incoming
        );
        incoming = replacement;
    } else if (GTForceResolvedBlue &&
               incoming &&
               !GTLooksLikeResolvedSystemBlue(incoming)) {
        // The host app deliberately changed to a non-target color. Do not
        // restore an obsolete value if the compatibility switch is disabled.
        GTClearRememberedColor(
            self,
            &GTOriginalResolvedTintKey
        );
    }

    %orig(incoming);
}

- (void)setBackgroundColor:(UIColor *)backgroundColor {
    if (GTColorEngineBypassDepth > 0) {
        %orig(backgroundColor);
        return;
    }

    UIColor *incoming = backgroundColor;
    UIColor *replacement = GTColorEngineReplaceColor(incoming);

    if (replacement && replacement != incoming) {
        GTRememberColorOnce(
            self,
            &GTOriginalResolvedBackgroundColorKey,
            incoming
        );
        incoming = replacement;
    } else if (GTForceResolvedBlue &&
               incoming &&
               !GTLooksLikeResolvedSystemBlue(incoming)) {
        GTClearRememberedColor(
            self,
            &GTOriginalResolvedBackgroundColorKey
        );
    }

    %orig(incoming);
}

%end

%hook UILabel

- (void)setTextColor:(UIColor *)textColor {
    if (GTColorEngineBypassDepth > 0) {
        %orig(textColor);
        return;
    }

    UIColor *incoming = textColor;
    UIColor *replacement = GTColorEngineReplaceColor(incoming);

    if (replacement && replacement != incoming) {
        GTRememberColorOnce(
            self,
            &GTOriginalResolvedTextColorKey,
            incoming
        );
        incoming = replacement;
    } else if (GTForceResolvedBlue &&
               incoming &&
               !GTLooksLikeResolvedSystemBlue(incoming)) {
        GTClearRememberedColor(
            self,
            &GTOriginalResolvedTextColorKey
        );
    }

    %orig(incoming);
}

%end

%hook CALayer

- (void)setBackgroundColor:(CGColorRef)backgroundColor {
    if (GTColorEngineBypassDepth > 0 ||
        !backgroundColor ||
        !GTForceResolvedBlue ||
        !GTShouldApplyBase()) {
        %orig(backgroundColor);
        return;
    }

    CGColorRef incoming = backgroundColor;
    UIColor *sourceColor = GTConcreteColorFromCGColor(backgroundColor);

    if (!sourceColor) {
        %orig(backgroundColor);
        return;
    }

    UIColor *replacement = GTColorEngineReplaceColor(sourceColor);

    if (replacement && replacement != sourceColor &&
        !GTColorsApproximatelyEqual(sourceColor, replacement, 0.01)) {
        GTRememberColorOnce(
            self,
            &GTOriginalLayerBackgroundColorKey,
            sourceColor
        );
        GTColorEngineHasLayerState = YES;

        GTColorEngineBypassDepth++;
        incoming = replacement.CGColor;
        GTColorEngineBypassDepth--;
    } else if (GTForceResolvedBlue &&
               !GTLooksLikeResolvedSystemBlue(sourceColor)) {
        GTClearRememberedColor(
            self,
            &GTOriginalLayerBackgroundColorKey
        );
    }

    %orig(incoming);
}

%end

#pragma mark - Semantic UIKit colors

%hook UIColor

+ (UIColor *)systemBlueColor {
    if (GTShouldApplyBase() &&
        (GTReplaceSystemBlue || GTForceResolvedBlue)) {
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
    return GTColorEngineReplaceColor(resolved);
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
        (GTShouldApplyComponent(
            @"TabBar",
            GTEnableTabBar,
            GTApplyBars
        ) ||
         GTShouldApplyComponent(
            @"TabBarBadge",
            GTEnableTabBarBadge,
            GTApplyBars
        ))) {

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
        (GTShouldApplyComponent(
            @"TabBar",
            GTEnableTabBar,
            GTApplyBars
        ) ||
         GTShouldApplyComponent(
            @"TabBarBadge",
            GTEnableTabBarBadge,
            GTApplyBars
        ))) {

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

%hook UITabBarItem

- (void)setBadgeValue:(NSString *)badgeValue {
    %orig(badgeValue);

    BOOL applyBadge =
        GTShouldApplyComponent(
            @"TabBarBadge",
            GTEnableTabBarBadge,
            GTApplyBars
        );

    GTApplyTabBarBadgeItem(
        self,
        applyBadge,
        GTBadgeBackgroundColor(),
        GTBadgeTextColor()
    );
}

- (void)setBadgeColor:(UIColor *)badgeColor {
    BOOL internalApply =
        [objc_getAssociatedObject(
            self,
            &GTApplyingBadgeAppearanceKey
        ) boolValue];

    BOOL applyBadge =
        GTShouldApplyComponent(
            @"TabBarBadge",
            GTEnableTabBarBadge,
            GTApplyBars
        );

    if (!internalApply && applyBadge) {
        objc_setAssociatedObject(
            self,
            &GTOriginalBadgeColorKey,
            GTBoxNullableObject(badgeColor),
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
    } else if (!internalApply && !applyBadge) {
        objc_setAssociatedObject(
            self,
            &GTOriginalBadgeColorKey,
            nil,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
    }

    %orig(badgeColor);

    if (!internalApply) {
        GTApplyTabBarBadgeItem(
            self,
            applyBadge,
            GTBadgeBackgroundColor(),
            GTBadgeTextColor()
        );
    }
}

- (void)setBadgeTextAttributes:(NSDictionary *)textAttributes
                      forState:(UIControlState)state {

    BOOL internalApply =
        [objc_getAssociatedObject(
            self,
            &GTApplyingBadgeAppearanceKey
        ) boolValue];

    BOOL applyBadge =
        GTShouldApplyComponent(
            @"TabBarBadge",
            GTEnableTabBarBadge,
            GTApplyBars
        );

    if (!internalApply && applyBadge) {
        char *key = NULL;

        if (state == UIControlStateNormal) {
            key = &GTOriginalBadgeNormalTextAttributesKey;
        } else if (state == UIControlStateSelected) {
            key = &GTOriginalBadgeSelectedTextAttributesKey;
        }

        if (key) {
            objc_setAssociatedObject(
                self,
                key,
                GTBoxNullableObject(
                    textAttributes
                    ? [textAttributes copy]
                    : nil
                ),
                OBJC_ASSOCIATION_RETAIN_NONATOMIC
            );
        }
    }

    %orig(textAttributes, state);

    if (!internalApply) {
        GTApplyTabBarBadgeItem(
            self,
            applyBadge,
            GTBadgeBackgroundColor(),
            GTBadgeTextColor()
        );
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

    UIColor *color = GTColorForComponent(@"ToolbarColor", GTToolbarHex);
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

    UIColor *color = GTColorForComponent(@"ToolbarColor", GTToolbarHex);
    self.tintColor = color;

    SEL selector = NSSelectorFromString(@"setInteractionTintColor:");

    if ([self respondsToSelector:selector]) {
        ((void (*)(id, SEL, id))objc_msgSend)(self, selector, color);
    }
}

%end

#pragma mark - Preferences

static NSString * const GTPrefsFilePath =
    @"/var/mobile/Library/Preferences/com.benja.globaltint.plist";

static void GTApplyPreferencesSandboxExtension(void) {
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        NSString *sandyPath =
            jbroot(@"/usr/lib/libsandy.dylib");

        void *handle =
            dlopen(sandyPath.UTF8String, RTLD_LAZY | RTLD_LOCAL);

        if (!handle) {
            return;
        }

        typedef int (*GTLibSandyApplyProfile)(const char *);

        GTLibSandyApplyProfile applyProfile =
            (GTLibSandyApplyProfile)dlsym(
                handle,
                "libSandy_applyProfile"
            );

        if (applyProfile) {
            applyProfile("com.benja.globaltint");
        }
    });
}

static BOOL GTBoolPreference(NSString *key, BOOL fallback) {
    id value = [GTPreferences objectForKey:key];

    if ([value respondsToSelector:@selector(boolValue)]) {
        return [value boolValue];
    }

    return fallback;
}

static NSString *GTStringPreference(NSString *key,
                                    NSString *fallback) {
    id value = [GTPreferences objectForKey:key];

    if ([value isKindOfClass:[NSString class]]) {
        return [(NSString *)value copy];
    }

    return [fallback copy];
}

static NSDictionary *GTDictionaryPreference(NSString *key) {
    id value = [GTPreferences objectForKey:key];

    if ([value isKindOfClass:[NSDictionary class]]) {
        return [(NSDictionary *)value copy];
    }

    return @{};
}

static NSDictionary<NSString *, NSString *> *
GTNormalizedAppColorOverrides(NSDictionary *source) {
    if (![source isKindOfClass:[NSDictionary class]] ||
        source.count == 0) {
        return @{};
    }

    NSMutableDictionary<NSString *, NSString *> *result =
        [NSMutableDictionary dictionary];

    [source enumerateKeysAndObjectsUsingBlock:
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
            [(NSString *)rawValue
             stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]];

        if (bundleID.length == 0 ||
            !GTColorFromHexOrNil(hex)) {
            return;
        }

        result[bundleID] = hex.uppercaseString;
    }];

    return [result copy];
}

static NSDictionary<NSString *,
                            NSDictionary<NSString *, NSString *> *> *
GTNormalizedAppComponentColorOverrides(NSDictionary *source) {
    if (![source isKindOfClass:[NSDictionary class]] ||
        source.count == 0) {
        return @{};
    }

    NSSet<NSString *> *allowedKeys =
        [NSSet setWithArray:@[
            @"WindowColor",
            @"SwitchColor",
            @"SliderColor",
            @"ProgressColor",
            @"SegmentedColor",
            @"PageControlColor",
            @"RefreshControlColor",
            @"NavigationBarColor",
            @"TabBarColor",
            @"BadgeBackgroundColor",
            @"BadgeTextColor",
            @"ToolbarColor",
            @"SearchBarColor"
        ]];

    NSMutableDictionary *result =
        [NSMutableDictionary dictionary];

    [source enumerateKeysAndObjectsUsingBlock:
        ^(id rawBundleID, id rawRules, BOOL *stop) {

        if (![rawBundleID isKindOfClass:[NSString class]] ||
            ![rawRules isKindOfClass:[NSDictionary class]]) {
            return;
        }

        NSString *bundleID =
            [[(NSString *)rawBundleID
              stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]]
             lowercaseString];

        if (bundleID.length == 0) {
            return;
        }

        NSMutableDictionary<NSString *, NSString *> *rules =
            [NSMutableDictionary dictionary];

        [(NSDictionary *)rawRules enumerateKeysAndObjectsUsingBlock:
            ^(id rawKey, id rawValue, BOOL *innerStop) {

            if (![rawKey isKindOfClass:[NSString class]] ||
                ![rawValue isKindOfClass:[NSString class]]) {
                return;
            }

            NSString *componentKey = (NSString *)rawKey;

            if (![allowedKeys containsObject:componentKey]) {
                return;
            }

            NSString *hex =
                [(NSString *)rawValue
                 stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceAndNewlineCharacterSet]];

            if (!GTColorFromHexOrNil(hex)) {
                return;
            }

            rules[componentKey] = hex.uppercaseString;
        }];

        if (rules.count > 0) {
            result[bundleID] = [rules copy];
        }
    }];

    return [result copy];
}

static NSDictionary<NSString *,
                            NSDictionary<NSString *, NSNumber *> *> *
GTNormalizedAppComponentSwitchOverrides(NSDictionary *source) {
    if (![source isKindOfClass:[NSDictionary class]] ||
        source.count == 0) {
        return @{};
    }

    NSSet<NSString *> *allowedKeys =
        [NSSet setWithArray:@[
            @"Window",
            @"Switch",
            @"Slider",
            @"Progress",
            @"Segmented",
            @"PageControl",
            @"RefreshControl",
            @"NavigationBar",
            @"TabBar",
            @"TabBarBadge",
            @"Toolbar",
            @"SearchBar"
        ]];

    NSMutableDictionary *result =
        [NSMutableDictionary dictionary];

    [source enumerateKeysAndObjectsUsingBlock:
        ^(id rawBundleID, id rawRules, BOOL *stop) {

        if (![rawBundleID isKindOfClass:[NSString class]] ||
            ![rawRules isKindOfClass:[NSDictionary class]]) {
            return;
        }

        NSString *bundleID =
            [[(NSString *)rawBundleID
              stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]]
             lowercaseString];

        if (bundleID.length == 0) {
            return;
        }

        NSMutableDictionary<NSString *, NSNumber *> *rules =
            [NSMutableDictionary dictionary];

        [(NSDictionary *)rawRules enumerateKeysAndObjectsUsingBlock:
            ^(id rawKey, id rawValue, BOOL *innerStop) {

            if (![rawKey isKindOfClass:[NSString class]] ||
                ![allowedKeys containsObject:(NSString *)rawKey] ||
                ![rawValue respondsToSelector:@selector(boolValue)]) {
                return;
            }

            rules[(NSString *)rawKey] =
                @([rawValue boolValue]);
        }];

        if (rules.count > 0) {
            result[bundleID] = [rules copy];
        }
    }];

    return [result copy];
}

static void GTLoadPreferencesFromDisk(void) {
    if (!GTPreferences) {
        return;
    }

    // NSUserDefaults with a full plist path is the libSandy-supported pattern
    // for sandboxed tweak processes on modern iOS.
    [GTPreferences synchronize];

    GTEnabled =
        GTBoolPreference(@"Enabled", YES);

    GTEnableWindowTint =
        GTBoolPreference(@"ApplyWindowTint", YES);

    GTApplyControls =
        GTBoolPreference(@"ApplyControls", YES);

    GTApplyBars =
        GTBoolPreference(@"ApplyBars", YES);

    GTUseSeparateColors =
        GTBoolPreference(@"UseSeparateColors", NO);

    GTEnableAppColorOverrides =
        GTBoolPreference(@"EnableAppColorOverrides", YES);

    GTEnableAppComponentSwitchOverrides =
        GTBoolPreference(@"EnableAppComponentSwitchOverrides", YES);

    GTReplaceSystemBlue =
        GTBoolPreference(@"ReplaceSystemBlue", NO);

    GTReplaceLinkColor =
        GTBoolPreference(@"ReplaceLinkColor", NO);

    GTDebugInjectionBorder =
        GTBoolPreference(@"DebugInjectionBorder", NO);

    GTForceResolvedBlue =
        GTBoolPreference(@"ForceResolvedBlue", NO);

    GTElementInspector =
        GTBoolPreference(@"ElementInspector", NO);

    GTEnableSwitch =
        GTBoolPreference(@"ApplySwitch", YES);

    GTEnableSlider =
        GTBoolPreference(@"ApplySlider", YES);

    GTEnableProgress =
        GTBoolPreference(@"ApplyProgress", YES);

    GTEnableSegmented =
        GTBoolPreference(@"ApplySegmented", YES);

    GTEnablePageControl =
        GTBoolPreference(@"ApplyPageControl", YES);

    GTEnableRefreshControl =
        GTBoolPreference(@"ApplyRefreshControl", YES);

    GTEnableNavigationBar =
        GTBoolPreference(@"ApplyNavigationBar", YES);

    GTEnableTabBar =
        GTBoolPreference(@"ApplyTabBar", YES);

    GTEnableTabBarBadge =
        GTBoolPreference(@"ApplyTabBarBadge", NO);

    GTEnableToolbar =
        GTBoolPreference(@"ApplyToolbar", YES);

    GTEnableSearchBar =
        GTBoolPreference(@"ApplySearchBar", YES);

    GTAccentHex =
        GTStringPreference(@"AccentColor", @"#0A84FF");

    GTSemanticBlueHex =
        GTStringPreference(@"SemanticBlueColor", @"");

    GTWindowHex =
        GTStringPreference(@"WindowColor", @"");

    GTSwitchHex =
        GTStringPreference(@"SwitchColor", @"");

    GTSliderHex =
        GTStringPreference(@"SliderColor", @"");

    GTProgressHex =
        GTStringPreference(@"ProgressColor", @"");

    GTSegmentedHex =
        GTStringPreference(@"SegmentedColor", @"");

    GTPageControlHex =
        GTStringPreference(@"PageControlColor", @"");

    GTRefreshControlHex =
        GTStringPreference(@"RefreshControlColor", @"");

    GTNavigationBarHex =
        GTStringPreference(@"NavigationBarColor", @"");

    GTTabBarHex =
        GTStringPreference(@"TabBarColor", @"");

    GTBadgeBackgroundHex =
        GTStringPreference(@"BadgeBackgroundColor", @"");

    GTBadgeTextHex =
        GTStringPreference(@"BadgeTextColor", @"");

    GTToolbarHex =
        GTStringPreference(@"ToolbarColor", @"");

    GTSearchBarHex =
        GTStringPreference(@"SearchBarColor", @"");

    GTExcludedBundleIDs =
        GTStringPreference(@"ExcludedBundleIDs", @"");

    GTAppColorOverrides =
        GTNormalizedAppColorOverrides(
            GTDictionaryPreference(@"AppColorOverrides")
        );

    GTAppComponentColorOverrides =
        GTNormalizedAppComponentColorOverrides(
            GTDictionaryPreference(@"AppComponentColorOverrides")
        );

    GTAppComponentSwitchOverrides =
        GTNormalizedAppComponentSwitchOverrides(
            GTDictionaryPreference(@"AppComponentSwitchOverrides")
        );

    GTAccentColor =
        GTColorFromHexOrNil(GTAccentHex) ?: GTDefaultAccentColor();

    GTRebuildExcludedBundles();
}

static void GTPreferencesDarwinCallback(
    CFNotificationCenterRef center,
    void *observer,
    CFStringRef name,
    const void *object,
    CFDictionaryRef userInfo
) {
    GTLoadPreferencesFromDisk();

    GTRefreshKnownWindows();

    GTRunOnMain(^{
        GTRefreshInspectorAcrossAllScenes();
        GTScheduleInspectorRefreshes();
    });
}

static void GTRegisterPreferences(void) {
    GTApplyPreferencesSandboxExtension();

    GTPreferences =
        [[NSUserDefaults alloc]
         initWithSuiteName:GTPrefsFilePath];

    [GTPreferences registerDefaults:@{
        @"Enabled": @YES,
        @"ApplyWindowTint": @YES,
        @"ApplyControls": @YES,
        @"ApplyBars": @YES,
        @"UseSeparateColors": @NO,
        @"EnableAppColorOverrides": @YES,
        @"EnableAppComponentSwitchOverrides": @YES,
        @"ReplaceSystemBlue": @NO,
        @"ReplaceLinkColor": @NO,
        @"DebugInjectionBorder": @NO,
        @"ForceResolvedBlue": @NO,
        @"ElementInspector": @NO,
        @"ApplySwitch": @YES,
        @"ApplySlider": @YES,
        @"ApplyProgress": @YES,
        @"ApplySegmented": @YES,
        @"ApplyPageControl": @YES,
        @"ApplyRefreshControl": @YES,
        @"ApplyNavigationBar": @YES,
        @"ApplyTabBar": @YES,
        @"ApplyTabBarBadge": @NO,
        @"ApplyToolbar": @YES,
        @"ApplySearchBar": @YES,
        @"AccentColor": @"#0A84FF",
        @"SemanticBlueColor": @"",
        @"WindowColor": @"",
        @"SwitchColor": @"",
        @"SliderColor": @"",
        @"ProgressColor": @"",
        @"SegmentedColor": @"",
        @"PageControlColor": @"",
        @"RefreshControlColor": @"",
        @"NavigationBarColor": @"",
        @"TabBarColor": @"",
        @"BadgeBackgroundColor": @"",
        @"BadgeTextColor": @"",
        @"ToolbarColor": @"",
        @"SearchBarColor": @"",
        @"ExcludedBundleIDs": @"",
        @"AppColorOverrides": @{},
        @"AppComponentColorOverrides": @{},
        @"AppComponentSwitchOverrides": @{}
    }];

    GTLoadPreferencesFromDisk();

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        GTPreferencesDarwinCallback,
        CFSTR("com.benja.globaltint/ReloadPrefs"),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
}

#pragma mark - Bootstrap

%ctor {
    @autoreleasepool {
        // Keep app extensions out.
        NSString *bundleExtension =
            NSBundle.mainBundle.bundleURL.pathExtension.lowercaseString;

        if ([bundleExtension isEqualToString:@"appex"]) {
            return;
        }

        // V0.4.2 defense-in-depth. The pure-C loader should never dlopen this
        // core inside SpringBoard, but refuse again before preferences/%init.
        NSString *processBundleID =
            NSBundle.mainBundle.bundleIdentifier.lowercaseString;

        if ([processBundleID
             isEqualToString:@"com.apple.springboard"]) {
            return;
        }

        // GlobalTintCore is manually loaded only in eligible full apps.
        // Relaxin's App List decide which processes are injected. Refuse to
        // initialize GlobalTint in non-UIKit daemon/tool processes.
        Class applicationClass = objc_getClass("UIApplication");

        if (!applicationClass) {
            return;
        }

        GTWindows = [NSHashTable weakObjectsHashTable];
        GTRegisterPreferences();

        // A custom Logos constructor is used, so initialize hooks explicitly.
        %init;

        // Private dynamic UIColor subclasses override UIColor's resolution and
        // CGColor paths. Hook them only after the public Logos layer is ready.
        GTInstallDynamicColorHooks();

        // The optional UI inspector is implemented with its own
        // pass-through UIWindowScene overlay. Keep it synchronized with app
        // and window lifecycle events without modifying UIApplication event
        // dispatch.
        dispatch_async(dispatch_get_main_queue(), ^{
            GTInstallInspectorLifecycleObservers();
            GTScheduleInspectorRefreshes();
        });
    }
}
