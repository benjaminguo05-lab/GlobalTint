# Chroma Palette 0.1.3

适用于 iPhone 15 Pro Max / iOS 17.1.1 / Relaxin（RootHide）的独立组件配色插件。使用独立配置和组件适配，不使用旧 GlobalTint 的全局颜色匹配。

## 本版修改

- 开关只保留开启、关闭轨道；移除圆形滑钮改色。Chroma Palette 自身设置页的开关轨道也参与配色，其他设置控件保持原色。
- 完全移除键盘改色选项及其运行时挂钩。
- 状态栏只保留电池填充，不再注册时间、信号、边框改色。
- 控制中心只保留圆形按钮开启色、开启模块图标。增加状态变化后刷新、按系统模式选色，以及选中图像高亮资源和局部材质合成处理，目标是修复深色模式遗漏。
- 移除手动 HEX 输入入口；每项保留浅色/深色原生颜色选择器及透明度。内部颜色存储格式保留，兼容旧配置。
- 启动、窗口显示、控件加入窗口后自动补色；启动后的两次有限补充刷新覆盖较晚创建的界面，不需要先触摸控件。每批最多 128 个视图、单次最多 8192 个，补充刷新不清除防循环写入计数。
- 新增备忘录链接选项，用 UITextView 的链接显示属性处理数字/电话号码/网址和下划线，不更改笔记的文字、链接目标或持久化内容。
- 新增 Filza 强调色适配，针对窗口、导航/工具栏/标签栏按钮、UIButton 标题和配置；注入过滤器增加 Filza 标识。用户环境为 Sileo 安装的 Filza 4.0.1.4，且已开启注入。
- PreferenceLoader 入口和设置 bundle 使用用户提供的原始 Spectrum.png 图标，安装包检查会核对图标字节。

本版共有 13 组、31 个独立颜色项。首次安装总开关关闭，系统组件默认关闭；从 0.1.1/0.1.2 升级保留有效颜色和开关，已移除的键不再加载。

## 编译和安装

GitHub Actions 工作流位于 `.github/workflows/chromapalette.yml`。构建使用 RootHide Theos，生成 `iphoneos-arm64e` 安装包，内含 arm64 与 arm64e 二进制。

下载本次 `ChromaPalette-RootHide-运行编号` 产物，解压后安装 `com.benja.chromapalette_0.1.3_iphoneos-arm64e.deb`。依赖 PreferenceLoader、libSandy 和注入框架。升级后按安装管理器提示重新载入 SpringBoard，再彻底关闭并重开相关 App。配置读取诊断应显示 0.1.3。

保留模块：导航栏、工具栏、列表、列表项、开关轨道、普通 App 滑块、底部标签栏、进度条、电池填充、控制中心两项、信息 App、备忘录链接、Filza。

## 检查范围

CI 检查配置结构、删除项、资源、Debian 控制文件换行和包内图标；运行实际属性更新引擎的 macOS 回归，覆盖复制对象、颜色冲突熔断、配置/浅深色变化、原值恢复、反复生命周期刷新和链接属性保留；最后检查安装包与 CPU 架构。

编译和逻辑测试不能替代 iOS 真机验证。首次显示、暗黑模式控制中心、备忘录链接和 Filza 的新增适配仍需要用户手机验证；主题插件自绘或不经过 UIKit 的界面可能仍遗漏。

## 实现边界

不全局替换 UIColor/CGColor，不给 UIView/CALayer 安装通用颜色匹配钩子。控制中心仅处理明确选中图像视图自身的合成属性，并在关闭时恢复；文件图片和笔记内容不全局重绘。私有接口运行时校验签名，不存在则跳过。

原始配置路径为 `/var/mobile/Library/Preferences/com.benja.chromapalette.plist`，越狱依赖使用 jbroot() 定位。两套动态库分别负责普通 App 和 SpringBoard。属性连续冲突时暂停单属性改写，优先保证交互。0.1.1 和 0.1.2 已由用户反馈不再卡死，不能因此推定任何后续改动都已完成真机验证。

接口参考：[Apple 链接显示属性](https://developer.apple.com/documentation/uikit/uitextview/linktextattributes)、[iOS 17 UIKit 头文件](https://github.com/matbrik/iOS17-Runtime-Headers/tree/master/PrivateFrameworks/UIKitCore.framework)、[运行时头文件参考](https://github.com/nst/iOS-Runtime-Headers)、[PreferenceLoader bundle 加载](https://github.com/DHowett/preferenceloader/blob/master/prefs.xm)。头文件参考不等于这台手机实时导出。
