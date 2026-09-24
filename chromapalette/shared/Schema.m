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
                R(@"index", @"右侧字母索引", @"#168A60", @"#5CDBAA", YES),
                R(@"separator", @"分隔线", @"#91BDA8", @"#355747", YES)]),
            G(@"cell", @"列表项", @"支持表格及集合列表内容配置。列表图标可单独配色，也用于备忘录列表中的系统符号；照片和文档缩略图保持原样。", NO, @[
                R(@"background", @"单元格背景", @"#F5FFF9", @"#193326", NO),
                R(@"selected", @"选中背景", @"#BCEBD5", @"#2B6047", NO),
                R(@"text", @"主要文字", @"#174B36", @"#D6F8E6", NO),
                R(@"detail", @"辅助文字", @"#55856B", @"#9CCBB0", NO),
                R(@"accessory", @"附件强调色", @"#168A60", @"#5CDBAA", YES),
                R(@"icon", @"列表图标（含备忘录符号）", @"#168A60", @"#5CDBAA", YES)]),
            G(@"accent", @"按钮与链接强调色", @"覆盖系统蓝色的文字、按钮、模板图标及按钮填充。仅处理具体控件，不替换照片、快捷指令卡片或任意蓝色图片。独立绘制界面仍可能不适用。", NO, @[
                R(@"foreground", @"按钮文字与强调文字", @"#168A60", @"#5CDBAA", YES),
                R(@"symbol", @"强调图标", @"#168A60", @"#5CDBAA", YES),
                R(@"filled", @"强调按钮填充", @"#168A60", @"#348465", YES),
                R(@"link", @"文本链接与下划线", @"#168A60", @"#5CDBAA", YES)]),
            G(@"notes", @"备忘录链接", @"修改系统识别出的电话号码、网址等链接及其下划线的显示颜色，不改写笔记内容。", NO, @[
                R(@"link", @"链接与带下划线的数字", @"#168A60", @"#5CDBAA", YES)]),
            G(@"filza", @"Filza 文件管理器", @"修改窗口和按钮强调色。需要 Filza 实际启用插件注入；文件图片、缩略图保持原样。", NO, @[
                R(@"accent", @"Filza 强调色", @"#168A60", @"#5CDBAA", YES)]),
            G(@"messages", @"信息 App", @"适配 ChatKit 的强调色与未读圆点。更新后请彻底关闭并重开信息 App；自定义美化界面仍可能覆盖。", NO, @[
                R(@"accent", @"信息强调色", @"#168A60", @"#5CDBAA", YES),
                R(@"unread", @"未读圆点", @"#168A60", @"#5CDBAA", YES)]),
            G(@"switch", @"切换开关", @"修改开启、关闭轨道，也适用于 Chroma Palette 设置页的开关；滑钮保持原样。", NO, @[
                R(@"on", @"开启轨道", @"#18A572", @"#42D79C", YES),
                R(@"off", @"关闭轨道", @"#D4E4DC", @"#365345", NO)]),
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
            G(@"status", @"电池填充", @"仅修改电池内部填充颜色。需要启用系统界面；不修改时间、信号及电池边框。", YES, @[
                R(@"battery", @"电池填充", @"#18A572", @"#42D79C", NO)]),
            G(@"controlcenter", @"控制中心", @"仅修改圆形按钮开启色与开启模块图标。按系统浅色/深色模式选择颜色；美化插件自绘内容仍可能需要单独适配。", YES, @[
                R(@"active", @"圆形按钮开启色", @"#18A572", @"#42D79C", YES),
                R(@"selectedGlyph", @"开启模块图标", @"#FFFFFF", @"#FFFFFF", NO)])
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
    return @{ @"schema":@2, @"enabled":@NO, @"systemEnabled":@NO,
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
