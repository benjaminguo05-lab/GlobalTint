#import "Preview.h"
#import "Config.h"

@interface CPPrefsPreview ()
@property(nonatomic,strong) NSDictionary *configuration;
@end
@implementation CPPrefsPreview
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"控件预览";
    UISegmentedControl *mode=[[UISegmentedControl alloc] initWithItems:@[@"跟随系统",@"浅色",@"深色"]];
    mode.selectedSegmentIndex=0; [mode addTarget:self action:@selector(changeMode:) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView=mode;
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated]; self.configuration=CPReadConfiguration(); [self.tableView reloadData];
}
- (void)changeMode:(UISegmentedControl *)sender {
    self.overrideUserInterfaceStyle=sender.selectedSegmentIndex==0 ? UIUserInterfaceStyleUnspecified :
        (sender.selectedSegmentIndex==1 ? UIUserInterfaceStyleLight : UIUserInterfaceStyleDark);
    [self.tableView reloadData];
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previous]) [self.tableView reloadData];
}
- (UIColor *)color:(NSString *)group role:(NSString *)role fallback:(UIColor *)fallback {
    NSDictionary *config=self.configuration;
    BOOL experimental=[group isEqual:@"status"] || [group isEqual:@"controlcenter"];
    NSDictionary *r=config[@"roles"][[NSString stringWithFormat:@"%@.%@",group,role]];
    if (![config[@"enabled"] boolValue] || ![config[@"groups"][group] boolValue] || ![r[@"enabled"] boolValue] ||
        (experimental && ![config[@"systemEnabled"] boolValue])) return fallback;
    return CPParseHex(r[self.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark ? @"dark" : @"light"]) ?: fallback;
}
- (UIColor *)items:(NSString *)group role:(NSString *)role {
    return [self color:@"accent" role:@"color" fallback:[self color:group role:role fallback:UIColor.systemBlueColor]];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return CPGroups().count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 1; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return CPGroups()[section][@"title"]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    NSString *key=CPGroups()[section][@"key"];
    if ([key isEqual:@"status"] || [key isEqual:@"controlcenter"])
        return @"配色示意，非真实系统控件。实际效果请查看状态栏或控制中心。";
    if ([key isEqual:@"accent"]) return @"点击按钮可测试响应。导航栏、工具栏、标签栏选中项和进度填充优先使用通用强调色。";
    if ([key isEqual:@"switch"]) return @"可切换开启／关闭。滑钮保留系统外观。";
    return @"按当前开关与颜色预览；关闭的颜色项显示系统默认效果。上方可切换浅色／深色。";
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)path {
    return [@[@190,@90,@150,@120,@90,@100,@80,@110,@130][path.section] doubleValue];
}
- (void)buttonTapped:(UIButton *)button {
    BOOL selected=!button.selected; button.selected=selected;
    [button setTitle:selected ? @"已响应，再点一次恢复" : @"强调色按钮（点我）" forState:UIControlStateNormal];
}
- (void)tabBar:(UITabBar *)tabBar didSelectItem:(UITabBarItem *)item { tabBar.selectedItem=item; }
- (UIView *)sample:(NSString *)key width:(CGFloat)width {
    UIView *sample=[[UIView alloc] initWithFrame:CGRectMake(0,0,width,70)];
    if ([key isEqual:@"navigation"]) {
        UINavigationBar *bar=[[UINavigationBar alloc] initWithFrame:CGRectMake(0,0,width,44)];
        UINavigationBarAppearance *a=[UINavigationBarAppearance new]; [a configureWithDefaultBackground];
        a.backgroundColor=[self color:key role:@"background" fallback:nil];
        if (a.backgroundColor) a.backgroundEffect=nil;
        a.titleTextAttributes=@{NSForegroundColorAttributeName:[self color:key role:@"title" fallback:UIColor.labelColor]};
        bar.standardAppearance=a; bar.scrollEdgeAppearance=a; bar.tintColor=[self items:key role:@"items"];
        UINavigationItem *item=[[UINavigationItem alloc] initWithTitle:@"普通标题"];
        item.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"返回" style:UIBarButtonItemStylePlain target:nil action:nil];
        bar.items=@[item]; [sample addSubview:bar];
        UILabel *large=[[UILabel alloc] initWithFrame:CGRectMake(16,52,width-32,55)];
        large.text=@"大标题"; large.font=[UIFont boldSystemFontOfSize:32];
        large.textColor=[self color:key role:@"largeTitle" fallback:UIColor.labelColor];
        sample.backgroundColor=[self color:key role:@"background" fallback:UIColor.systemBackgroundColor];
        [sample addSubview:large]; sample.frame=CGRectMake(0,0,width,115);
    } else if ([key isEqual:@"toolbar"]) {
        UIToolbar *bar=[[UIToolbar alloc] initWithFrame:CGRectMake(0,0,width,44)];
        UIToolbarAppearance *a=[UIToolbarAppearance new]; [a configureWithDefaultBackground];
        UIColor *bg=[self color:key role:@"background" fallback:nil]; if (bg) { a.backgroundColor=bg; a.backgroundEffect=nil; }
        bar.standardAppearance=a; bar.scrollEdgeAppearance=a; bar.tintColor=[self items:key role:@"items"];
        bar.items=@[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:nil action:nil],
            [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],
            [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:nil action:nil]];
        [sample addSubview:bar];
    } else if ([key isEqual:@"accent"]) {
        UIColor *color=[self color:key role:@"color" fallback:UIColor.systemBlueColor];
        UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem]; button.frame=CGRectMake(0,0,width,44);
        [button setTitle:@"强调色按钮（点我）" forState:UIControlStateNormal]; button.tintColor=color;
        [button addTarget:self action:@selector(buttonTapped:) forControlEvents:UIControlEventTouchUpInside]; [sample addSubview:button];
        UILabel *link=[[UILabel alloc] initWithFrame:CGRectMake(16,52,width-32,30)];
        link.attributedText=[[NSAttributedString alloc] initWithString:@"链接文字与下划线示例" attributes:@{NSForegroundColorAttributeName:color,NSUnderlineStyleAttributeName:@1}];
        [sample addSubview:link];
    } else if ([key isEqual:@"switch"]) {
        for (NSInteger i=0;i<2;i++) {
            UILabel *label=[[UILabel alloc] initWithFrame:CGRectMake(16,i*44,width-100,34)]; label.text=i ? @"关闭轨道" : @"开启轨道"; [sample addSubview:label];
            UISwitch *control=[[UISwitch alloc] initWithFrame:CGRectMake(width-70,i*44,51,31)]; control.on=(i==0);
            control.onTintColor=[self color:key role:@"on" fallback:UIColor.systemGreenColor];
            UIColor *off=[self color:key role:@"off" fallback:UIColor.systemGray5Color];
            control.tintColor=off; control.backgroundColor=off; control.layer.cornerRadius=15.5;
            [sample addSubview:control];
        }
    } else if ([key isEqual:@"slider"]) {
        UISlider *slider=[[UISlider alloc] initWithFrame:CGRectMake(16,12,width-32,34)]; slider.value=0.6;
        slider.minimumTrackTintColor=[self color:key role:@"minimum" fallback:UIColor.systemBlueColor];
        slider.maximumTrackTintColor=[self color:key role:@"maximum" fallback:UIColor.systemGray4Color];
        slider.thumbTintColor=[self color:key role:@"thumb" fallback:UIColor.whiteColor]; [sample addSubview:slider];
    } else if ([key isEqual:@"tabbar"]) {
        UITabBar *bar=[[UITabBar alloc] initWithFrame:CGRectMake(0,0,width,60)]; bar.delegate=self;
        UITabBarAppearance *a=[UITabBarAppearance new]; [a configureWithDefaultBackground];
        UIColor *bg=[self color:key role:@"background" fallback:nil]; if (bg) { a.backgroundColor=bg; a.backgroundEffect=nil; }
        UIColor *selected=[self items:key role:@"selected"], *normal=[self color:key role:@"normal" fallback:UIColor.secondaryLabelColor];
        for (UITabBarItemAppearance *i in @[a.stackedLayoutAppearance,a.inlineLayoutAppearance,a.compactInlineLayoutAppearance]) {
            i.selected.iconColor=selected; i.selected.titleTextAttributes=@{NSForegroundColorAttributeName:selected};
            i.normal.iconColor=normal; i.normal.titleTextAttributes=@{NSForegroundColorAttributeName:normal};
        }
        bar.standardAppearance=a; bar.scrollEdgeAppearance=a;
        bar.items=@[[[UITabBarItem alloc] initWithTitle:@"首页" image:[UIImage systemImageNamed:@"house.fill"] tag:0],
                    [[UITabBarItem alloc] initWithTitle:@"收藏" image:[UIImage systemImageNamed:@"star.fill"] tag:1],
                    [[UITabBarItem alloc] initWithTitle:@"设置" image:[UIImage systemImageNamed:@"gearshape.fill"] tag:2]];
        bar.selectedItem=bar.items.firstObject; [sample addSubview:bar];
    } else if ([key isEqual:@"progress"]) {
        UIProgressView *progress=[[UIProgressView alloc] initWithFrame:CGRectMake(16,24,width-32,12)]; progress.progress=0.6;
        progress.progressTintColor=[self items:key role:@"fill"];
        progress.trackTintColor=[self color:key role:@"track" fallback:UIColor.systemGray4Color]; [sample addSubview:progress];
    } else if ([key isEqual:@"status"]) {
        UIView *battery=[[UIView alloc] initWithFrame:CGRectMake(16,14,90,38)];
        battery.layer.borderWidth=2; battery.layer.borderColor=UIColor.secondaryLabelColor.CGColor; battery.layer.cornerRadius=8;
        UIView *fill=[[UIView alloc] initWithFrame:CGRectMake(4,4,58,30)]; fill.layer.cornerRadius=4;
        fill.backgroundColor=[self color:key role:@"battery" fallback:UIColor.systemGreenColor]; [battery addSubview:fill]; [sample addSubview:battery];
        UILabel *label=[[UILabel alloc] initWithFrame:CGRectMake(120,14,width-130,38)]; label.text=@"70% · 电池填充示意"; label.font=[UIFont systemFontOfSize:13]; [sample addSubview:label];
    } else if ([key isEqual:@"controlcenter"]) {
        UIButton *circle=[UIButton buttonWithType:UIButtonTypeCustom]; circle.frame=CGRectMake(16,8,60,60); circle.layer.cornerRadius=30;
        circle.backgroundColor=[self color:key role:@"active" fallback:UIColor.systemBlueColor];
        circle.tintColor=[self color:key role:@"selectedGlyph" fallback:UIColor.whiteColor];
        [circle setImage:[UIImage systemImageNamed:@"wifi"] forState:UIControlStateNormal]; circle.userInteractionEnabled=NO; [sample addSubview:circle];
        UILabel *label=[[UILabel alloc] initWithFrame:CGRectMake(90,8,width-100,60)]; label.numberOfLines=2; label.font=[UIFont systemFontOfSize:13];
        label.text=@"圆形按钮开启背景\n开启模块图标示意"; [sample addSubview:label];
    }
    return sample;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle=UITableViewCellSelectionStyleNone;
    CGFloat width=MAX(200,CGRectGetWidth(tableView.bounds)-64);
    UIView *sample=[self sample:CPGroups()[path.section][@"key"] width:width];
    sample.translatesAutoresizingMaskIntoConstraints=NO; [cell.contentView addSubview:sample];
    [NSLayoutConstraint activateConstraints:@[[sample.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:8],
        [sample.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-8],
        [sample.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:12],
        [sample.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-12]]];
    return cell;
}
@end
