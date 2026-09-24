#import "Runtime.h"
static void NotesSymbols(UIView *cell);
static BOOL IsFilza(void) {
    return [NSBundle.mainBundle.bundleIdentifier.lowercaseString hasPrefix:@"com.tigisoftware.filza"];
}
static UIColor *ItemsColor(NSString *group, NSString *role, UIView *view) {
    if (IsFilza()) {
        UIColor *accent=CPColor(@"filza",@"accent",view);
        if (accent) return accent;
    }
    return CPColor(group,role,view);
}

static NSMutableDictionary *TextAttributes(NSDictionary *source, UIColor *color) {
    NSMutableDictionary *out=source ? [source mutableCopy] : [NSMutableDictionary dictionary];
    if (color) out[NSForegroundColorAttributeName]=color;
    return out;
}
static UINavigationBarAppearance *NavigationAppearance(UINavigationBarAppearance *source, UINavigationBar *bar) {
    UINavigationBarAppearance *a=[source copy] ?: [bar.standardAppearance copy];
    UIColor *bg=CPColor(@"navigation",@"background",bar);
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
}
static void Toolbar(UIToolbar *bar) {
    UIColor *items=ItemsColor(@"toolbar",@"items",bar), *bg=CPColor(@"toolbar",@"background",bar);
    CPApplyColor(bar,@"tintColor",items);
    for (UIBarButtonItem *item in bar.items) CPApplyColor(item,@"tintColor",items);
    for (NSString *p in @[@"standardAppearance",@"scrollEdgeAppearance",@"compactAppearance",@"compactScrollEdgeAppearance"])
        CPTransform(bar,p,items || bg,^id(id source) {
            UIToolbarAppearance *a=[source copy] ?: [bar.standardAppearance copy];
            if (bg) { a.backgroundColor=bg; a.backgroundEffect=nil; a.backgroundImage=nil; }
            if (items) for (UIBarButtonItemAppearance *button in @[a.buttonAppearance,a.doneButtonAppearance])
                button.normal.titleTextAttributes=TextAttributes(button.normal.titleTextAttributes,items);
            return a;
        });
}
static UITabBarAppearance *TabAppearance(UITabBarAppearance *source, UITabBar *bar) {
    UITabBarAppearance *a=[source copy] ?: [bar.standardAppearance copy];
    UIColor *bg=CPColor(@"tabbar",@"background",bar), *selected=ItemsColor(@"tabbar",@"selected",bar), *normal=CPColor(@"tabbar",@"normal",bar);
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
static NSAttributedString *ListText(NSAttributedString *source, UIColor *color) {
    if (!source || !color || !source.length) return source;
    NSMutableAttributedString *copy=[source mutableCopy];
    [copy addAttribute:NSForegroundColorAttributeName value:color range:NSMakeRange(0,copy.length)];
    return copy;
}
static void Cell(UITableViewCell *cell) {
    UIColor *bg=CPColor(@"cell",@"background",cell), *text=CPColor(@"cell",@"text",cell), *detail=CPColor(@"cell",@"detail",cell);
    CPApplyColor(cell,@"backgroundColor",bg);
    CPApplyColor(cell,@"tintColor",CPColor(@"cell",@"accessory",cell));
    CPTransform(cell,@"backgroundConfiguration",bg != nil,^id(id source) {
        UIBackgroundConfiguration *a=[source copy] ?: [UIBackgroundConfiguration listPlainCellConfiguration];
        a.backgroundColor=bg; a.backgroundColorTransformer=nil;
        return a;
    });
    UIColor *selected=CPColor(@"cell",@"selected",cell);
    CPTransform(cell,@"selectedBackgroundView",selected != nil,^id(id source) {
        UIView *v=[[UIView alloc] initWithFrame:cell.bounds]; v.backgroundColor=selected; return v;
    });
    UIColor *icon=CPColor(@"cell",@"icon",cell);
    id content=cell.contentConfiguration;
    if (!content || [content isKindOfClass:UIListContentConfiguration.class]) {
        CPTransform(cell,@"contentConfiguration",(text || detail || icon) && content != nil,^id(id source) {
            if (![source isKindOfClass:UIListContentConfiguration.class]) return source;
            UIListContentConfiguration *a=[source copy];
            if (text) { a.textProperties.color=text; a.textProperties.colorTransformer=nil; a.attributedText=ListText(a.attributedText,text); }
            if (detail) { a.secondaryTextProperties.color=detail; a.secondaryTextProperties.colorTransformer=nil; a.secondaryAttributedText=ListText(a.secondaryAttributedText,detail); }
            if (icon) { a.imageProperties.tintColor=icon; a.imageProperties.tintColorTransformer=nil; }
            return a;
        });
        if (!content) {
            CPApplyColor(cell.textLabel,@"textColor",text);
            CPApplyColor(cell.detailTextLabel,@"textColor",detail);
            CPApplyColor(cell.imageView,@"tintColor",icon);
            // Preserve photos and arbitrary raster artwork in ordinary list cells.
            CPApplySymbolColor(cell.imageView,icon);
        }
    }
    if ([NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.mobilenotes"]) NotesSymbols(cell);
}
static void CollectionCell(UICollectionViewListCell *cell) {
    UIColor *icon=CPColor(@"cell",@"icon",cell), *text=CPColor(@"cell",@"text",cell), *detail=CPColor(@"cell",@"detail",cell);
    CPApplyColor(cell,@"tintColor",CPColor(@"cell",@"accessory",cell));
    CPTransform(cell,@"contentConfiguration",icon || text || detail,^id(id source) {
        if (![source isKindOfClass:UIListContentConfiguration.class]) return source;
        UIListContentConfiguration *a=[source copy];
        if (icon) { a.imageProperties.tintColor=icon; a.imageProperties.tintColorTransformer=nil; }
        if (text) { a.textProperties.color=text; a.textProperties.colorTransformer=nil; a.attributedText=ListText(a.attributedText,text); }
        if (detail) { a.secondaryTextProperties.color=detail; a.secondaryTextProperties.colorTransformer=nil; a.secondaryAttributedText=ListText(a.secondaryAttributedText,detail); }
        return a;
    });
    if ([NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.mobilenotes"]) NotesSymbols(cell);
}
static void NotesSymbols(UIView *cell) {
    // Notes uses collection cells and hierarchical symbols instead of UITableViewCell.imageView.
    // Bound the walk to this cell. Never inspect or modify note text/attachment data.
    NSMutableArray<UIView *> *pending=[NSMutableArray arrayWithArray:cell.subviews];
    UIColor *color=CPColor(@"cell",@"icon",cell);
    for (NSUInteger visited=0; pending.count && visited<64; ++visited) {
        UIView *view=pending.lastObject; [pending removeLastObject];
        if ([view isKindOfClass:UIImageView.class]) {
            UIImageView *icon=(UIImageView *)view;
            CPApplySymbolColor(icon,color);
        }
        if (![view isKindOfClass:UICollectionViewCell.class] && ![view isKindOfClass:UITableViewCell.class])
            [pending addObjectsFromArray:view.subviews];
    }
}
void CPInstallComponents(void) {
    for (NSString *selector in @[@"_buttonTintColorForState:",@"_contentTintColorForState:",@"iconColorForState:",@"defaultColorForState:"])
        CPRegisterTabColorGetter(selector);
    CPRegisterColorGetter(@"UISwitchModernVisualElement",@"_effectiveOnTintColor",@"switch",@"on");
    CPRegisterColorGetter(@"UISwitchModernVisualElement",@"_effectiveTintColor",@"switch",@"off");
    CPInstallAccent();
    CPRegisterViewEvent(@"UITableViewCell",@"updateConfiguration");
    CPRegisterViewEvent(@"UICollectionViewListCell",@"updateConfiguration");
    CPTrackProperties(@"UINavigationItem",@[@"standardAppearance",@"scrollEdgeAppearance",@"compactAppearance",@"compactScrollEdgeAppearance"]);
    CPTrackProperties(@"UITabBarItem",@[@"standardAppearance",@"scrollEdgeAppearance"]);
    CPTrackProperties(@"UIBarButtonItem",@[@"tintColor"]);
    CPRegisterView(@"UINavigationBar",@[@"tintColor",@"standardAppearance",@"scrollEdgeAppearance",@"compactAppearance",@"compactScrollEdgeAppearance"],^(UIView *v) { Navigation((UINavigationBar *)v); });
    CPRegisterView(@"UIToolbar",@[@"tintColor",@"standardAppearance",@"scrollEdgeAppearance",@"compactAppearance",@"compactScrollEdgeAppearance"],^(UIView *v) { Toolbar((UIToolbar *)v); });
    CPRegisterView(@"UITabBar",@[@"tintColor",@"unselectedItemTintColor",@"standardAppearance",@"scrollEdgeAppearance"],^(UIView *v) { Tabbar((UITabBar *)v); });
    CPRegisterView(@"UITableView",@[@"backgroundColor",@"separatorColor",@"sectionIndexColor"],^(UIView *v) {
        CPApplyColor(v,@"backgroundColor",CPColor(@"table",@"background",v));
        CPApplyColor(v,@"separatorColor",CPColor(@"table",@"separator",v));
        CPApplyColor(v,@"sectionIndexColor",CPColor(@"table",@"index",v));
    });
    CPRegisterView(@"UITableViewCell",@[@"backgroundColor",@"tintColor",@"selectedBackgroundView",@"backgroundConfiguration",@"contentConfiguration"],^(UIView *v) { Cell((UITableViewCell *)v); });
    CPRegisterView(@"UICollectionViewListCell",@[@"tintColor",@"contentConfiguration"],^(UIView *v) { CollectionCell((UICollectionViewListCell *)v); });
    if ([NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.mobilenotes"])
        CPRegisterView(@"UICollectionViewCell",@[],^(UIView *v) { NotesSymbols(v); });
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
        CPApplyColor(v,@"progressTintColor",CPColor(@"progress",@"fill",v));
        CPApplyColor(v,@"trackTintColor",CPColor(@"progress",@"track",v));
    });
}
