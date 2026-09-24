#import "Runtime.h"
#import <os/log.h>
#import "PropertyUpdate.h"

static NSDictionary *configuration;
static NSUInteger revision;
static BOOL isSystem;
static NSHashTable<UIView *> *targets;
static NSHashTable<UIView *> *queuedViews;
static NSMutableDictionary<NSString *, CPViewAction> *actions;
static NSMutableSet<NSString *> *registered;
static NSMutableSet<NSString *> *trackedSetters;
static char recordsKey;
static thread_local unsigned int applying;
static thread_local unsigned int layingOut;
static thread_local NSInteger activeStyle;
static BOOL reconciling;
static void QueueApply(UIView *view);

static NSString *Setter(NSString *property) {
    return [NSString stringWithFormat:@"set%@%@:", [[property substringToIndex:1] uppercaseString], [property substringFromIndex:1]];
}
static BOOL TypeStarts(Method method, BOOL result, unsigned index, char wanted) {
    if (!method) return NO;
    char buffer[128] = {};
    if (result) method_getReturnType(method, buffer, sizeof(buffer));
    else method_getArgumentType(method, index, buffer, sizeof(buffer));
    const char *p = buffer;
    while (*p && strchr("rnNoORV", *p)) ++p;
    return *p == wanted;
}
BOOL CPObjectMethod(Class cls, SEL selector, unsigned int arguments) {
    Method m = class_getInstanceMethod(cls, selector);
    if (!m || method_getNumberOfArguments(m) != arguments + 2 || !TypeStarts(m, YES, 0, '@')) return NO;
    for (unsigned i = 2; i < arguments + 2; ++i) if (!TypeStarts(m, NO, i, '@')) return NO;
    return YES;
}
BOOL CPVoidObjectMethod(Class cls, SEL selector) {
    Method m = class_getInstanceMethod(cls, selector);
    return m && method_getNumberOfArguments(m) == 3 && TypeStarts(m, YES, 0, 'v') && TypeStarts(m, NO, 2, '@');
}
id CPGetObject(id object, NSString *property) {
    SEL sel = NSSelectorFromString(property);
    if (!object || !CPObjectMethod(object_getClass(object), sel, 0)) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, sel);
}
id CPGetIvar(id object, const char *name) {
    if (!object) return nil;
    Ivar ivar = class_getInstanceVariable(object_getClass(object), name);
    if (!ivar || ivar_getTypeEncoding(ivar)[0] != '@') return nil;
    return object_getIvar(object, ivar);
}
static NSMutableDictionary *Records(id object, BOOL create) {
    NSMutableDictionary *r = objc_getAssociatedObject(object, &recordsKey);
    if (!r && create) { r = [NSMutableDictionary dictionary]; objc_setAssociatedObject(object, &recordsKey, r, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    return r;
}
void CPTransform(id object, NSString *property, BOOL enabled, id (^transform)(id source)) {
    if (!object || !NSThread.isMainThread) return;
    SEL get = NSSelectorFromString(property), set = NSSelectorFromString(Setter(property));
    if (!CPObjectMethod(object_getClass(object), get, 0) || !CPVoidObjectMethod(object_getClass(object), set)) return;
    NSMutableDictionary *records = Records(object, enabled);
    if (!records) return;
    // Reconcile non-view objects too (navigation/tab items may override their bars).
    // This marks one transform dirty without resetting its conflict budget.
    if (reconciling) CPInvalidatePropertyRecord(records[property]);
    BOOL blocked = CPUpdateProperty(records, property, enabled, revision, activeStyle, CACurrentMediaTime(),
      ^id { return CPGetObject(object, property); }, ^(id desired) {
        ++applying;
        @try { ((void (*)(id, SEL, id))objc_msgSend)(object, set, desired); }
        @finally { --applying; }
      }, transform);
    if (blocked) os_log(OS_LOG_DEFAULT,"[ChromaPalette] paused repeated updates: %{public}@.%{public}@",NSStringFromClass([object class]),property);
}
void CPApplyColor(id object, NSString *property, UIColor *color) {
    if (!object || !NSThread.isMainThread) return;
    // UIKit can reassign a concrete color during layout. Its value is comparable;
    // unlike appearance copies this cannot invalidate merely due to a new identity.
    CPPropertyConcreteInput(Records(object,NO)[property], CPGetObject(object,property), color);
    CPTransform(object, property, color != nil, ^id(id source) { return color; });
}
id CPSourceValue(id object, NSString *property) {
    id current=CPGetObject(object,property);
    NSMutableDictionary *record=Records(object,NO)[property];
    CPPropertySourceChanged(record,current);
    return record ? CPUnboxValue(record[@"source"]) : current;
}
void CPApplyImageColor(UIImageView *view, UIColor *color) {
    if (![view isKindOfClass:UIImageView.class] || !NSThread.isMainThread) return;
    CPPropertyConcreteInput(Records(view,NO)[@"image"], view.image, color);
    CPTransform(view,@"image",color != nil,^id(id source) {
        return [source isKindOfClass:UIImage.class] ? [source imageWithTintColor:color renderingMode:UIImageRenderingModeAlwaysOriginal] : source;
    });
}
void CPTransformValue(id object, NSString *property, BOOL enabled, id context, id (^transform)(id)) {
    if (!object || !NSThread.isMainThread) return;
    CPPropertyConcreteInput(Records(object,NO)[property],CPGetObject(object,property),context);
    CPTransform(object,property,enabled,transform);
}
void CPApplySymbolColor(UIImageView *view, UIColor *color) {
    if (![view isKindOfClass:UIImageView.class] || !NSThread.isMainThread) return;
    // Reuse can replace a symbol with a photo; release the old transform without tinting it.
    CPPropertySourceChanged(Records(view,NO)[@"image"],view.image);
    id original=CPUnboxValue(Records(view,NO)[@"image"][@"source"]);
    if (view.image.isSymbolImage || ([original isKindOfClass:UIImage.class] && [original isSymbolImage]))
        CPApplyImageColor(view,color);
    else CPApplyImageColor(view,nil);
}
// Read-side overrides do not write properties or request layout. Unsupported ABI is skipped.
void CPRegisterColorGetter(NSString *className, NSString *selector, NSString *group, NSString *role) {
    Class cls=NSClassFromString(className); SEL sel=NSSelectorFromString(selector);
    NSString *key=[NSString stringWithFormat:@"getter:%@.%@",className,selector];
    if ([trackedSetters containsObject:key]) return;
    if (!CPObjectMethod(cls,sel,0)) { CPRecordCapability(key,NO); return; }
    [trackedSetters addObject:key];
    __block IMP original=NULL;
    IMP hook=imp_implementationWithBlock(^id(id object) {
        id source=((id (*)(id,SEL))original)(object,sel);
        if (!NSThread.isMainThread) return source;
        UIView *view=[object isKindOfClass:UIView.class] ? object : nil;
        return CPColor(group,role,view) ?: source;
    });
    MSHookMessageEx(cls,sel,hook,&original); CPRecordCapability(key,YES);
}
void CPRegisterTabColorGetter(NSString *selector) {
    CPRegisterStateColorGetter(@"UITabBarButton",selector,@"tabbar",@"normal",@"selected");
}
void CPRegisterStateColorGetter(NSString *className, NSString *selector, NSString *group, NSString *normal, NSString *selected) {
    Class cls=NSClassFromString(className); SEL sel=NSSelectorFromString(selector);
    NSString *key=[NSString stringWithFormat:@"state:%@.%@",className,selector];
    if ([trackedSetters containsObject:key]) return;
    Method m=class_getInstanceMethod(cls,sel);
    if (!m || method_getNumberOfArguments(m)!=3 || !TypeStarts(m,YES,0,'@') ||
        !(TypeStarts(m,NO,2,'Q') || TypeStarts(m,NO,2,'q'))) { CPRecordCapability(key,NO); return; }
    [trackedSetters addObject:key]; __block IMP original=NULL;
    IMP hook=imp_implementationWithBlock(^id(UIView *view,NSUInteger state) {
        id source=((id (*)(id,SEL,NSUInteger))original)(view,sel,state);
        if (!NSThread.isMainThread || (state & UIControlStateDisabled)) return source;
        if ([className isEqual:@"UITabBarButton"] && (state & UIControlStateSelected) &&
            [NSBundle.mainBundle.bundleIdentifier.lowercaseString hasPrefix:@"com.tigisoftware.filza"]) {
            UIColor *filza=CPColor(@"filza",@"accent",view);
            if (filza) return filza;
        }
        return CPColor(group,(state & UIControlStateSelected) ? selected : normal,view) ?: source;
    });
    MSHookMessageEx(cls,sel,hook,&original); CPRecordCapability(key,YES);
}
BOOL CPIsSettingsView(UIView *view) {
    UIResponder *r = view;
    for (unsigned i=0; r && i<100; i++, r=r.nextResponder)
        if ([NSStringFromClass(r.class) hasPrefix:@"CPPrefs"]) return YES;
    // UINavigationBar is a sibling of the visible preference controller.
    for (UIView *p=view; p; p=p.superview) {
        UIResponder *next=p.nextResponder;
        if ([next isKindOfClass:UINavigationController.class]) {
            UIViewController *top=((UINavigationController *)next).topViewController;
            if ([NSStringFromClass(top.class) hasPrefix:@"CPPrefs"]) return YES;
        }
    }
    return NO;
}
BOOL CPGroupEnabled(NSString *group, UIView *view) {
    if (![configuration[@"enabled"] boolValue] || ![configuration[@"groups"][group] boolValue]) return NO;
    NSString *bundle=NSBundle.mainBundle.bundleIdentifier ?: @"";
    if ([configuration[@"excludedApps"] containsObject:bundle]) return NO;
    if ((isSystem || [group isEqual:@"status"] || [group isEqual:@"controlcenter"]) && ![configuration[@"systemEnabled"] boolValue]) return NO;
    if (view && ![group isEqual:@"switch"] && CPIsSettingsView(view)) return NO;
    return YES;
}
UIColor *CPColor(NSString *group, NSString *role, UIView *view) {
    if (!CPGroupEnabled(group, view)) return nil;
    NSDictionary *r=configuration[@"roles"][[NSString stringWithFormat:@"%@.%@",group,role]];
    if (![r[@"enabled"] boolValue]) return nil;
    UITraitCollection *traits=view ? view.traitCollection : UITraitCollection.currentTraitCollection;
    // CC modules can force dark local traits even while the phone is in light mode.
    // Select the user's system palette, rather than that module's material style.
    NSInteger style=traits.userInterfaceStyle;
    if ([group isEqual:@"controlcenter"]) {
        NSInteger screenStyle=UIScreen.mainScreen.traitCollection.userInterfaceStyle;
        if (screenStyle!=UIUserInterfaceStyleUnspecified) style=screenStyle;
    }
    return CPParseHex(r[style == UIUserInterfaceStyleDark ? @"dark" : @"light"]);
}
void CPRecordCapability(NSString *name, BOOL supported) {
    static NSMutableDictionary *last;
    if (!last) last=[NSMutableDictionary dictionary];
    if (last[name] && [last[name] boolValue] == supported) return;
    last[name]=@(supported);
    os_log(OS_LOG_DEFAULT, "[ChromaPalette] %{public}@ : %{public}s", name, supported ? "installed" : "unavailable/skipped");
}
static void Apply(UIView *view, CPViewAction action) {
    if (!NSThread.isMainThread) return;
    [targets addObject:view];
    if (applying) return;
    NSInteger previousStyle=activeStyle;
    activeStyle=view.traitCollection.userInterfaceStyle;
    ++applying;
    @try { action(view); }
    @finally { --applying; activeStyle=previousStyle; }
}
static CPViewAction ActionForView(UIView *view) {
    for (Class cls=view.class; cls; cls=class_getSuperclass(cls)) {
        CPViewAction action=actions[NSStringFromClass(cls)];
        if (action) return action;
    }
    return nil;
}
static void QueueApply(UIView *view) {
    if (!NSThread.isMainThread || applying || !view || [queuedViews containsObject:view]) return;
    [queuedViews addObject:view];
    __weak UIView *weakView=view;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *live=weakView;
        if (!live) return;
        [queuedViews removeObject:live];
        CPViewAction action=ActionForView(live);
        if (action) Apply(live,action);
    });
}
void CPRegisterViewEvent(NSString *className, NSString *selector) {
    Class cls=NSClassFromString(className); SEL sel=NSSelectorFromString(selector);
    NSString *key=[NSString stringWithFormat:@"event:%@.%@",className,selector];
    if ([trackedSetters containsObject:key]) return;
    Method method=class_getInstanceMethod(cls,sel);
    if (!cls || ![cls isSubclassOfClass:UIView.class] || !method || method_getNumberOfArguments(method)!=2 || !TypeStarts(method,YES,0,'v')) return;
    [trackedSetters addObject:key]; __block IMP original=NULL;
    IMP hook=imp_implementationWithBlock(^(UIView *view) {
        ((void (*)(id,SEL))original)(view,sel);
        QueueApply(view);
    });
    MSHookMessageEx(cls,sel,hook,&original);
}
static void TrackSetter(Class cls, NSString *property) {
    NSString *key=[NSString stringWithFormat:@"%@.%@",NSStringFromClass(cls),property];
    if ([trackedSetters containsObject:key]) return;
    SEL sel=NSSelectorFromString(Setter(property));
    if (!CPVoidObjectMethod(cls,sel)) return;
    [trackedSetters addObject:key];
    __block IMP original=NULL;
    IMP hook=imp_implementationWithBlock(^(id object,id value) {
        if (!applying && !layingOut && NSThread.isMainThread)
            CPPropertySourceChanged(Records(object,NO)[property], value);
        ((void (*)(id,SEL,id))original)(object,sel,value);
        // UIKit's own setter owns layout invalidation; do not request another pass.
        // Text/configuration can update after the final layout (async Photos cells).
        // Coalesce a property reconciliation, never call setNeedsLayout here.
        if (!applying && !layingOut && NSThread.isMainThread && [object isKindOfClass:UIView.class])
            QueueApply(object);
    });
    MSHookMessageEx(cls,sel,hook,&original);
}
void CPTrackProperties(NSString *className, NSArray<NSString *> *properties) {
    Class cls=NSClassFromString(className);
    if (cls) for (NSString *property in properties) TrackSetter(cls,property);
}
void CPRegisterView(NSString *className, NSArray<NSString *> *properties, CPViewAction action) {
    if ([registered containsObject:className]) return;
    Class cls=NSClassFromString(className);
    if (!cls || ![cls isSubclassOfClass:UIView.class]) { CPRecordCapability(className,NO); return; }
    SEL sel=@selector(layoutSubviews);
    Method method=class_getInstanceMethod(cls,sel);
    if (!method || method_getNumberOfArguments(method)!=2 || !TypeStarts(method,YES,0,'v')) return;
    [registered addObject:className]; actions[className]=[action copy];
    for (NSString *property in properties) TrackSetter(cls,property);
    __block IMP original=NULL;
    IMP hook=imp_implementationWithBlock(^(UIView *view) {
        ++layingOut;
        @try { ((void (*)(id,SEL))original)(view,sel); }
        @finally { --layingOut; }
        Apply(view,action);
    });
    MSHookMessageEx(cls,sel,hook,&original);
    CPRegisterViewEvent(className,@"didMoveToWindow");
    // Invalidate cached transformations when the local appearance changes.
    SEL trait=@selector(traitCollectionDidChange:);
    if (CPVoidObjectMethod(cls,trait)) {
        __block IMP oldTrait=NULL;
        IMP newTrait=imp_implementationWithBlock(^(UIView *view,UITraitCollection *previous) {
            ((void (*)(id,SEL,id))oldTrait)(view,trait,previous);
            // A forced-dark CC view may receive changed environment traits while
            // its own userInterfaceStyle stays dark. Reconcile without a layout loop.
            QueueApply(view);
        });
        MSHookMessageEx(cls,trait,newTrait,&oldTrait);
    }
    CPRecordCapability(className,YES);
}
static NSMutableArray<UIView *> *reconcileViews;
static NSUInteger reconcileVisited;
static void ReconcileBatch(void) {
    for (NSUInteger n=0; reconcileViews.count && n<128 && reconcileVisited<8192; ++n,++reconcileVisited) {
        UIView *view=reconcileViews.lastObject; [reconcileViews removeLastObject];
        [reconcileViews addObjectsFromArray:view.subviews];
        CPViewAction action=ActionForView(view);
        if (action) {
            BOOL previous=reconciling; reconciling=YES;
            @try { Apply(view,action); }
            @finally { reconciling=previous; }
        }
    }
    if (reconcileViews.count && reconcileVisited<8192) dispatch_async(dispatch_get_main_queue(), ^{ ReconcileBatch(); });
    else reconcileViews=nil;
}
static void ReconcileWindows(void) {
    if (reconcileViews) return;
    reconcileViews=[NSMutableArray array]; reconcileVisited=0;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if ([scene isKindOfClass:UIWindowScene.class]) [reconcileViews addObjectsFromArray:((UIWindowScene *)scene).windows];
    // Older jailbreak apps may not adopt scenes. Query their legacy window list
    // through the checked runtime accessor instead of a deprecated SDK declaration.
    if (!reconcileViews.count) {
        id legacy=CPGetObject(UIApplication.sharedApplication,@"windows");
        if ([legacy isKindOfClass:NSArray.class])
            for (id window in legacy) if ([window isKindOfClass:UIWindow.class]) [reconcileViews addObject:window];
    }
    // Iterative, bounded, and split across main-queue turns. No perpetual timer.
    dispatch_async(dispatch_get_main_queue(), ^{ ReconcileBatch(); });
}
static void Refresh(void) {
    configuration=CPReadConfiguration(); ++revision;
    for (UIView *view in targets.allObjects) {
        CPViewAction action=ActionForView(view);
        if (action) Apply(view,action);
    }
    ReconcileWindows();
}
static void Changed(CFNotificationCenterRef center,void *observer,CFStringRef name,const void *object,CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{ Refresh(); });
}
void CPStart(BOOL systemProcess, dispatch_block_t install) {
    NSCAssert(NSThread.isMainThread, @"Initialize on main thread");
    isSystem=systemProcess; targets=[NSHashTable weakObjectsHashTable]; queuedViews=[NSHashTable weakObjectsHashTable];
    actions=[NSMutableDictionary dictionary]; registered=[NSMutableSet set]; trackedSetters=[NSMutableSet set];
    configuration=CPReadConfiguration(); revision=1;
    install();
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),NULL,Changed,(__bridge CFStringRef)CPNotification,NULL,CFNotificationSuspensionBehaviorDeliverImmediately);
    // Never synchronously wait for the main queue from a framework loader callback.
    __block BOOL installPending=NO;
    dispatch_block_t scheduleInstall=^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (installPending) return;
            installPending=YES;
            dispatch_async(dispatch_get_main_queue(), ^{ installPending=NO; install(); ReconcileWindows(); });
        });
    };
    for (NSString *name in @[NSBundleDidLoadNotification])
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) { scheduleInstall(); }];
    __block NSUInteger activation=0;
    dispatch_block_t mounted=^{
        NSUInteger generation=++activation;
        install(); Refresh();
        // Catch windows created after injection and late appearance setup at launch.
        for (NSNumber *delay in @[@0.35,@1.2]) dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay.doubleValue*NSEC_PER_SEC)),dispatch_get_main_queue(), ^{
            if (generation==activation) ReconcileWindows();
        });
    };
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { mounted(); }];
    [NSNotificationCenter.defaultCenter addObserverForName:UIWindowDidBecomeVisibleNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { ReconcileWindows(); }];
    mounted();
    os_log(OS_LOG_DEFAULT,"[ChromaPalette] initialized in %{public}@; libSandy=%d",NSBundle.mainBundle.bundleIdentifier,CPPreparePreferences());
}
