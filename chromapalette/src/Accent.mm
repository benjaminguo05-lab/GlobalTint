#import "Runtime.h"
#import "AttributedColors.h"
#import "BluePolicy.h"

// Only concrete text/control properties are inspected. Compare named tokens and
// their canonical sRGB blue values across color spaces; never scan image pixels.
static BOOL NativeAccent(UIColor *color, UIView *view) {
    if (![color isKindOfClass:UIColor.class]) return NO;
    UITraitCollection *traits=view ? view.traitCollection : UIScreen.mainScreen.traitCollection;
    UIColor *resolved=[[color resolvedColorWithTraitCollection:traits] colorWithAlphaComponent:1];
    for (UIColor *token in @[UIColor.systemBlueColor,UIColor.linkColor]) {
        if ([color isEqual:token]) return YES;
        for (UITraitCollection *t in @[traits,
                [UITraitCollection traitCollectionWithUserInterfaceStyle:UIUserInterfaceStyleLight],
                [UITraitCollection traitCollectionWithUserInterfaceStyle:UIUserInterfaceStyleDark]])
            if ([resolved isEqual:[[token resolvedColorWithTraitCollection:t] colorWithAlphaComponent:1]]) return YES;
    }
    CGFloat r=0,g=0,b=0,a=0;
    return [resolved getRed:&r green:&g blue:&b alpha:&a] && CPCanonicalBlue(r,g,b);
}
static BOOL InputOrAlert(UIView *view) {
    for (UIResponder *r=view; r; r=r.nextResponder) {
        if ([r isKindOfClass:UITextView.class] || [r isKindOfClass:UITextField.class] ||
            [r isKindOfClass:UIInputView.class] || [r isKindOfClass:UIAlertController.class]) return YES;
    }
    return NO;
}
static UIColor *Accent(UIView *view) {
    if (InputOrAlert(view)) return nil;
    for (UIView *p=view; p; p=p.superview)
        if ([p isKindOfClass:UITabBar.class]) return nil; // Selected/normal appearance owns this.
    return CPColor(@"accent",@"color",view);
}
static UIColor *Mapped(UIColor *source, UIColor *chosen, UIView *view) {
    if (!chosen || [source isEqual:chosen] || !NativeAccent(source,view)) return source;
    CGFloat alpha=CGColorGetAlpha([source resolvedColorWithTraitCollection:(view ? view.traitCollection : UIScreen.mainScreen.traitCollection)].CGColor);
    CGFloat chosenAlpha=CGColorGetAlpha(chosen.CGColor);
    return [chosen colorWithAlphaComponent:alpha*chosenAlpha];
}
static NSAttributedString *Attributed(NSAttributedString *source, UIColor *color, UIView *view) {
    if (!color) return source;
    return CPMapAttributedColors(source,@[NSForegroundColorAttributeName,NSUnderlineColorAttributeName],^id(id value) {
        return Mapped(value,color,view);
    });
}
static void AccentProperty(id object, NSString *property, UIColor *color, UIView *view) {
    if (!object) return;
    static char accentPropertiesKey;
    NSMutableSet *owned=objc_getAssociatedObject(object,&accentPropertiesKey);
    UIColor *source=CPSourceValue(object,property);
    BOOL enabled=color && NativeAccent(source,view);
    // Do not remove a property record owned by the cell/navigation component.
    if (!enabled && ![owned containsObject:property]) return;
    if (!owned) {
        owned=[NSMutableSet set];
        objc_setAssociatedObject(object,&accentPropertiesKey,owned,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (enabled) [owned addObject:property]; else [owned removeObject:property];
    CPApplyColor(object,property,enabled ? Mapped(source,color,view) : nil);
}
static void Label(UILabel *label) {
    UIColor *color=Accent(label);
    AccentProperty(label,@"textColor",color,label);
    CPTransformValue(label,@"attributedText",color!=nil,color,^id(id source) { return Attributed(source,color,label); });
}
static void Button(UIButton *button) {
    UIColor *foreground=button.enabled ? Accent(button) : nil;
    UIColor *fill=button.enabled ? Accent(button) : nil;
    AccentProperty(button,@"tintColor",foreground,button);
    AccentProperty(button,@"backgroundColor",fill,button);
    AccentProperty(button.titleLabel,@"textColor",foreground,button);
    CPTransform(button,@"configuration",foreground || fill,^id(id source) {
        if (![source isKindOfClass:UIButtonConfiguration.class]) return source;
        UIButtonConfiguration *copy=[source copy];
        copy.baseForegroundColor=Mapped(copy.baseForegroundColor,foreground,button);
        copy.baseBackgroundColor=Mapped(copy.baseBackgroundColor,fill,button);
        copy.attributedTitle=Attributed(copy.attributedTitle,foreground,button);
        copy.attributedSubtitle=Attributed(copy.attributedSubtitle,foreground,button);
        // Retain white text on filled buttons, red destructive actions, and host
        // transformers. Only the transformer's returned native accent is mapped.
        UIConfigurationColorTransformer old=copy.imageColorTransformer;
        __weak UIButton *weakButton=button;
        copy.imageColorTransformer=^UIColor *(UIColor *input) {
            UIColor *original=old ? old(input) : input;
            UIButton *live=weakButton;
            return live ? Mapped(original,foreground,live) : original;
        };
        UIBackgroundConfiguration *background=[copy.background copy];
        background.backgroundColor=Mapped(background.backgroundColor,fill,button);
        copy.background=background;
        return copy;
    });
}
// Filza 4.0.1-4 creates sorting arrows via ThemeManager's explicit image-mask
// API with a hard-coded #007AFF. Replace its color argument before rasterization,
// not UIImage/UIColor factories, pixels, or generic drawing callbacks.
static void InstallFilza(void) {
    if (![NSBundle.mainBundle.bundleIdentifier.lowercaseString hasPrefix:@"com.tigisoftware.filza"]) return;
    Class manager=NSClassFromString(@"ThemeManager");
    SEL mask=NSSelectorFromString(@"imageWithName:withMaskColor:");
    if (CPObjectMethod(manager,mask,2)) {
        __block IMP original=NULL;
        IMP hook=imp_implementationWithBlock(^id(id object,id name,id color) {
            UIColor *chosen=NSThread.isMainThread ? CPColor(@"accent",@"color",nil) : nil;
            id desired=Mapped(color,chosen,nil);
            return ((id (*)(id,SEL,id,id))original)(object,mask,name,desired);
        });
        MSHookMessageEx(manager,mask,hook,&original);
        CPRecordCapability(@"Filza.ThemeManager.imageMask",YES);
    } else CPRecordCapability(@"Filza.ThemeManager.imageMask",NO);
    // QuickDialog supplies Filza's settings values (including entry fields).
    // Read-side mapping keeps disabled gray, red warnings and other colors intact.
    NSDictionary *getters=@{@"ThemeManager":@[@"systemColor",@"link"],
        @"QAppearance":@[@"valueColorEnabled",@"entryTextColorEnabled",@"actionColorEnabled"]};
    for (NSString *name in getters) for (NSString *selector in getters[name]) {
        Class cls=NSClassFromString(name); SEL sel=NSSelectorFromString(selector);
        if (!CPObjectMethod(cls,sel,0)) continue;
        __block IMP original=NULL;
        IMP hook=imp_implementationWithBlock(^id(id object) {
            id source=((id (*)(id,SEL))original)(object,sel);
            return NSThread.isMainThread ? Mapped(source,CPColor(@"accent",@"color",nil),nil) : source;
        });
        MSHookMessageEx(cls,sel,hook,&original);
    }
}
// A read-only override covers buttons which resolve per-state title colors after
// their configuration update. It never writes a view property or requests layout.
static void InstallButtonTitleGetter(void) {
    Class cls=UIButton.class; SEL sel=@selector(titleColorForState:);
    Method method=class_getInstanceMethod(cls,sel);
    char result[16]={}, argument[16]={};
    if (method) { method_getReturnType(method,result,sizeof(result)); method_getArgumentType(method,2,argument,sizeof(argument)); }
    if (!method || method_getNumberOfArguments(method)!=3 || result[0]!='@' || (argument[0]!='Q' && argument[0]!='q')) return;
    __block IMP original=NULL;
    IMP hook=imp_implementationWithBlock(^id(UIButton *button,NSUInteger state) {
        id source=((id (*)(id,SEL,NSUInteger))original)(button,sel,state);
        if (!NSThread.isMainThread || !button.enabled || (state & UIControlStateDisabled)) return source;
        return Mapped(source,Accent(button),button);
    });
    MSHookMessageEx(cls,sel,hook,&original);
}
void CPInstallAccent(void) {
    InstallFilza();
    InstallButtonTitleGetter();
    CPRegisterView(@"UIWindow",@[@"tintColor"],^(UIView *v) {
        AccentProperty(v,@"tintColor",Accent(v),v);
    });
    CPRegisterView(@"UILabel",@[@"textColor",@"attributedText"],^(UIView *v) { Label((UILabel *)v); });
    CPRegisterView(@"UIButton",@[@"tintColor",@"backgroundColor",@"configuration"],^(UIView *v) { Button((UIButton *)v); });
    CPRegisterViewEvent(@"UIButton",@"updateConfiguration");
    CPRegisterView(@"UIImageView",@[@"tintColor",@"image"],^(UIView *v) {
        UIImageView *image=(UIImageView *)v;
        UIImage *source=CPSourceValue(image,@"image");
        // Only template images use tint. Keep multicolor symbols and actual artwork.
        if (source.renderingMode==UIImageRenderingModeAlwaysTemplate)
            AccentProperty(image,@"tintColor",Accent(image),image);
        else AccentProperty(image,@"tintColor",nil,image);
        BOOL controlSymbol=source.isSymbolImage && [image.superview isKindOfClass:UIButton.class];
        UIColor *native=CPSourceValue(image,@"tintColor");
        static char symbolOwner;
        UIColor *common=Accent(image);
        UIColor *chosen=controlSymbol && (NativeAccent(native,image) || [native isEqual:common]) ? common : nil;
        if (chosen || [objc_getAssociatedObject(image,&symbolOwner) boolValue]) {
            CPApplySymbolColor(image,chosen);
            objc_setAssociatedObject(image,&symbolOwner,@(chosen!=nil),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    });
    CPRegisterView(@"UITextView",@[@"linkTextAttributes",@"tintColor"],^(UIView *v) {
        UIColor *color=CPColor(@"accent",@"color",v);
        // The same common option owns detected links, including Notes numbers.
        CPApplyColor(v,@"tintColor",color);
        CPTransformValue(v,@"linkTextAttributes",color!=nil,color,^id(id source) {
            NSMutableDictionary *attrs=[source isKindOfClass:NSDictionary.class] ? [source mutableCopy] : [NSMutableDictionary dictionary];
            attrs[NSForegroundColorAttributeName]=color; attrs[NSUnderlineColorAttributeName]=color;
            return attrs;
        });
    });
}
