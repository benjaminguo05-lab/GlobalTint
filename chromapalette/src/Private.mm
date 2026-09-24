#import "Runtime.h"

static void Status(void) {
    CPRegisterView(@"_UIStatusBarStringView",@[@"textColor"],^(UIView *v) {
        CPApplyColor(v,@"textColor",CPColor(@"status",@"text",v));
    });
    for (NSString *name in @[@"_UIStatusBarWifiSignalView",@"_UIStatusBarCellularSignalView"]) {
        NSString *role=[name containsString:@"Wifi"] ? @"wifi" : @"cellular";
        CPRegisterView(name,@[@"activeColor",@"inactiveColor"],^(UIView *v) {
            CPApplyColor(v,@"activeColor",CPColor(@"status",role,v));
            CPApplyColor(v,@"inactiveColor",CPColor(@"status",@"inactive",v));
        });
    }
    CPRegisterView(@"_UIBatteryView",@[@"fillColor",@"bodyColor",@"pinColor"],^(UIView *v) {
        CPApplyColor(v,@"fillColor",CPColor(@"status",@"battery",v));
        CPApplyColor(v,@"bodyColor",CPColor(@"status",@"batteryBody",v));
        CPApplyColor(v,@"pinColor",CPColor(@"status",@"batteryBody",v));
    });
}
static void ControlCenter(void) {
    CPRegisterView(@"CCUIContentModuleBackgroundView",@[],^(UIView *v) {
        static char overlayKey;
        UIView *overlay=objc_getAssociatedObject(v,&overlayKey);
        UIColor *color=CPColor(@"controlcenter",@"background",v);
        if (color && !overlay) {
            overlay=[[UIView alloc] init]; overlay.userInteractionEnabled=NO;
            overlay.accessibilityElementsHidden=YES;
            objc_setAssociatedObject(v,&overlayKey,overlay,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [v addSubview:overlay];
        }
        if (overlay) {
            overlay.frame=v.bounds; overlay.backgroundColor=color;
            overlay.layer.cornerRadius=v.layer.cornerRadius; overlay.hidden=!color;
        }
    });
    CPRegisterView(@"CCUIRoundButton",@[@"highlightColor"],^(UIView *v) {
        CPApplyColor(v,@"highlightColor",CPColor(@"controlcenter",@"active",v));
    });
    CPRegisterView(@"CCUIButtonModuleView",@[@"glyphColor",@"selectedGlyphColor"],^(UIView *v) {
        CPApplyColor(v,@"glyphColor",CPColor(@"controlcenter",@"glyph",v));
        CPApplyColor(v,@"selectedGlyphColor",CPColor(@"controlcenter",@"selectedGlyph",v));
    });
    CPRegisterView(@"CCUIModuleSliderView",@[],^(UIView *v) {
        id fill=CPGetIvar(v,"_continuousValueBackgroundView");
        if ([fill isKindOfClass:UIView.class]) CPApplyColor(fill,@"backgroundColor",CPColor(@"controlcenter",@"slider",v));
    });
    // Newer iOS builds can use this class. No unsafe ivar offsets or KVC assumptions.
    CPRegisterView(@"CCUIContinuousSliderView",@[@"valueColor"],^(UIView *v) {
        CPApplyColor(v,@"valueColor",CPColor(@"controlcenter",@"slider",v));
        id fill=CPGetIvar(v,"_continuousValueBackgroundView");
        if ([fill isKindOfClass:UIView.class]) CPApplyColor(fill,@"backgroundColor",CPColor(@"controlcenter",@"slider",v));
    });
}
static BOOL HasOwnMethod(Class cls, SEL selector) {
    unsigned count=0; Method *list=class_copyMethodList(cls,&count); BOOL found=NO;
    for (unsigned i=0;i<count;++i) if (method_getName(list[i])==selector) { found=YES; break; }
    free(list); return found;
}
static id KeyboardTraits(id source) {
    if (!NSThread.isMainThread || !source) return source;
    UIColor *color=CPColor(@"keyboard",@"keycap",nil);
    if (!color || ![source conformsToProtocol:@protocol(NSCopying)]) return source;
    Class gradientClass=NSClassFromString(@"UIKBColorGradient");
    SEL factory=NSSelectorFromString(@"gradientWithUIColor:");
    if (!CPObjectMethod(object_getClass(gradientClass),factory,1)) return source;
    id copy=[source copy];
    SEL set=NSSelectorFromString(@"setBackgroundGradient:");
    if (!CPVoidObjectMethod(object_getClass(copy),set)) return source;
    id gradient=((id (*)(id,SEL,id))objc_msgSend)(gradientClass,factory,color);
    if (!gradient) return source;
    ((void (*)(id,SEL,id))objc_msgSend)(copy,set,gradient);
    SEL layered=NSSelectorFromString(@"setLayeredBackgroundGradient:");
    if (CPVoidObjectMethod(object_getClass(copy),layered)) ((void (*)(id,SEL,id))objc_msgSend)(copy,layered,gradient);
    // Key images are cached by traits; distinguish our output from original traits.
    SEL hash=NSSelectorFromString(@"setHashString:");
    if (CPVoidObjectMethod(object_getClass(copy),hash)) {
        NSString *original=CPGetObject(source,@"hashString") ?: @"";
        NSString *value=[NSString stringWithFormat:@"%@/ChromaPalette/%@",original,CPHex(color)];
        ((void (*)(id,SEL,id))objc_msgSend)(copy,hash,value);
    }
    return copy;
}
static void Keyboard(void) {
    CPRegisterView(@"UIKeyboardLayoutStar",@[@"backgroundColor"],^(UIView *v) {
        CPApplyColor(v,@"backgroundColor",CPColor(@"keyboard",@"background",v));
    });
    CPRegisterView(@"UIKeyboardDockView",@[@"backgroundColor"],^(UIView *v) {
        CPApplyColor(v,@"backgroundColor",CPColor(@"keyboard",@"dock",v));
    });
    static NSMutableSet *hooked;
    if (!hooked) hooked=[NSMutableSet set];
    Class base=NSClassFromString(@"UIKBRenderFactory");
    if (!base) { CPRecordCapability(@"UIKBRenderFactory",NO); return; }
    unsigned count=0; Class *classes=objc_copyClassList(&count);
    SEL selector=NSSelectorFromString(@"traitsForKey:onKeyplane:");
    for (unsigned i=0;i<count;i++) {
        Class cls=classes[i];
        // Traverse runtime superclasses without sending messages to arbitrary classes.
        BOOL matches=NO;
        for (Class c=cls;c;c=class_getSuperclass(c)) if (c==base) { matches=YES; break; }
        if (!matches || !HasOwnMethod(cls,selector) || !CPObjectMethod(cls,selector,2)) continue;
        NSString *name=NSStringFromClass(cls);
        if ([hooked containsObject:name]) continue;
        [hooked addObject:name];
        __block IMP original=NULL;
        IMP replacement=imp_implementationWithBlock(^id(id object,id key,id plane) {
            id traits=((id (*)(id,SEL,id,id))original)(object,selector,key,plane);
            return KeyboardTraits(traits);
        });
        MSHookMessageEx(cls,selector,replacement,&original);
        CPRecordCapability([name stringByAppendingString:@" keycap"],YES);
    }
    free(classes);
}
void CPInstallPrivate(BOOL systemProcess) {
    Status();
    if (systemProcess) ControlCenter();
    else Keyboard();
}
