#import "Runtime.h"

static void Status(void) {
    CPRegisterView(@"_UIBatteryView",@[@"fillColor"],^(UIView *v) {
        CPApplyColor(v,@"fillColor",CPColor(@"status",@"battery",v));
    });
}
static void SelectedBackground(id background, UIColor *color) {
    if (![background isKindOfClass:UIView.class]) return;
    CPApplyColor(background,@"backgroundColor",color);
    if ([background isKindOfClass:UIVisualEffectView.class])
        CPApplyColor(((UIVisualEffectView *)background).contentView,@"backgroundColor",color);
}
static void GlyphImage(id image, UIColor *color) {
    if (![image isKindOfClass:UIImageView.class]) return;
    CPApplyColor(image,@"tintColor",color);
    CPApplyImageColor(image,color);
    CPTransformValue(image,@"highlightedImage",color!=nil,color,^id(id source) {
        return [source isKindOfClass:UIImage.class] ? [source imageWithTintColor:color renderingMode:UIImageRenderingModeAlwaysOriginal] : source;
    });
    // Keep the selected glyph's actual RGB color through dark material rendering.
    // Restore only this image layer's original filters when the option/state is off.
    CPTransformValue(((UIImageView *)image).layer,@"filters",color!=nil,color,^id(id source) { return nil; });
    CPTransformValue(((UIImageView *)image).layer,@"compositingFilter",color!=nil,color,^id(id source) { return nil; });
}
static void SelectedGlyph(UIView *button, UIColor *color) {
    id selected=CPGetObject(button,@"selectedGlyphView");
    GlyphImage(selected,color);
    BOOL on=[button isKindOfClass:UIControl.class] && ((UIControl *)button).selected;
    id image=CPGetObject(button,@"glyphImageView") ?: CPGetIvar(button,"_glyphImageView");
    GlyphImage(image,on ? color : nil);
    id package=CPGetIvar(button,"_glyphPackageView");
    if ([package isKindOfClass:UIView.class]) CPApplyColor(package,@"tintColor",on ? color : nil);
}
static void ControlCenter(void) {
    for (NSString *name in @[@"CCUIRoundButton",@"CCUIConnectivityButtonView"]) {
        CPRegisterColorGetter(name,@"highlightColor",@"controlcenter",@"active");
        CPRegisterView(name,@[],^(UIView *v) {
            UIColor *active=CPColor(@"controlcenter",@"active",v);
            for (NSString *property in @[@"selectedStateBackgroundView",@"alternateSelectedStateBackgroundView"])
                SelectedBackground(CPGetObject(v,property),active);
            SelectedGlyph(v,CPColor(@"controlcenter",@"selectedGlyph",v));
        });
        CPRegisterViewEvent(name,@"_updateForStateChange");
    }
    // Override the color read by the selected state, without changing ordinary glyphs.
    CPRegisterColorGetter(@"CCUIButtonModuleView",@"selectedGlyphColor",@"controlcenter",@"selectedGlyph");
    CPRegisterView(@"CCUIButtonModuleView",@[],^(UIView *v) {
        SelectedGlyph(v,CPColor(@"controlcenter",@"selectedGlyph",v));
    });
    CPRegisterViewEvent(@"CCUIButtonModuleView",@"_updateForStateChange");
}
void CPInstallPrivate(BOOL systemProcess) {
    Status();
    if (systemProcess) ControlCenter();
    else if ([NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.MobileSMS"]) {
        CPRegisterView(@"UIWindow",@[@"tintColor"],^(UIView *v) {
            CPApplyColor(v,@"tintColor",CPColor(@"messages",@"accent",v));
        });
        for (NSString *selector in @[@"appTintColor",@"darkAppTintColor",@"entryFieldButtonColor",@"entryFieldDarkStyleButtonColor",@"segmentedControlSelectionTintColor"])
            CPRegisterColorGetter(@"CKUITheme",selector,@"messages",@"accent");
        CPRegisterView(@"CKConversationListStandardCell",@[],^(UIView *v) {
            id image=CPGetIvar(v,"_unreadIndicatorImageView");
            if ([image isKindOfClass:UIImageView.class]) CPApplyImageColor(image,CPColor(@"messages",@"unread",v));
        });
    }
}
