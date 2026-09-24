#import "Runtime.h"
#import "AttributedColors.h"

// Match UIKit's named accent tokens only, on text/control properties. No global
// UIColor/CGColor hook, RGB tolerance, pixel replacement, or layer-tree traversal.
static BOOL NativeAccent(UIColor *color, UIView *view) {
    if (![color isKindOfClass:UIColor.class]) return NO;
    UITraitCollection *traits=view.traitCollection;
    UIColor *resolved=[[color resolvedColorWithTraitCollection:traits] colorWithAlphaComponent:1];
    for (UIColor *token in @[UIColor.systemBlueColor,UIColor.linkColor]) {
        if ([color isEqual:token]) return YES;
        for (UITraitCollection *t in @[traits,
                [UITraitCollection traitCollectionWithUserInterfaceStyle:UIUserInterfaceStyleLight],
                [UITraitCollection traitCollectionWithUserInterfaceStyle:UIUserInterfaceStyleDark]])
            if ([resolved isEqual:[[token resolvedColorWithTraitCollection:t] colorWithAlphaComponent:1]]) return YES;
    }
    return NO;
}
static BOOL InputOrAlert(UIView *view) {
    for (UIResponder *r=view; r; r=r.nextResponder) {
        if ([r isKindOfClass:UITextView.class] || [r isKindOfClass:UITextField.class] ||
            [r isKindOfClass:UIInputView.class] || [r isKindOfClass:UIAlertController.class]) return YES;
    }
    return NO;
}
static UIColor *Accent(UIView *view, NSString *role) {
    if (InputOrAlert(view)) return nil;
    NSString *bundle=NSBundle.mainBundle.bundleIdentifier.lowercaseString;
    if ([bundle hasPrefix:@"com.tigisoftware.filza"] && ![role isEqual:@"filled"])
        return CPColor(@"filza",@"accent",view) ?: CPColor(@"accent",role,view);
    for (UIView *p=view; p; p=p.superview) {
        if ([p isKindOfClass:UINavigationBar.class]) return CPColor(@"navigation",@"items",view);
        if ([p isKindOfClass:UIToolbar.class]) return CPColor(@"toolbar",@"items",view);
        if ([p isKindOfClass:UITabBar.class]) return nil; // The bar owns selected/normal colors.
    }
    return CPColor(@"accent",role,view);
}
static UIColor *Mapped(UIColor *source, UIColor *chosen, UIView *view) {
    if (!chosen || !NativeAccent(source,view)) return source;
    CGFloat alpha=CGColorGetAlpha([source resolvedColorWithTraitCollection:view.traitCollection].CGColor);
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
    UIColor *color=Accent(label,@"foreground");
    // Respect the independently selected primary/secondary cell text colors.
    for (UIView *p=label.superview; p; p=p.superview) {
        if ([p isKindOfClass:UIButton.class]) break;
        if ([p isKindOfClass:UITableViewCell.class]) {
            UITableViewCell *cell=(UITableViewCell *)p;
            if (!cell.contentConfiguration && label==cell.detailTextLabel)
                color=CPColor(@"cell",@"detail",cell) ?: color;
            else color=CPColor(@"cell",@"text",cell) ?: color;
            break;
        }
        if ([p isKindOfClass:UICollectionViewListCell.class]) {
            color=CPColor(@"cell",@"text",p) ?: color; break;
        }
    }
    AccentProperty(label,@"textColor",color,label);
    CPTransformValue(label,@"attributedText",color!=nil,color,^id(id source) { return Attributed(source,color,label); });
}
static void Button(UIButton *button) {
    UIColor *foreground=button.enabled ? Accent(button,@"foreground") : nil;
    UIColor *fill=button.enabled ? Accent(button,@"filled") : nil;
    BOOL filza=[NSBundle.mainBundle.bundleIdentifier.lowercaseString hasPrefix:@"com.tigisoftware.filza"];
    AccentProperty(button,@"tintColor",foreground,button);
    AccentProperty(button,@"backgroundColor",fill,button);
    AccentProperty(button.titleLabel,@"textColor",foreground,button);
    if (filza) {
        CPApplyColor(button,@"tintColor",foreground);
        CPApplyColor(button.titleLabel,@"textColor",foreground);
        CPApplySymbolColor(button.imageView,foreground);
    }
    CPTransform(button,@"configuration",foreground || fill,^id(id source) {
        if (![source isKindOfClass:UIButtonConfiguration.class]) return source;
        UIButtonConfiguration *copy=[source copy];
        copy.baseForegroundColor=(filza && foreground) ? foreground : Mapped(copy.baseForegroundColor,foreground,button);
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
void CPInstallAccent(void) {
    BOOL filza=[NSBundle.mainBundle.bundleIdentifier.lowercaseString hasPrefix:@"com.tigisoftware.filza"];
    if (filza) CPRegisterStateColorGetter(@"UIButton",@"titleColorForState:",@"filza",@"accent",@"accent");
    // MobileSMS has its own UIWindow action, installed by Private.mm.
    if (![NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.MobileSMS"])
        CPRegisterView(@"UIWindow",@[@"tintColor"],^(UIView *v) {
            if (filza) CPApplyColor(v,@"tintColor",CPColor(@"filza",@"accent",v));
            else AccentProperty(v,@"tintColor",Accent(v,@"foreground"),v);
        });
    CPRegisterView(@"UILabel",@[@"textColor",@"attributedText"],^(UIView *v) { Label((UILabel *)v); });
    CPRegisterView(@"UIButton",@[@"tintColor",@"backgroundColor",@"configuration"],^(UIView *v) { Button((UIButton *)v); });
    CPRegisterViewEvent(@"UIButton",@"updateConfiguration");
    CPRegisterView(@"UIImageView",@[@"tintColor",@"image"],^(UIView *v) {
        UIImageView *image=(UIImageView *)v;
        UIImage *source=CPSourceValue(image,@"image");
        // Only template images use tint. Keep multicolor symbols and actual artwork.
        if (source.renderingMode==UIImageRenderingModeAlwaysTemplate)
            AccentProperty(image,@"tintColor",Accent(image,@"symbol"),image);
        else AccentProperty(image,@"tintColor",nil,image);
    });
    CPRegisterView(@"UITextView",@[@"linkTextAttributes",@"tintColor"],^(UIView *v) {
        UIColor *color=CPColor(@"accent",@"link",v);
        if ([NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.mobilenotes"]) {
            color=CPColor(@"notes",@"link",v) ?: color;
            CPApplyColor(v,@"tintColor",color);
        }
        CPTransformValue(v,@"linkTextAttributes",color!=nil,color,^id(id source) {
            NSMutableDictionary *attrs=[source isKindOfClass:NSDictionary.class] ? [source mutableCopy] : [NSMutableDictionary dictionary];
            attrs[NSForegroundColorAttributeName]=color; attrs[NSUnderlineColorAttributeName]=color;
            return attrs;
        });
    });
}
