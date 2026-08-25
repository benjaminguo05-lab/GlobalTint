#import <UIKit/UIKit.h>
#include <roothide.h>
#include <dlfcn.h>
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

// SpringBoard / System UI foundation (V0.4.0)
static BOOL GTEnableSystemUI = NO;
static BOOL GTEnableControlCenter = YES;
static BOOL GTEnableLockScreen = YES;
static BOOL GTEnableSystemMenus = YES;

static NSString *GTSystemAccentHex = @"";
static NSString *GTControlCenterHex = @"";
static NSString *GTLockScreenHex = @"";
static NSString *GTSystemMenuHex = @"";

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
static char GTOriginalWindowBorderWidthKey;
static char GTOriginalWindowBorderColorKey;
static char GTOriginalResolvedTintKey;
static char GTOriginalResolvedTextColorKey;
static char GTOriginalSystemUITintColorKey;
static char GTOriginalSystemUITextColorKey;

static BOOL GTShouldApplyBase(void);
static BOOL GTIsSpringBoardProcess(void);
static BOOL GTInspectorProcessIsEligible(void);
static BOOL GTInspectorWindowIsEligible(UIWindow *window);
static BOOL GTInspectorViewIsEligible(UIView *view);
static void GTApplySystemUIViewIfNeeded(UIView *view);

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
    // Ordinary per-App UIKit rules apply to application processes only.
    // SpringBoard gets its own System UI rule path starting in V0.4.0.
    return
        GTEnabled &&
        !GTCurrentProcessIsExcluded() &&
        !GTIsSpringBoardProcess();
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

static BOOL GTIsSpringBoardProcess(void) {
    NSString *bundleID =
        NSBundle.mainBundle.bundleIdentifier.lowercaseString;

    return [bundleID
        isEqualToString:@"com.apple.springboard"];
}

static BOOL GTInspectorProcessIsEligible(void) {
    // SpringBoard is now inspectable. GTInspectorWindowIsEligible still
    // rejects _UISystemGestureWindow / UISystemGestureView.
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
    UIWindow *topCandidate = nil;

    for (UIWindow *window in scene.windows) {
        if (!GTInspectorCanUseSourceWindow(window)) {
            continue;
        }

        if (window.isKeyWindow) {
            keyCandidate = window;
        }

        if (!topCandidate ||
            window.windowLevel > topCandidate.windowLevel) {
            topCandidate = window;
        }
    }

    return keyCandidate ?: topCandidate;
}

static UIView *GTInspectorHitTestSceneAtPoint(
    UIWindowScene *scene,
    GTInspectorOverlayWindow *overlayWindow,
    CGPoint overlayPoint,
    UIWindow **matchedWindow
) {
    if (matchedWindow) {
        *matchedWindow = nil;
    }

    if (!scene || !overlayWindow) {
        return nil;
    }

    NSArray<UIWindow *> *windows =
        [scene.windows sortedArrayUsingComparator:
            ^NSComparisonResult(UIWindow *left, UIWindow *right) {

        if (left.windowLevel > right.windowLevel) {
            return NSOrderedAscending;
        }

        if (left.windowLevel < right.windowLevel) {
            return NSOrderedDescending;
        }

        return NSOrderedSame;
    }];

    for (UIWindow *window in windows) {
        if (!GTInspectorCanUseSourceWindow(window)) {
            continue;
        }

        CGPoint point =
            [overlayWindow convertPoint:overlayPoint
                               toWindow:window];

        UIView *hit =
            [window hitTest:point withEvent:nil];

        if (!GTInspectorViewIsEligible(hit)) {
            continue;
        }

        if (matchedWindow) {
            *matchedWindow = window;
        }

        return hit;
    }

    return nil;
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

    // Remove the capture interception first, then search all eligible windows
    // from highest to lowest. This is important in SpringBoard because Control
    // Center, Lock Screen and menus commonly live in separate windows.
    GTRemoveInspectorCapture(overlayWindow);

    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *sourceWindow = nil;

        UIView *hitView =
            GTInspectorHitTestSceneAtPoint(
                overlayWindow.windowScene,
                overlayWindow,
                screenPoint,
                &sourceWindow
            );

        if (!sourceWindow ||
            !GTInspectorViewIsEligible(hitView)) {
            return;
        }

        overlayWindow.gtSourceWindow = sourceWindow;
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
        GTEnabled &&
        !GTCurrentProcessIsExcluded() &&
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
        !GTEnabled ||
        GTCurrentProcessIsExcluded() ||
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

typedef NS_ENUM(NSInteger, GTSystemUIRegion) {
    GTSystemUIRegionNone = 0,
    GTSystemUIRegionControlCenter,
    GTSystemUIRegionLockScreen,
    GTSystemUIRegionMenu
};

static NSString *GTLowerClassName(id object) {
    if (!object) {
        return @"";
    }

    NSString *className =
        NSStringFromClass([object class]);

    return className.lowercaseString ?: @"";
}

static BOOL GTClassNameContainsAny(
    NSString *className,
    NSArray<NSString *> *tokens
) {
    if (className.length == 0) {
        return NO;
    }

    for (NSString *token in tokens) {
        if ([className containsString:
                token.lowercaseString]) {
            return YES;
        }
    }

    return NO;
}

static GTSystemUIRegion GTSystemUIRegionForView(
    UIView *view
) {
    if (!view || !GTIsSpringBoardProcess()) {
        return GTSystemUIRegionNone;
    }

    static NSArray<NSString *> *controlCenterTokens = nil;
    static NSArray<NSString *> *lockScreenTokens = nil;
    static NSArray<NSString *> *menuTokens = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        controlCenterTokens = @[
            @"ccui",
            @"controlcenter",
            @"ccuimodule"
        ];

        lockScreenTokens = @[
            @"coversheet",
            @"lockscreen",
            @"sbuiproudlock",
            @"sbflock",
            @"csquickaction",
            @"cscover",
            @"csmain"
        ];

        menuTokens = @[
            @"contextmenu",
            @"alertcontroller",
            @"alertview",
            @"actionsheet",
            @"uimenu",
            @"uipreview"
        ];
    });

    UIView *cursor = view;

    for (NSInteger depth = 0;
         cursor && depth < 10;
         depth++, cursor = cursor.superview) {

        NSString *className =
            GTLowerClassName(cursor);

        if (GTClassNameContainsAny(
                className,
                controlCenterTokens)) {
            return GTSystemUIRegionControlCenter;
        }

        if (GTClassNameContainsAny(
                className,
                lockScreenTokens)) {
            return GTSystemUIRegionLockScreen;
        }

        if (GTClassNameContainsAny(
                className,
                menuTokens)) {
            return GTSystemUIRegionMenu;
        }
    }

    return GTSystemUIRegionNone;
}

static UIColor *GTSystemBaseAccentColor(void) {
    UIColor *specific =
        GTColorFromHexOrNil(GTSystemAccentHex);

    return specific ?: GTGlobalAccentColor();
}

static UIColor *GTColorForSystemUIRegion(
    GTSystemUIRegion region
) {
    UIColor *base =
        GTSystemBaseAccentColor();

    switch (region) {
        case GTSystemUIRegionControlCenter:
            return
                GTColorFromHexOrNil(GTControlCenterHex)
                ?: base;

        case GTSystemUIRegionLockScreen:
            return
                GTColorFromHexOrNil(GTLockScreenHex)
                ?: base;

        case GTSystemUIRegionMenu:
            return
                GTColorFromHexOrNil(GTSystemMenuHex)
                ?: base;

        case GTSystemUIRegionNone:
        default:
            return base;
    }
}

static BOOL GTSystemUIRegionEnabled(
    GTSystemUIRegion region
) {
    if (!GTEnabled ||
        GTCurrentProcessIsExcluded() ||
        !GTEnableSystemUI ||
        !GTIsSpringBoardProcess()) {
        return NO;
    }

    switch (region) {
        case GTSystemUIRegionControlCenter:
            return GTEnableControlCenter;

        case GTSystemUIRegionLockScreen:
            return GTEnableLockScreen;

        case GTSystemUIRegionMenu:
            return GTEnableSystemMenus;

        case GTSystemUIRegionNone:
        default:
            return NO;
    }
}

static BOOL GTLooksLikeBlueAccentColor(
    UIColor *color
) {
    if (!color) {
        return NO;
    }

    CGFloat r = 0.0;
    CGFloat g = 0.0;
    CGFloat b = 0.0;
    CGFloat a = 0.0;

    if (![color getRed:&r
                 green:&g
                  blue:&b
                 alpha:&a]) {
        return NO;
    }

    return
        a > 0.05 &&
        b > 0.50 &&
        b > r * 1.18 &&
        b > g * 1.03;
}

static void GTApplySystemUIViewIfNeeded(
    UIView *view
) {
    if (!view || !GTIsSpringBoardProcess()) {
        return;
    }

    GTSystemUIRegion region =
        GTSystemUIRegionForView(view);

    BOOL apply =
        GTSystemUIRegionEnabled(region);

    if (apply) {
        UIColor *color =
            GTColorForSystemUIRegion(region);

        if (color) {
            GTRememberColorOnce(
                view,
                &GTOriginalSystemUITintColorKey,
                view.tintColor
            );

            view.tintColor = color;
        }

        if ([view isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)view;

            if (GTLooksLikeBlueAccentColor(
                    label.textColor)) {

                GTRememberColorOnce(
                    label,
                    &GTOriginalSystemUITextColorKey,
                    label.textColor
                );

                CGFloat alpha = 1.0;
                CGFloat r = 0.0;
                CGFloat g = 0.0;
                CGFloat b = 0.0;

                [label.textColor getRed:&r
                                  green:&g
                                   blue:&b
                                  alpha:&alpha];

                label.textColor =
                    [color colorWithAlphaComponent:
                        alpha];
            }
        }

        return;
    }

    if (GTHasRememberedColor(
            view,
            &GTOriginalSystemUITintColorKey)) {

        view.tintColor =
            GTRememberedColor(
                view,
                &GTOriginalSystemUITintColorKey
            );

        GTClearRememberedColor(
            view,
            &GTOriginalSystemUITintColorKey
        );
    }

    if ([view isKindOfClass:[UILabel class]] &&
        GTHasRememberedColor(
            view,
            &GTOriginalSystemUITextColorKey)) {

        UILabel *label = (UILabel *)view;

        label.textColor =
            GTRememberedColor(
                label,
                &GTOriginalSystemUITextColorKey
            );

        GTClearRememberedColor(
            label,
            &GTOriginalSystemUITextColorKey
        );
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
    BOOL apply = GTShouldApplyComponent(@"TabBar", GTEnableTabBar, GTApplyBars);

    UIColor *color = GTColorForComponent(@"TabBarColor", GTTabBarHex);

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
    GTApplySystemUIViewIfNeeded(view);

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

- (void)didMoveToWindow {
    %orig;

    if (GTIsSpringBoardProcess()) {
        GTApplySystemUIViewIfNeeded(self);
    }
}

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

    GTEnableSystemUI =
        GTBoolPreference(@"EnableSystemUI", NO);

    GTEnableControlCenter =
        GTBoolPreference(@"EnableControlCenter", YES);

    GTEnableLockScreen =
        GTBoolPreference(@"EnableLockScreen", YES);

    GTEnableSystemMenus =
        GTBoolPreference(@"EnableSystemMenus", YES);

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

    GTToolbarHex =
        GTStringPreference(@"ToolbarColor", @"");

    GTSearchBarHex =
        GTStringPreference(@"SearchBarColor", @"");

    GTSystemAccentHex =
        GTStringPreference(@"SystemAccentColor", @"");

    GTControlCenterHex =
        GTStringPreference(@"ControlCenterColor", @"");

    GTLockScreenHex =
        GTStringPreference(@"LockScreenColor", @"");

    GTSystemMenuHex =
        GTStringPreference(@"SystemMenuColor", @"");

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
        @"EnableSystemUI": @NO,
        @"EnableControlCenter": @YES,
        @"EnableLockScreen": @YES,
        @"EnableSystemMenus": @YES,
        @"ApplySwitch": @YES,
        @"ApplySlider": @YES,
        @"ApplyProgress": @YES,
        @"ApplySegmented": @YES,
        @"ApplyPageControl": @YES,
        @"ApplyRefreshControl": @YES,
        @"ApplyNavigationBar": @YES,
        @"ApplyTabBar": @YES,
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
        @"ToolbarColor": @"",
        @"SearchBarColor": @"",
        @"SystemAccentColor": @"",
        @"ControlCenterColor": @"",
        @"LockScreenColor": @"",
        @"SystemMenuColor": @"",
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

        // The broad com.apple.Security Substrate filter lets
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
