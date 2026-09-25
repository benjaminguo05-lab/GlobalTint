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
    static NSMutableSet *installed;
    if (!installed) installed=[NSMutableSet set];
    Class manager=NSClassFromString(@"ThemeManager");
    SEL mask=NSSelectorFromString(@"imageWithName:withMaskColor:");
    if (![installed containsObject:@"imageMask"] && CPObjectMethod(manager,mask,2)) {
        [installed addObject:@"imageMask"];
        __block IMP original=NULL;
        IMP hook=imp_implementationWithBlock(^id(id object,id name,id color) {
            UIColor *chosen=NSThread.isMainThread ? CPColor(@"accent",@"color",nil) : nil;
            id desired=Mapped(color,chosen,nil);
            return ((id (*)(id,SEL,id,id))original)(object,mask,name,desired);
        });
        MSHookMessageEx(manager,mask,hook,&original);
        CPRecordCapability(@"Filza.ThemeManager.imageMask",YES);
    } else if (![installed containsObject:@"imageMask"]) CPRecordCapability(@"Filza.ThemeManager.imageMask",NO);
    // QuickDialog supplies Filza's settings values (including entry fields).
    // Read-side mapping keeps disabled gray, red warnings and other colors intact.
    NSDictionary *getters=@{@"ThemeManager":@[@"systemColor",@"link"],
        @"QAppearance":@[@"valueColorEnabled",@"entryTextColorEnabled",@"actionColorEnabled"]};
    for (NSString *name in getters) for (NSString *selector in getters[name]) {
        Class cls=NSClassFromString(name); SEL sel=NSSelectorFromString(selector);
        NSString *key=[name stringByAppendingString:selector];
        if ([installed containsObject:key] || !CPObjectMethod(cls,sel,0)) continue;
        [installed addObject:key];
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
    static BOOL installed=NO; if (installed) return;
    Class cls=UIButton.class; SEL sel=@selector(titleColorForState:);
    Method method=class_getInstanceMethod(cls,sel);
    char result[16]={}, argument[16]={};
    if (method) { method_getReturnType(method,result,sizeof(result)); method_getArgumentType(method,2,argument,sizeof(argument)); }
    if (!method || method_getNumberOfArguments(method)!=3 || result[0]!='@' || (argument[0]!='Q' && argument[0]!='q')) return;
    installed=YES;
    __block IMP original=NULL;
    IMP hook=imp_implementationWithBlock(^id(UIButton *button,NSUInteger state) {
        id source=((id (*)(id,SEL,NSUInteger))original)(button,sel,state);
        if (!NSThread.isMainThread || !button.enabled || (state & UIControlStateDisabled)) return source;
        return Mapped(source,Accent(button),button);
    });
    MSHookMessageEx(cls,sel,hook,&original);
}
static BOOL PhotosListSymbol(UIImageView *image, UIImage *source) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.mobileslideshow"] || !source.isSymbolImage) return NO;
    if (source.size.width>64 || source.size.height>64) return NO;
    UIView *parent=image.superview;
    for (NSUInteger depth=0; parent && depth<6; ++depth,parent=parent.superview)
        if ([parent isKindOfClass:UITableViewCell.class] || [parent isKindOfClass:UICollectionViewCell.class] ||
            [NSStringFromClass(parent.class) isEqual:@"PUAlbumListCellContentView"]) {
            // Only the leading category glyph, not trailing locks or badges.
            if (parent.bounds.size.width<=0 || image.bounds.size.width>64 || image.bounds.size.height>64) return NO;
            CGRect rect=[image convertRect:image.bounds toView:parent];
            CGFloat fraction=CGRectGetMidX(rect)/parent.bounds.size.width;
            return parent.effectiveUserInterfaceLayoutDirection==UIUserInterfaceLayoutDirectionRightToLeft ? fraction>0.75 : fraction<0.25;
        }
    return NO;
}

static void InstallPhotos(void) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.mobileslideshow"]) return;
    CPRegisterView(@"PUAlbumListCellContentView",@[@"customImageView"],^(UIView *view) {
        id custom=CPGetObject(view,@"customImageView");
        if (![custom isKindOfClass:UIImageView.class]) return;
        UIImageView *image=custom;
        UIImage *source=CPSourceValue(image,@"image");
        // This explicitly exposed category-icon slot is separate from the album
        // photo stack. It can contain a raster glyph rather than an SF Symbol.
        UIColor *color=Accent(image); UIColor *tint=CPSourceValue(image,@"tintColor");
        BOOL small=source && source.size.width<=64 && source.size.height<=64;
        CPApplyImageColor(image,small && (NativeAccent(tint,image) || [tint isEqual:color]) ? color : nil);
    });
}

// UIColor adapters let the existing bounded, restorable property engine handle
// only layers belonging to an App Store offer button. No CALayer hooks installed.
@interface CPOfferLayerColors : NSObject
@property(nonatomic,weak) CALayer *layer;
@property(nonatomic,strong) UIColor *backgroundColor;
@property(nonatomic,strong) UIColor *fillColor;
@property(nonatomic,strong) UIColor *strokeColor;
@end
@implementation CPOfferLayerColors
- (UIColor *)backgroundColor { CGColorRef c=self.layer.backgroundColor; return c ? [UIColor colorWithCGColor:c] : nil; }
- (void)setBackgroundColor:(UIColor *)color { self.layer.backgroundColor=color.CGColor; }
- (UIColor *)fillColor { CGColorRef c=[self.layer isKindOfClass:CAShapeLayer.class] ? ((CAShapeLayer *)self.layer).fillColor : nil; return c ? [UIColor colorWithCGColor:c] : nil; }
- (void)setFillColor:(UIColor *)color { if ([self.layer isKindOfClass:CAShapeLayer.class]) ((CAShapeLayer *)self.layer).fillColor=color.CGColor; }
- (UIColor *)strokeColor { CGColorRef c=[self.layer isKindOfClass:CAShapeLayer.class] ? ((CAShapeLayer *)self.layer).strokeColor : nil; return c ? [UIColor colorWithCGColor:c] : nil; }
- (void)setStrokeColor:(UIColor *)color { if ([self.layer isKindOfClass:CAShapeLayer.class]) ((CAShapeLayer *)self.layer).strokeColor=color.CGColor; }
@end
static void Offer(UIView *view) {
    UIColor *chosen=([view isKindOfClass:UIControl.class] && !((UIControl *)view).enabled) ? nil : Accent(view);
    NSMutableArray *pending=[NSMutableArray arrayWithObject:@[view.layer,@0]];
    static char layerColorsKey;
    for (NSUInteger n=0; pending.count && n<48; ++n) {
        NSArray *item=pending.lastObject; [pending removeLastObject];
        CALayer *layer=item[0]; NSUInteger depth=[item[1] unsignedIntegerValue];
        CPOfferLayerColors *adapter=objc_getAssociatedObject(layer,&layerColorsKey);
        if (!adapter) { adapter=[CPOfferLayerColors new]; adapter.layer=layer; objc_setAssociatedObject(layer,&layerColorsKey,adapter,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        for (NSString *property in @[@"backgroundColor",@"fillColor",@"strokeColor"])
            AccentProperty(adapter,property,chosen,view);
        if (depth<3) for (CALayer *child in layer.sublayers) {
            if (pending.count>=48) break;
            [pending addObject:@[child,@(depth+1)]];
        }
    }
}
static void InstallStore(void) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.AppStore"]) return;
    static NSMutableSet *installed;
    if (!installed) installed=[NSMutableSet set];
    Class theme=NSClassFromString(@"ASCOfferTheme");
    for (NSString *name in @[@"titleBackgroundColor",@"titleTextColor",@"iconTintColor",@"progressColor"]) {
        SEL sel=NSSelectorFromString(name);
        if ([installed containsObject:name] || !CPObjectMethod(theme,sel,0)) continue;
        [installed addObject:name]; __block IMP original=NULL;
        IMP hook=imp_implementationWithBlock(^id(id object) {
            id source=((id (*)(id,SEL))original)(object,sel);
            return NSThread.isMainThread ? Mapped(source,CPColor(@"accent",@"color",nil),nil) : source;
        });
        MSHookMessageEx(theme,sel,hook,&original);
        CPRecordCapability([@"ASCOfferTheme." stringByAppendingString:name],YES);
    }
    // Swift class names vary by app release. Discover only loaded offer-button
    // classes in the AppStore modules and install the checked UIView adapter.
    unsigned count=0; Class *classes=objc_copyClassList(&count);
    for (unsigned i=0;i<count;++i) {
        Class cls=classes[i]; NSString *name=NSStringFromClass(cls);
        BOOL candidate=[name isEqual:@"ASCOfferButton"] ||
            ([name containsString:@"AppStore"] && [name containsString:@"OfferButton"]);
        if (!candidate || ![cls isSubclassOfClass:UIView.class]) continue;
        CPRegisterView(name,@[@"backgroundColor",@"tintColor"],^(UIView *v) { Offer(v); });
    }
    free(classes);
}
void CPInstallAccent(void) {
    InstallFilza();
    InstallStore();
    InstallPhotos();
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
        BOOL controlSymbol=source.isSymbolImage && ([image.superview isKindOfClass:UIButton.class] || PhotosListSymbol(image,source));
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
