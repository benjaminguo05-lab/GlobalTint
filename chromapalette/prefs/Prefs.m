#import <Preferences/PSViewController.h>
#import <QuartzCore/QuartzCore.h>
#import "Config.h"

@interface CPDemoController : UITableViewController
@end

@interface CPPrefsTable : UITableViewController <UIColorPickerViewControllerDelegate>
@property(nonatomic,strong) NSMutableDictionary *configuration;
@property(nonatomic,strong) NSDictionary *group;
@property(nonatomic,copy) NSString *editingRole;
@property(nonatomic,copy) NSString *editingMode;
@end

@implementation CPPrefsTable
- (instancetype)init {
    if ((self=[super initWithStyle:UITableViewStyleInsetGrouped])) _configuration=[CPReadConfiguration() mutableCopy];
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=self.group ? self.group[@"title"] : @"Chroma Palette";
    self.navigationItem.largeTitleDisplayMode=UINavigationItemLargeTitleDisplayModeNever;
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.configuration=[CPReadConfiguration() mutableCopy];
    [self.tableView reloadData];
}
- (void)save {
    if (!CPWriteConfiguration(self.configuration)) {
        UIAlertController *a=[UIAlertController alertControllerWithTitle:@"设置保存失败" message:@"请确认 libSandy 已安装且设置应用已启用插件注入，然后重新打开设置。" preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        if (!self.presentedViewController) [self presentViewController:a animated:YES completion:nil];
    }
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.group ? 1+[self.group[@"roles"] count] : 3;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.group) return section==0 ? 1 : 3;
    return section==0 ? 2 : section==1 ? CPGroups().count : 4;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (self.group) return section==0 ? @"组件开关" : self.group[@"roles"][section-1][@"title"];
    return @[@"总开关",@"独立颜色设置",@"管理与验证"][section];
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (self.group) return section==0 ? self.group[@"note"] : nil;
    if (section==0) return @"首次安装默认关闭。先开启总开关测试普通控件；电池填充与控制中心还需开启各自开关和系统界面总开关。";
    if (section==1) return @"每项可分别选择浅色、深色颜色和透明度。此设置页的开关轨道也参与配色，其余控件保持原色。修改会通知已注入的应用。";
    return @"目标：iPhone 15 Pro Max / iOS 17.1.1 / Relaxin。实验性接口需要真机验证；编译成功不代表所有系统界面均已验证。";
}
- (NSString *)roleAtSection:(NSInteger)section {
    return [NSString stringWithFormat:@"%@.%@",self.group[@"key"],self.group[@"roles"][section-1][@"key"]];
}
- (void)addSwitch:(UITableViewCell *)cell value:(BOOL)value tag:(NSInteger)tag {
    UISwitch *s=[[UISwitch alloc] init]; s.on=value; s.tag=tag;
    [s addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView=s; cell.selectionStyle=UITableViewCellSelectionStyleNone;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.numberOfLines=0; cell.detailTextLabel.numberOfLines=0;
    if (!self.group) {
        if (path.section==0) {
            NSString *key=path.row==0 ? @"enabled" : @"systemEnabled";
            cell.textLabel.text=path.row==0 ? @"启用系统配色" : @"启用系统界面（实验性）";
            [self addSwitch:cell value:[self.configuration[key] boolValue] tag:path.row];
        } else if (path.section==1) {
            NSDictionary *g=CPGroups()[path.row]; cell.textLabel.text=g[@"title"];
            NSUInteger enabled=0;
            for (NSDictionary *role in g[@"roles"]) {
                NSString *key=[NSString stringWithFormat:@"%@.%@",g[@"key"],role[@"key"]];
                if ([self.configuration[@"roles"][key][@"enabled"] boolValue]) ++enabled;
            }
            cell.detailTextLabel.text=[self.configuration[@"groups"][g[@"key"]] boolValue] ?
                [NSString stringWithFormat:@"已开启 · %lu/%lu 项颜色已启用",(unsigned long)enabled,(unsigned long)[g[@"roles"] count]] : @"已关闭 · 点击设置颜色";
            cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
        } else {
            cell.textLabel.text=@[@"不改色的应用",@"控件预览",@"关闭并恢复默认设置",@"配置读取诊断"][path.row];
            cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
        }
    } else if (path.section==0) {
        cell.textLabel.text=@"启用此组件";
        [self addSwitch:cell value:[self.configuration[@"groups"][self.group[@"key"]] boolValue] tag:0];
    } else {
        NSString *role=[self roleAtSection:path.section]; NSDictionary *r=self.configuration[@"roles"][role];
        if (path.row==0) {
            cell.textLabel.text=@"替换此项颜色";
            [self addSwitch:cell value:[r[@"enabled"] boolValue] tag:path.section];
        } else {
            BOOL dark=(path.row==2); NSString *mode=dark ? @"dark" : @"light";
            cell.textLabel.text=dark ? @"深色模式：选择颜色" : @"浅色模式：选择颜色";
            cell.detailTextLabel.text=@"点击打开颜色选择器"; cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
            UIView *swatch=[[UIView alloc] initWithFrame:CGRectMake(0,0,30,30)];
            swatch.backgroundColor=CPParseHex(r[mode]); swatch.layer.cornerRadius=7;
            swatch.layer.borderWidth=1; swatch.layer.borderColor=UIColor.separatorColor.CGColor; cell.accessoryView=swatch;
        }
    }
    return cell;
}
- (void)toggle:(UISwitch *)s {
    if (!self.group) self.configuration[s.tag==0 ? @"enabled" : @"systemEnabled"]=@(s.on);
    else if (s.tag==0) {
        NSMutableDictionary *groups=[self.configuration[@"groups"] mutableCopy]; groups[self.group[@"key"]]=@(s.on); self.configuration[@"groups"]=groups;
    } else {
        NSString *role=[self roleAtSection:s.tag];
        NSMutableDictionary *roles=[self.configuration[@"roles"] mutableCopy], *r=[roles[role] mutableCopy];
        r[@"enabled"]=@(s.on); roles[role]=r; self.configuration[@"roles"]=roles;
    }
    [self save];
}
- (void)setColor:(UIColor *)color {
    if (!self.editingRole || !self.editingMode) return;
    NSMutableDictionary *roles=[self.configuration[@"roles"] mutableCopy], *r=[roles[self.editingRole] mutableCopy];
    r[self.editingMode]=CPHex(color); roles[self.editingRole]=r; self.configuration[@"roles"]=roles;
    [self save]; [self.tableView reloadData];
}
- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)controller { [self setColor:controller.selectedColor]; }
- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)controller { [self setColor:controller.selectedColor]; }
- (void)editExclusions {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"不改色的应用" message:@"输入应用标识，多个用逗号分隔。例如 com.apple.mobilesafari。此列表不会开启或关闭 Relaxin 的注入。" preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f) { f.text=[self.configuration[@"excludedApps"] componentsJoinedByString:@","]; f.autocapitalizationType=UITextAutocapitalizationTypeNone; f.autocorrectionType=UITextAutocorrectionTypeNo; }];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSMutableArray *ids=[NSMutableArray array];
        for (NSString *part in [a.textFields.firstObject.text componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@",，\n "]]) {
            NSString *item=[part stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (item.length) [ids addObject:item];
        }
        self.configuration[@"excludedApps"]=ids; [self save];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)reset {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"恢复默认设置" message:@"这会关闭改色并清除本插件的自选颜色和排除列表。" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"恢复" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { self.configuration=[CPDefaults() mutableCopy]; [self save]; [self.tableView reloadData]; }]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)diagnostics {
    NSDictionary *disk=CPReadConfiguration();
    NSString *message=[NSString stringWithFormat:@"版本：0.1.3\nlibSandy 返回值：%d\n总开关：%@\n系统界面：%@\n颜色项：%lu\n\n这仅检查设置进程读到的配置。其他进程的注入与私有接口命中，需要查看 ChromaPalette 日志并真机测试。",CPPreparePreferences(),[disk[@"enabled"] boolValue]?@"开":@"关",[disk[@"systemEnabled"] boolValue]?@"开":@"关",(unsigned long)[disk[@"roles"] count]];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"配置读取诊断" message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]]; [self presentViewController:a animated:YES completion:nil];
}
- (void)preview { [self.navigationController pushViewController:[[CPDemoController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES]; }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (!self.group) {
        if (path.section==1) { CPPrefsTable *child=[[CPPrefsTable alloc] init]; child.group=CPGroups()[path.row]; [self.navigationController pushViewController:child animated:YES]; }
        else if (path.section==2) {
            if (path.row==0) [self editExclusions];
            if (path.row==1) [self preview];
            if (path.row==2) [self reset];
            if (path.row==3) [self diagnostics];
        }
        return;
    }
    if (!path.section || !path.row) return;
    self.editingRole=[self roleAtSection:path.section]; self.editingMode=(path.row==2) ? @"dark" : @"light";
    UIColorPickerViewController *picker=[[UIColorPickerViewController alloc] init]; picker.delegate=self; picker.supportsAlpha=YES;
    picker.selectedColor=CPParseHex(self.configuration[@"roles"][self.editingRole][self.editingMode]);
    [self presentViewController:picker animated:YES completion:nil];
}
@end

// Deliberately outside CPPrefs* so the component hooks can color this test page.
@implementation CPDemoController
- (void)viewDidLoad { [super viewDidLoad]; self.title=@"控件预览"; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)section { return 4; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.text=@[@"主要文字",@"切换开关",@"滑块",@"进度条"][path.row];
    cell.detailTextLabel.text=path.row==0 ? @"辅助文字 · 点击查看选中背景" : nil;
    if (path.row==1) { UISwitch *s=[[UISwitch alloc] init]; s.on=YES; cell.accessoryView=s; }
    if (path.row==2) { UISlider *s=[[UISlider alloc] initWithFrame:CGRectMake(0,0,160,32)]; s.value=0.6; cell.accessoryView=s; }
    if (path.row==3) { UIProgressView *p=[[UIProgressView alloc] initWithFrame:CGRectMake(0,0,160,12)]; p.progress=0.6; cell.accessoryView=p; }
    return cell;
}
@end
@interface CPPrefsRootController : PSViewController
@end
@implementation CPPrefsRootController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"Chroma Palette";
    CPPrefsTable *child=[[CPPrefsTable alloc] init];
    [self addChildViewController:child]; child.view.frame=self.view.bounds; child.view.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:child.view]; [child didMoveToParentViewController:self];
}
@end
