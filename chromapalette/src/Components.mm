#import "Runtime.h"
#import "ContrastPolicy.h"

static UINavigationController *NavigationController(UINavigationBar *bar) {
    for (UIResponder *r=bar.nextResponder;r;r=r.nextResponder)
        if ([r isKindOfClass:UINavigationController.class]) return (id)r;
    return nil;
}
static NSNumber *StatusStyle(UIViewController *controller) {
    UINavigationController *nav=[controller isKindOfClass:UINavigationController.class] ? (id)controller : controller.navigationController;
    UINavigationBar *bar=nav.navigationBar;
    if (!bar.window || nav.navigationBarHidden || bar.hidden || bar.alpha<0.95 || nav.presentedViewController) return nil;
    // A sheet below the status bar must not recolor the presenting app's status.
    CGRect rect=[bar convertRect:bar.bounds toView:bar.window];
    if (CGRectGetMinY(rect)>bar.window.safeAreaInsets.top+2) return nil;
    UIColor *background=CPColor(@"navigation",@"background",bar);
    CGFloat r=0,g=0,b=0,a=0;
    if (!background || ![background getRed:&r green:&g blue:&b alpha:&a]) return nil;
    int ink=CPStatusInk(r,g,b,a);
    if (ink<0) return nil;
    return @(ink ? UIStatusBarStyleLightContent : UIStatusBarStyleDarkContent);
}
static void TrackStatusController(UIViewController *controller) {
    if (!controller) return;
    static NSMutableSet *installed;
    if (!installed) installed=[NSMutableSet set];
    Class cls=controller.class; NSString *name=NSStringFromClass(cls);
    if ([installed containsObject:name]) return;
    SEL sel=@selector(preferredStatusBarStyle);
    Method m=class_getInstanceMethod(cls,sel); char result[16]={};
    if (m) method_getReturnType(m,result,sizeof(result));
    if (!m || method_getNumberOfArguments(m)!=2 || (result[0]!='q' && result[0]!='Q')) return;
    [installed addObject:name]; __block IMP original=NULL;
    IMP hook=imp_implementationWithBlock(^NSInteger(UIViewController *live) {
        NSInteger source=((NSInteger (*)(id,SEL))original)(live,sel);
        NSNumber *style=NSThread.isMainThread ? StatusStyle(live) : nil;
        return style ? style.integerValue : source;
    });
    MSHookMessageEx(cls,sel,hook,&original);
}
static void UpdateStatusContrast(UINavigationBar *bar) {
    UINavigationController *nav=NavigationController(bar);
    if (!nav) return;
    TrackStatusController(nav);
    UIViewController *child=nav.topViewController;
    for (NSUInteger depth=0;child && depth<8;++depth) {
        TrackStatusController(child);
        UIViewController *next=child.childViewControllerForStatusBarStyle;
        if (next==child) break;
        child=next;
    }
    // The style getter is read-only. Request an update only after a real change.
    static char styleKey, controllerKey;
    NSNumber *style=StatusStyle(nav) ?: @(-1);
    NSValue *identity=[NSValue valueWithNonretainedObject:nav.topViewController];
    if (![objc_getAssociatedObject(bar,&styleKey) isEqual:style] ||
        ![objc_getAssociatedObject(bar,&controllerKey) isEqual:identity]) {
        objc_setAssociatedObject(bar,&styleKey,style,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(bar,&controllerKey,identity,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [nav setNeedsStatusBarAppearanceUpdate]; [nav.topViewController setNeedsStatusBarAppearanceUpdate];
    }
}
static UIColor *ItemsColor(NSString *group, NSString *role, UIView *view) {
    return CPColor(@"accent",@"color",view) ?: CPColor(group,role,view);
}

static NSMutableDictionary *TextAttributes(NSDictionary *source, UIColor *color) {
    NSMutableDictionary *out=source ? [source mutableCopy] : [NSMutableDictionary dictionary];
    if (color) out[NSForegroundColorAttributeName]=color;
    return out;
}
static UINavigationBarAppearance *NavigationAppearance(UINavigationBarAppearance *source, UINavigationBar *bar) {
    UIColor *bg=CPColor(@"navigation",@"background",bar);
    // nil scroll-edge appearances are UIKit's automatic transparent fallback.
    // Coloring only buttons/titles must not turn a banner's status background white.
    if (!source && !bg) return nil;
    UINavigationBarAppearance *a=[source copy] ?: [bar.standardAppearance copy];
    if (bg) { a.backgroundColor=bg; a.backgroundEffect=nil; a.backgroundImage=nil; }
    UIColor *title=CPColor(@"navigation",@"title",bar), *large=CPColor(@"navigation",@"largeTitle",bar);
    if (title) a.titleTextAttributes=TextAttributes(a.titleTextAttributes,title);
    if (large) a.largeTitleTextAttributes=TextAttributes(a.largeTitleTextAttributes,large);
    UIColor *items=ItemsColor(@"navigation",@"items",bar);
    if (items) for (UIBarButtonItemAppearance *button in @[a.buttonAppearance,a.doneButtonAppearance,a.backButtonAppearance]) {
        button.normal.titleTextAttributes=TextAttributes(button.normal.titleTextAttributes,items);
        button.highlighted.titleTextAttributes=TextAttributes(button.highlighted.titleTextAttributes,[items colorWithAlphaComponent:0.65]);
    }
    return a;
}
static void Navigation(UINavigationBar *bar) {
    CPApplyColor(bar,@"tintColor",ItemsColor(@"navigation",@"items",bar));
    BOOL active=CPColor(@"navigation",@"background",bar) || CPColor(@"navigation",@"title",bar) || CPColor(@"navigation",@"largeTitle",bar) || ItemsColor(@"navigation",@"items",bar);
    for (NSString *p in @[@"standardAppearance",@"scrollEdgeAppearance",@"compactAppearance",@"compactScrollEdgeAppearance"])
        CPTransform(bar,p,active,^id(id source) { return NavigationAppearance(source,bar); });
    // Item appearances have precedence over the bar's appearance on iOS 15+.
    for (UINavigationItem *item in bar.items) {
        for (UIBarButtonItem *button in item.leftBarButtonItems) CPApplyColor(button,@"tintColor",ItemsColor(@"navigation",@"items",bar));
        for (UIBarButtonItem *button in item.rightBarButtonItems) CPApplyColor(button,@"tintColor",ItemsColor(@"navigation",@"items",bar));
        for (NSString *p in @[@"standardAppearance",@"scrollEdgeAppearance",@"compactAppearance",@"compactScrollEdgeAppearance"])
            CPTransform(item,p,active,^id(id source) { return NavigationAppearance(source,bar); });
    }
    UpdateStatusContrast(bar);
}
static void Toolbar(UIToolbar *bar) {
    UIColor *items=ItemsColor(@"toolbar",@"items",bar), *bg=CPColor(@"toolbar",@"background",bar);
    // Sileo uses an empty toolbar as the blur behind its date section headers.
    // It is a list material, not a toolbar the user can operate.
    for (UIView *parent=bar.superview;parent;parent=parent.superview)
        if ([NSStringFromClass(parent.class) isEqual:@"Sileo.PackageListHeader"]) { bg=nil; break; }
    CPApplyColor(bar,@"tintColor",items);
    for (UIBarButtonItem *item in bar.items) CPApplyColor(item,@"tintColor",items);
    for (NSString *p in @[@"standardAppearance",@"scrollEdgeAppearance",@"compactAppearance",@"compactScrollEdgeAppearance"])
        CPTransform(bar,p,items || bg,^id(id source) {
            if (!source && !bg) return nil;
            UIToolbarAppearance *a=[source copy] ?: [bar.standardAppearance copy];
            if (bg) { a.backgroundColor=bg; a.backgroundEffect=nil; a.backgroundImage=nil; }
            if (items) for (UIBarButtonItemAppearance *button in @[a.buttonAppearance,a.doneButtonAppearance])
                button.normal.titleTextAttributes=TextAttributes(button.normal.titleTextAttributes,items);
            return a;
        });
}
static UITabBarAppearance *TabAppearance(UITabBarAppearance *source, UITabBar *bar) {
    UIColor *bg=CPColor(@"tabbar",@"background",bar), *selected=ItemsColor(@"tabbar",@"selected",bar), *normal=CPColor(@"tabbar",@"normal",bar);
    if (!source && !bg) return nil;
    UITabBarAppearance *a=[source copy] ?: [bar.standardAppearance copy];
    if (bg) { a.backgroundColor=bg; a.backgroundImage=nil; a.backgroundEffect=nil; }
    for (UITabBarItemAppearance *i in @[a.stackedLayoutAppearance,a.inlineLayoutAppearance,a.compactInlineLayoutAppearance]) {
        if (selected) { i.selected.iconColor=selected; i.selected.titleTextAttributes=TextAttributes(i.selected.titleTextAttributes,selected); }
        if (normal) { i.normal.iconColor=normal; i.normal.titleTextAttributes=TextAttributes(i.normal.titleTextAttributes,normal); }
    }
    return a;
}
static void Tabbar(UITabBar *bar) {
    CPApplyColor(bar,@"tintColor",ItemsColor(@"tabbar",@"selected",bar));
    CPApplyColor(bar,@"unselectedItemTintColor",CPColor(@"tabbar",@"normal",bar));
    BOOL active=CPColor(@"tabbar",@"background",bar) || ItemsColor(@"tabbar",@"selected",bar) || CPColor(@"tabbar",@"normal",bar);
    for (NSString *p in @[@"standardAppearance",@"scrollEdgeAppearance"]) {
        CPTransform(bar,p,active,^id(id source) { return TabAppearance(source,bar); });
        for (UITabBarItem *item in bar.items)
            CPTransform(item,p,active,^id(id source) { return TabAppearance(source,bar); });
    }
}
void CPInstallComponents(void) {
    for (NSString *selector in @[@"_buttonTintColorForState:",@"_contentTintColorForState:",@"iconColorForState:",@"defaultColorForState:"])
        CPRegisterTabColorGetter(selector);
    CPRegisterColorGetter(@"UISwitchModernVisualElement",@"_effectiveOnTintColor",@"switch",@"on");
    CPRegisterColorGetter(@"UISwitchModernVisualElement",@"_effectiveTintColor",@"switch",@"off");
    CPInstallAccent();
    CPTrackProperties(@"UINavigationItem",@[@"standardAppearance",@"scrollEdgeAppearance",@"compactAppearance",@"compactScrollEdgeAppearance"]);
    CPTrackProperties(@"UITabBarItem",@[@"standardAppearance",@"scrollEdgeAppearance"]);
    CPTrackProperties(@"UIBarButtonItem",@[@"tintColor"]);
    CPRegisterView(@"UINavigationBar",@[@"tintColor",@"standardAppearance",@"scrollEdgeAppearance",@"compactAppearance",@"compactScrollEdgeAppearance"],^(UIView *v) { Navigation((UINavigationBar *)v); });
    CPRegisterView(@"UIToolbar",@[@"tintColor",@"standardAppearance",@"scrollEdgeAppearance",@"compactAppearance",@"compactScrollEdgeAppearance"],^(UIView *v) { Toolbar((UIToolbar *)v); });
    CPRegisterView(@"UITabBar",@[@"tintColor",@"unselectedItemTintColor",@"standardAppearance",@"scrollEdgeAppearance"],^(UIView *v) { Tabbar((UITabBar *)v); });
    if ([NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.MobileSMS"])
        CPRegisterView(@"CKNavigationBar",@[@"tintColor",@"standardAppearance",@"scrollEdgeAppearance"],^(UIView *v) { Navigation((UINavigationBar *)v); });
    CPRegisterView(@"UISwitch",@[@"onTintColor",@"tintColor",@"backgroundColor"],^(UIView *v) {
        CPApplyColor(v,@"onTintColor",CPColor(@"switch",@"on",v));
        CPApplyColor(v,@"tintColor",CPColor(@"switch",@"off",v));
        // A separate rounded underlay is used below, so the switch's clipping and layer are untouched.
        static char offLayerKey;
        UIView *underlay=objc_getAssociatedObject(v,&offLayerKey);
        UIColor *off=CPColor(@"switch",@"off",v);
        if (off && !underlay) {
            underlay=[[UIView alloc] init]; underlay.userInteractionEnabled=NO;
            underlay.accessibilityElementsHidden=YES;
            objc_setAssociatedObject(v,&offLayerKey,underlay,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [v insertSubview:underlay atIndex:0];
        }
        if (underlay) {
            if (!CGRectEqualToRect(underlay.frame,v.bounds)) underlay.frame=v.bounds;
            CGFloat radius=CGRectGetHeight(v.bounds)/2;
            if (underlay.layer.cornerRadius!=radius) underlay.layer.cornerRadius=radius;
            if (![underlay.backgroundColor isEqual:off]) underlay.backgroundColor=off;
            BOOL hidden=!off || ((UISwitch *)v).on;
            if (underlay.hidden!=hidden) underlay.hidden=hidden;
        }
    });
    CPRegisterView(@"UISlider",@[@"minimumTrackTintColor",@"maximumTrackTintColor",@"thumbTintColor"],^(UIView *v) {
        CPApplyColor(v,@"minimumTrackTintColor",CPColor(@"slider",@"minimum",v));
        CPApplyColor(v,@"maximumTrackTintColor",CPColor(@"slider",@"maximum",v));
        CPApplyColor(v,@"thumbTintColor",CPColor(@"slider",@"thumb",v));
    });
    CPRegisterView(@"UIProgressView",@[@"progressTintColor",@"trackTintColor"],^(UIView *v) {
        CPApplyColor(v,@"progressTintColor",ItemsColor(@"progress",@"fill",v));
        CPApplyColor(v,@"trackTintColor",CPColor(@"progress",@"track",v));
    });
}
