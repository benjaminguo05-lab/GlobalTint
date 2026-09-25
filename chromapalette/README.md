# iOS全局改色 0.1.7

适用于 iPhone 15 Pro Max / iOS 17.1.1 / Relaxin（RootHide）。包标识仍是 `com.benja.chromapalette`，可从旧版直接升级。

## 本次修改

- “不改色的应用”改为已安装应用列表，显示图标、名称和标识符，可以搜索并逐项切换。打开开关表示该应用不改色，关闭表示使用插件配色。保留旧排除项以及暂时未枚举到的应用标识，保存失败则回退开关。列表只在手机本地读取，不上传应用信息，不修改 Relaxin 注入配置。
- 设置入口 `Spectrum.png` 从 90×90 缩为 30×30，保留原图案。
- 照片 App 的列表小型 SF Symbols 也参与通用强调色；为已知相簿分类图标槽增加小型图标适配，不对相册照片缩略图改色。
- App Store 的购买／更新按钮补充 `ASCOfferTheme` 的蓝色值映射，并为 AppStore 模块实际已加载的 OfferButton 视图增加局部背景和形状层适配。仅检查按钮自身的有限层级（最多 48 层节点、3 层深度），复用可恢复、有冲突限额的属性引擎；没有添加 UIView/CALayer 全局绘制钩子。白色按钮文字及其他非标准蓝色保持原值。
- 修正已有 Filza 和 UIButton 只读钩子的重复安装问题。框架载入或应用回到前台时，不再叠加相同钩子。

继续使用“通用蓝色强调色”设置，不增加按 App 选择颜色的入口。保持 9 组、20 项颜色。保留 0.1.6 的 Filza 修复，已删除的列表、键盘等改色项不恢复。

## 安装与复测

下载本次 Actions 的 `ChromaPalette-RootHide-运行编号`，解压安装版本为 **0.1.7** 的 `.deb`，按提示重新载入桌面并重开照片和 App Store。

1. 设置入口图标应为正常小图标；进入“不改色的应用”查看图标、名称、标识符和搜索框。
2. 搜索一个应用，打开排除开关后重开该应用，检查恢复原色；关闭后重开，检查重新配色。退出列表再进入，确认选择保留。
3. 开启通用蓝色强调色，检查照片的录屏、空间、RAW 图标以及 App Store 详情页顶部“更新”实心按钮。切换浅深色再检查；关闭通用强调色并重开应用，检查原色恢复。

运行源码和安装包契约检查、属性引擎回归测试，并在 GitHub macOS 环境编译 arm64/arm64e。编译成功不能代替真机验证；私有控件在具体系统版本或主题插件下可能不同，未命中的接口会跳过。

接口依据：[iOS 17 AppStoreComponents 运行时头文件](https://github.com/matbrik/iOS17-Runtime-Headers/tree/master/PrivateFrameworks/AppStoreComponents.framework)、[iOS 17 CoreServices 头文件](https://github.com/matbrik/iOS17-Runtime-Headers/tree/master/Frameworks/CoreServices.framework)、[相簿分类内容视图](https://github.com/nst/iOS-Runtime-Headers/blob/master/Frameworks/PhotosUI.framework/PUAlbumListCellContentView.h)。旧版头文件仅作为兼容候选，安装前仍检查类和方法签名。
