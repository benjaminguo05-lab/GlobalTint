#import "Schema.h"
#import <math.h>

NSString * const CPPreferencePath = @"/var/mobile/Library/Preferences/com.benja.chromapalette.plist";
NSString * const CPNotification = @"com.benja.chromapalette/changed";

// This is the single source of truth for settings and runtime role defaults.
static NSDictionary *R(NSString *key, NSString *title, NSString *light, NSString *dark, BOOL enabled) {
    return @{ @"key":key, @"title":title, @"light":light, @"dark":dark, @"enabled":@(enabled) };
}
static NSDictionary *G(NSString *key, NSString *title, NSString *note, BOOL experimental, NSArray *roles) {
    return @{ @"key":key, @"title":title, @"note":note, @"experimental":@(experimental), @"roles":roles };
}
NSArray<NSDictionary *> *CPGroups(void) {
    static NSArray *groups;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        groups = @[
            G(@"navigation", @"导航栏", @"按钮、普通标题、大标题和背景分别设置。", NO, @[
                R(@"items", @"按钮与返回箭头", @"#168A60", @"#5CDBAA", YES),
                R(@"title", @"普通标题", @"#164A38", @"#C7FFE9", NO),
                R(@"largeTitle", @"大标题", @"#164A38", @"#C7FFE9", NO),
                R(@"background", @"背景", @"#ECF8F2", @"#162C23", NO)]),
            G(@"toolbar", @"工具栏", @"适用于使用系统工具栏的界面。", NO, @[
                R(@"items", @"按钮", @"#168A60", @"#5CDBAA", YES),
                R(@"background", @"背景", @"#ECF8F2", @"#162C23", NO)]),
            G(@"table", @"列表视图", @"只影响 UITableView；自绘列表和纯 SwiftUI 列表可能不适用。", NO, @[
                R(@"background", @"列表背景", @"#ECF8F2", @"#101E18", NO),
                R(@"separator", @"分隔线", @"#91BDA8", @"#355747", YES)]),
            G(@"cell", @"列表项", @"支持传统文字标签及标准列表内容配置；自定义内容不强行覆盖。", NO, @[
                R(@"background", @"单元格背景", @"#F5FFF9", @"#193326", NO),
                R(@"selected", @"选中背景", @"#BCEBD5", @"#2B6047", NO),
                R(@"text", @"主要文字", @"#174B36", @"#D6F8E6", NO),
                R(@"detail", @"辅助文字", @"#55856B", @"#9CCBB0", NO),
                R(@"accessory", @"附件强调色", @"#168A60", @"#5CDBAA", YES)]),
            G(@"switch", @"切换开关", @"关闭轨道采用开关自身的背景层，某些自定义开关可能不同。", NO, @[
                R(@"on", @"开启轨道", @"#18A572", @"#42D79C", YES),
                R(@"off", @"关闭轨道", @"#D4E4DC", @"#365345", NO),
                R(@"thumb", @"圆形滑钮", @"#FFFFFF", @"#ECFFF4", NO)]),
            G(@"slider", @"滑块", @"分别控制已滑过、未滑过部分及滑钮。", NO, @[
                R(@"minimum", @"已滑过轨道", @"#18A572", @"#42D79C", YES),
                R(@"maximum", @"未滑过轨道", @"#C9E4D6", @"#365345", NO),
                R(@"thumb", @"滑钮", @"#FFFFFF", @"#ECFFF4", NO)]),
            G(@"tabbar", @"底部标签栏", @"支持普通、滚动边缘及单个标签项的外观配置。", NO, @[
                R(@"selected", @"选中图标与文字", @"#168A60", @"#5CDBAA", YES),
                R(@"normal", @"未选中图标与文字", @"#789689", @"#789F8D", NO),
                R(@"background", @"背景", @"#ECF8F2", @"#162C23", NO)]),
            G(@"progress", @"进度条", @"适用于系统进度条。", NO, @[
                R(@"fill", @"进度颜色", @"#18A572", @"#42D79C", YES),
                R(@"track", @"底轨", @"#C9E4D6", @"#365345", NO)]),
            G(@"keyboard", @"键盘（实验性）", @"系统键盘背景、底部托盘、按键底色。按键底色通过渲染特征处理；不改变按键文字。渲染缓存可能需要关闭并重新打开应用。第三方或独立键盘进程不保证覆盖。", YES, @[
                R(@"background", @"键盘背景", @"#D5E9DE", @"#193428", YES),
                R(@"dock", @"底部托盘背景", @"#D5E9DE", @"#193428", NO),
                R(@"keycap", @"按键底色", @"#ECFFF5", @"#315D47", NO)]),
            G(@"status", @"状态栏（实验性）", @"时间等文字、信号及电池分开设置。电池颜色可能覆盖低电量/充电提示色。需要系统界面总开关；App 内和桌面分别注入。", YES, @[
                R(@"text", @"时间与文字", @"#168A60", @"#5CDBAA", YES),
                R(@"wifi", @"Wi-Fi 有效信号", @"#168A60", @"#5CDBAA", YES),
                R(@"cellular", @"蜂窝有效信号", @"#168A60", @"#5CDBAA", YES),
                R(@"inactive", @"未点亮信号", @"#A0C5B3", @"#456B58", NO),
                R(@"battery", @"电池填充", @"#18A572", @"#42D79C", NO),
                R(@"batteryBody", @"电池边框与电极", @"#168A60", @"#5CDBAA", NO)]),
            G(@"controlcenter", @"控制中心（实验性）", @"模块背景、圆形按钮高亮、模块图标、滑块填充。仅处理检测到的接口；部分材质与动画可能覆盖自选色。更改后收起并重新打开控制中心。", YES, @[
                R(@"background", @"模块背景着色", @"#265B4680", @"#265B4680", NO),
                R(@"active", @"圆形按钮开启色", @"#18A572", @"#42D79C", YES),
                R(@"glyph", @"普通模块图标", @"#E2FFF1", @"#E2FFF1", NO),
                R(@"selectedGlyph", @"开启模块图标", @"#FFFFFF", @"#FFFFFF", NO),
                R(@"slider", @"音量/亮度滑块填充", @"#42D79C", @"#42D79C", NO)])
        ];
    });
    return groups;
}
NSDictionary *CPDefaults(void) {
    NSMutableDictionary *groups = [NSMutableDictionary dictionary];
    NSMutableDictionary *roles = [NSMutableDictionary dictionary];
    for (NSDictionary *g in CPGroups()) {
        groups[g[@"key"]] = @(![g[@"experimental"] boolValue]);
        for (NSDictionary *r in g[@"roles"]) {
            NSString *key = [NSString stringWithFormat:@"%@.%@", g[@"key"], r[@"key"]];
            roles[key] = @{ @"enabled":r[@"enabled"], @"light":r[@"light"], @"dark":r[@"dark"] };
        }
    }
    return @{ @"schema":@1, @"enabled":@NO, @"systemEnabled":@NO,
              @"groups":groups, @"roles":roles, @"excludedApps":@[] };
}
UIColor *CPParseHex(id input) {
    if (![input isKindOfClass:NSString.class]) return nil;
    NSString *s = [[input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] uppercaseString];
    if ([s hasPrefix:@"#"]) s = [s substringFromIndex:1];
    if (s.length != 6 && s.length != 8) return nil;
    if ([s rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789ABCDEF"] invertedSet]].location != NSNotFound) return nil;
    unsigned long long n = 0;
    if (![[NSScanner scannerWithString:s] scanHexLongLong:&n]) return nil;
    if (s.length == 6) n = (n << 8) | 255;
    return [UIColor colorWithRed:((n >> 24) & 255)/255.0 green:((n >> 16)&255)/255.0 blue:((n >> 8)&255)/255.0 alpha:(n&255)/255.0];
}
NSString *CPHex(UIColor *color) {
    CGFloat r=0,g=0,b=0,a=1;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) return @"#000000FF";
    return [NSString stringWithFormat:@"#%02X%02X%02X%02X", (unsigned)lround(r*255), (unsigned)lround(g*255), (unsigned)lround(b*255), (unsigned)lround(a*255)];
}
