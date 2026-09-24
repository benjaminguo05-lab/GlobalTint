#import "Runtime.h"
#import <os/log.h>

static NSDictionary *configuration;
static NSUInteger revision;
static BOOL isSystem;
static NSHashTable<UIView *> *targets;
static NSMutableDictionary<NSString *, CPViewAction> *actions;
static NSMutableSet<NSString *> *registered;
static char recordsKey;
static thread_local unsigned int applying;
static thread_local unsigned int layingOut;

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
static BOOL Same(id a, id b) { return a == b || (a && b && [a isEqual:b]); }
static id Box(id object) { return object ?: NSNull.null; }
static id Unbox(id object) { return object == NSNull.null ? nil : object; }
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
    NSMutableDictionary *record = records[property];
    if (!enabled && !record) return;
    id current = CPGetObject(object, property);
    if (!record) { record = [@{@"source":Box(current)} mutableCopy]; records[property] = record; }
    else if (!Same(current, Unbox(record[@"output"]))) record[@"source"] = Box(current);
    if (enabled && [record[@"revision"] unsignedIntegerValue] == revision && Same(current, Unbox(record[@"output"]))) return;
    id desired = enabled ? transform(Unbox(record[@"source"])) : Unbox(record[@"source"]);
    record[@"output"] = Box(desired);
    record[@"revision"] = @(revision);
    if (!Same(current, desired)) {
        ++applying;
        @try { ((void (*)(id, SEL, id))objc_msgSend)(object, set, desired); }
        @finally { --applying; }
    }
    if (!enabled) [records removeObjectForKey:property];
}
void CPApplyColor(id object, NSString *property, UIColor *color) {
    CPTransform(object, property, color != nil, ^id(id source) { return color; });
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
    if (view && CPIsSettingsView(view)) return NO;
    return YES;
}
UIColor *CPColor(NSString *group, NSString *role, UIView *view) {
    if (!CPGroupEnabled(group, view)) return nil;
    NSDictionary *r=configuration[@"roles"][[NSString stringWithFormat:@"%@.%@",group,role]];
    if (![r[@"enabled"] boolValue]) return nil;
    UITraitCollection *traits=view ? view.traitCollection : UITraitCollection.currentTraitCollection;
    return CPParseHex(r[traits.userInterfaceStyle == UIUserInterfaceStyleDark ? @"dark" : @"light"]);
}
void CPRecordCapability(NSString *name, BOOL supported) {
    static NSMutableDictionary *last;
    if (!last) last=[NSMutableDictionary dictionary];
    if (last[name] && [last[name] boolValue] == supported) return;
    last[name]=@(supported);
    os_log(OS_LOG_DEFAULT, "[ChromaPalette] %{public}@ : %{public}s", name, supported ? "installed" : "unavailable/skipped");
}
static void Apply(UIView *view, CPViewAction action) {
    if (applying || !NSThread.isMainThread) return;
    [targets addObject:view];
    ++applying;
    @try { action(view); }
    @finally { --applying; }
}
static void TrackSetter(Class cls, NSString *property) {
    SEL sel=NSSelectorFromString(Setter(property));
    if (!CPVoidObjectMethod(cls,sel)) return;
    __block IMP original=NULL;
    IMP hook=imp_implementationWithBlock(^(id object,id value) {
        if (!applying && NSThread.isMainThread) {
            NSMutableDictionary *record=Records(object,NO)[property];
            if (record) {
                record[@"source"]=Box(value);
                [record removeObjectForKey:@"revision"];
            }
        }
        ((void (*)(id,SEL,id))original)(object,sel,value);
        if (!applying && !layingOut && [object isKindOfClass:UIView.class] && NSThread.isMainThread && Records(object,NO)[property]) [(UIView *)object setNeedsLayout];
    });
    MSHookMessageEx(cls,sel,hook,&original);
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
    // Invalidate cached transformations when the local appearance changes.
    SEL trait=@selector(traitCollectionDidChange:);
    if (CPVoidObjectMethod(cls,trait)) {
        __block IMP oldTrait=NULL;
        IMP newTrait=imp_implementationWithBlock(^(UIView *view,UITraitCollection *previous) {
            ((void (*)(id,SEL,id))oldTrait)(view,trait,previous);
            if (NSThread.isMainThread && (!previous || previous.userInterfaceStyle!=view.traitCollection.userInterfaceStyle)) {
                ++revision; [view setNeedsLayout];
            }
        });
        MSHookMessageEx(cls,trait,newTrait,&oldTrait);
    }
    CPRecordCapability(className,YES);
}
static void Refresh(void) {
    configuration=CPReadConfiguration(); ++revision;
    for (UIView *view in targets.allObjects) {
        // Most specific class action; avoid applying parent actions a second time.
        for (Class cls=view.class; cls; cls=class_getSuperclass(cls)) {
            CPViewAction action=actions[NSStringFromClass(cls)];
            if (action) { Apply(view,action); break; }
        }
        [view setNeedsLayout];
    }
}
static void Changed(CFNotificationCenterRef center,void *observer,CFStringRef name,const void *object,CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{ Refresh(); });
}
void CPStart(BOOL systemProcess, dispatch_block_t install) {
    NSCAssert(NSThread.isMainThread, @"Initialize on main thread");
    isSystem=systemProcess; targets=[NSHashTable weakObjectsHashTable];
    actions=[NSMutableDictionary dictionary]; registered=[NSMutableSet set];
    configuration=CPReadConfiguration(); revision=1;
    install();
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),NULL,Changed,(__bridge CFStringRef)CPNotification,NULL,CFNotificationSuspensionBehaviorDeliverImmediately);
    [NSNotificationCenter.defaultCenter addObserverForName:NSBundleDidLoadNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { install(); }];
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { install(); Refresh(); }];
    os_log(OS_LOG_DEFAULT,"[ChromaPalette] initialized in %{public}@; libSandy=%d",NSBundle.mainBundle.bundleIdentifier,CPPreparePreferences());
}
