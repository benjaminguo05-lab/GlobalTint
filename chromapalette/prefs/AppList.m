#import "AppList.h"
#import "Config.h"
#import <objc/message.h>
#import <objc/runtime.h>

// LaunchServices enumeration is read-only. No app launching or injection changes.
static id ReadObject(id object, NSString *name) {
    SEL selector=NSSelectorFromString(name);
    Method method=class_getInstanceMethod(object_getClass(object),selector);
    char type[32]={};
    if (!method || method_getNumberOfArguments(method)!=2) return nil;
    method_getReturnType(method,type,sizeof(type));
    if (type[0]!='@') return nil;
    return ((id (*)(id,SEL))objc_msgSend)(object,selector);
}
@interface CPAppSwitch : UISwitch
@property(nonatomic,copy) NSString *bundleID;
@end
@implementation CPAppSwitch
@end

@interface CPPrefsAppList ()
@property(nonatomic,strong) NSArray<NSDictionary *> *apps;
@property(nonatomic,strong) NSArray<NSDictionary *> *visibleApps;
@property(nonatomic,strong) NSSet<NSString *> *excluded;
@property(nonatomic,strong) UISearchController *search;
@property(nonatomic,strong) NSCache *icons;
@property(nonatomic,copy) NSString *loadMessage;
@end
@implementation CPPrefsAppList
- (instancetype)init {
    if ((self=[super initWithStyle:UITableViewStyleInsetGrouped])) {
        _apps=@[]; _visibleApps=@[]; _icons=[[NSCache alloc] init]; _icons.countLimit=100;
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"不改色的应用";
    self.navigationItem.largeTitleDisplayMode=UINavigationItemLargeTitleDisplayModeNever;
    self.tableView.rowHeight=68;
    self.search=[[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater=self; self.search.obscuresBackgroundDuringPresentation=NO;
    self.search.searchBar.placeholder=@"名字或者标识符";
    self.navigationItem.searchController=self.search;
    self.navigationItem.hidesSearchBarWhenScrolling=NO; self.definesPresentationContext=YES;
    self.excluded=[NSSet setWithArray:CPReadConfiguration()[@"excludedApps"] ?: @[]];
    self.loadMessage=@"正在读取已安装应用…";
    NSSet *saved=self.excluded;
    __weak CPPrefsAppList *weakSelf=self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        NSMutableDictionary *byID=[NSMutableDictionary dictionary]; BOOL readable=NO;
        @try {
            id workspace=ReadObject(NSClassFromString(@"LSApplicationWorkspace"),@"defaultWorkspace");
            id proxies=ReadObject(workspace,@"allInstalledApplications");
            readable=[proxies isKindOfClass:NSArray.class] && [proxies count]>0;
            if (readable) for (id proxy in proxies) {
                NSString *bundle=ReadObject(proxy,@"applicationIdentifier");
                if (![bundle isKindOfClass:NSString.class] || !bundle.length) continue;
                NSString *name=ReadObject(proxy,@"localizedName");
                if (![name isKindOfClass:NSString.class] || !name.length) name=bundle;
                byID[bundle]=@{@"id":bundle,@"name":name};
            }
        } @catch (__unused NSException *exception) { readable=NO; }
        // Never lose saved exclusions if an app is uninstalled or enumeration fails.
        for (NSString *bundle in saved) if (!byID[bundle])
            byID[bundle]=@{@"id":bundle,@"name":bundle};
        NSArray *apps=[byID.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b) {
            NSComparisonResult result=[a[@"name"] localizedStandardCompare:b[@"name"]];
            return result==NSOrderedSame ? [a[@"id"] compare:b[@"id"]] : result;
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            CPPrefsAppList *live=weakSelf; if (!live) return;
            live.apps=apps;
            live.loadMessage=readable ? nil : @"未能读取已安装应用。请重新打开设置，并确认设置的插件注入正常；已保存的排除项仍保留。";
            [live updateSearchResultsForSearchController:live.search];
        });
    });
}
- (void)updateSearchResultsForSearchController:(UISearchController *)search {
    NSString *query=[search.searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    self.visibleApps=query.length ? [self.apps filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *app,NSDictionary *bindings) {
        NSStringCompareOptions options=NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch;
        return [app[@"name"] rangeOfString:query options:options].location!=NSNotFound ||
            [app[@"id"] rangeOfString:query options:options].location!=NSNotFound;
    }]] : self.apps;
    [self.tableView reloadData];
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return self.visibleApps.count; }
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    if (self.loadMessage) return self.loadMessage;
    return self.visibleApps.count ? @"开关打开：该应用不改色。关闭：按插件配色。修改后重开对应应用；此处不改变 Relaxin 的注入开关。" : @"没有匹配的应用。";
}
- (UIImage *)iconForBundle:(NSString *)bundle {
    UIImage *cached=[self.icons objectForKey:bundle]; if (cached) return cached;
    SEL selector=NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
    Method method=class_getClassMethod(UIImage.class,selector); UIImage *image=nil;
    char result[16]={},arg[16]={},format[16]={},scale[16]={};
    if (method && method_getNumberOfArguments(method)==5) {
        method_getReturnType(method,result,sizeof(result));
        method_getArgumentType(method,2,arg,sizeof(arg));
        method_getArgumentType(method,3,format,sizeof(format));
        method_getArgumentType(method,4,scale,sizeof(scale));
        if (result[0]=='@' && arg[0]=='@' && format[0]=='i' && scale[0]=='d') {
            @try { image=((id (*)(id,SEL,id,int,double))objc_msgSend)(UIImage.class,selector,bundle,0,UIScreen.mainScreen.scale); }
            @catch (__unused NSException *exception) { image=nil; }
        }
    }
    if (![image isKindOfClass:UIImage.class]) image=[UIImage systemImageNamed:@"app.dashed"];
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(40,40)];
    UIImage *sized=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context) { [image drawInRect:CGRectMake(0,0,40,40)]; }];
    [self.icons setObject:sized forKey:bundle]; return sized;
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[table dequeueReusableCellWithIdentifier:@"Application"];
    if (!cell) cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Application"];
    NSDictionary *app=self.visibleApps[path.row]; NSString *bundle=app[@"id"];
    cell.textLabel.text=app[@"name"]; cell.detailTextLabel.text=bundle;
    cell.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.detailTextLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    cell.detailTextLabel.textColor=UIColor.secondaryLabelColor;
    cell.imageView.image=[self iconForBundle:bundle]; cell.imageView.layer.cornerRadius=9; cell.imageView.clipsToBounds=YES;
    CPAppSwitch *toggle=[[CPAppSwitch alloc] init]; toggle.bundleID=bundle; toggle.on=[self.excluded containsObject:bundle];
    toggle.accessibilityLabel=[NSString stringWithFormat:@"%@：不改色",app[@"name"]];
    [toggle addTarget:self action:@selector(toggleApp:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView=toggle; cell.selectionStyle=UITableViewCellSelectionStyleNone;
    return cell;
}
- (void)toggleApp:(CPAppSwitch *)toggle {
    NSMutableDictionary *configuration=[CPReadConfiguration() mutableCopy];
    NSMutableSet *excluded=[NSMutableSet setWithArray:configuration[@"excludedApps"] ?: @[]];
    if (toggle.on) [excluded addObject:toggle.bundleID]; else [excluded removeObject:toggle.bundleID];
    configuration[@"excludedApps"]=[excluded.allObjects sortedArrayUsingSelector:@selector(compare:)];
    if (CPWriteConfiguration(configuration)) { self.excluded=excluded; return; }
    [toggle setOn:!toggle.on animated:YES];
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"设置保存失败" message:@"本次选择未保存，请重新打开设置后重试。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end
