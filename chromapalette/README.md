# Chroma Palette 0.1.0

为 iPhone 15 Pro Max、iOS 17.1.1、Relaxin / RootHide 编写的独立组件配色插件。与仓库原 GlobalTint 并列存放，不使用它的颜色匹配引擎，也不读取它的配置。

**当前属于首版真机验证版本。GitHub Actions 负责实际编译和打包；键盘、状态栏、控制中心是实验性适配，不能仅凭编译成功认定真机兼容。**

## 颜色设置

11 组组件、38 个独立颜色项。每项提供开关、浅色/深色模式颜色、系统原生颜色选择器、透明度以及 HEX 输入（`#RRGGBB` / `#RRGGBBAA`）。

| 组件 | 可设置的颜色 |
|---|---|
| UINavigationBar 导航栏 | 按钮/返回箭头、普通标题、大标题、背景 |
| UIToolbar 工具栏 | 按钮、背景 |
| UITableView 列表 | 背景、分隔线 |
| UITableViewCell 列表项 | 背景、选中背景、主要文字、辅助文字、附件强调色 |
| UISwitch 开关 | 开启轨道、关闭轨道底色、滑钮 |
| UISlider 滑块 | 已滑过轨道、未滑过轨道、滑钮 |
| UITabBar 标签栏 | 选中图标/文字、未选中图标/文字、背景 |
| UIProgressView 进度条 | 进度、底轨 |
| 系统键盘，实验性 | 背景、底部托盘、按键底色 |
| 状态栏，实验性 | 时间/文字、Wi-Fi、蜂窝信号、未点亮信号、电池填充、电池边框/电极 |
| 控制中心，实验性 | 模块背景着色、圆形按钮开启色、普通/开启模块图标、音量/亮度填充 |

也包含应用排除列表、关闭并重置、控件预览、设置读取诊断。首次安装总开关关闭；键盘/系统模块默认关闭。

## 在 GitHub 编译

本目录位于仓库根目录的 `chromapalette/`；对应工作流为根目录 `.github/workflows/chromapalette.yml`。

1. 打开 **Actions → Build Chroma Palette**。新代码提交会自动构建，也可在工作流存在于默认分支后手动运行。
2. 等待所有步骤成功。下载产物 **ChromaPalette-RootHide-运行编号**，解压取得 `.deb` 和 SHA256 校验文件。
3. 工作流使用 macOS、RootHide Theos，编译 `arm64 + arm64e`，生成架构为 `iphoneos-arm64e` 的原生 RootHide 包，并检查各动态库和设置面板都包含两个 CPU slice。

工作流不创建发布、不修改仓库权限、不自动安装手机软件。Theos 安装脚本入口固定至 `88506b2c22e9e07dd4ed055f23c9e398a117a2c7`；安装器内部依赖仍由上游解析，日志记录实际 Theos revision，因此不是完全可复现构建。

本地已有 RootHide Theos 时：在本目录运行 `make package FINALPACKAGE=1`。

## 安装与启用

1. 在 Sileo 中安装 `.deb` 所需依赖：PreferenceLoader、libSandy、Relaxin 环境的注入框架。
2. 本包声明与 `com.benja.globaltint`、`com.liuf.color` 冲突，安装管理器会要求处理冲突。不要让多个系统改色插件同时生效。
3. 按 Relaxin 的方式开启目标 App 的插件注入，先测试设置 App 和一个普通 App。
4. 打开 **设置 → Chroma Palette → 启用系统配色**，在组件页面勾选需要修改的项。
5. 状态栏/控制中心还需开启 **系统界面总开关** 和各自组件开关。首次安装动态库后按包管理器提示重新载入 SpringBoard；仅修改普通颜色时通常无需 respring。

配置保存在独立域 `com.benja.chromapalette`。配置文件在移动用户的系统 Preferences 路径；加载 libSandy 等越狱文件时用 `jbroot()` 动态定位，不硬编码 `/var/jb`。

## 实现边界

- 对组件属性和 UIKit appearance 做局部变换，不全局替换 `UIColor`、`CGColor`、`UIView` 或 `CALayer` 的颜色解析。
- 普通组件与 SpringBoard 适配使用两个独立动态库；系统库只注册具体状态栏/控制中心类。
- 保存被替换属性的原值，接收宿主后续 setter 更新，关闭时尝试恢复；动态自绘、图片、SwiftUI 自有渲染和复杂状态配置仍需逐项验证。键盘渲染缓存可能要重开应用才能完全恢复。
- 现代导航栏/工具栏/标签栏覆盖 standard、scroll-edge、compact 等外观，并保留未指定的属性。
- 列表支持传统标签以及标准 `UIListContentConfiguration`；自定义内容配置不覆盖。
- 所有私有类/selector 先检查存在性及方法类型；不使用固定 ivar 偏移、未经检查的 KVC 或强制加载私有框架。缺少接口时跳过，并以 `[ChromaPalette]` 前缀记录日志。
- Runtime header 资料并非这台 iOS 17.1.1 的实机转储。类存在不等于渲染路径命中；具体颜色效果以实机为准。
- 键盘按键底色通过 `UIKBRenderFactory` 返回的 traits 副本设置 `UIKBColorGradient`。不修改输入事件、按键文字或密码内容；不读取、不记录输入文本。第三方键盘与单独键盘扩展进程不在本版注入范围。
- 控制中心不同模块有不同绘制路径，本版不是对所有模块和自绘图标的保证。状态栏电池自定义色可能覆盖原来的充电、低电量提示色，电池颜色默认不启用。
- UISwitch 关闭轨道使用自身底层的圆角色层；系统内部不透明轨道可能遮住它。

## 真机验收

请记录每项结果，避免以某个 App 的成功代表全系统成功：

| 测试 | 预期 | 当前 |
|---|---|---|
| 设置显示并保存，重开设置 | 颜色、开关保留 | 待真机 |
| Safari / App Store 或普通 App | 注入并读取到相同配置 | 待真机 |
| 普通标题、大标题、滚动边缘导航栏 | 三种状态按所选颜色显示 | 待真机 |
| 列表滚动与 cell 复用 | 不串色、不丢内容 | 待真机 |
| 切换开关、滑块拖动 | 交互正常，颜色项独立 | 待真机 |
| 浅色/深色切换 | 对应配色同步，文字可读 | 待真机 |
| App 自行设置新 appearance 后 | 更新仍可改色、关闭能恢复 | 待真机 |
| 关闭单项、组件、总开关/排除 App | 属性恢复；必要时重开 App 清缓存 | 待真机 |
| 键盘中文/英文、弹出/收起 | 背景与按键底色生效、输入正常 | 待真机 |
| 锁屏/桌面/App 状态栏 | 文字、信号、电池分别测试 | 待真机 |
| 控制中心展开/收起、亮度/音量拖动 | 模块颜色独立、无卡死 | 待真机 |
| 进入后台再回前台 | 设置保持、无明显额外卡顿 | 待真机 |

出现单个 App 异常先通过 Relaxin 关闭该 App 注入；出现 SpringBoard 异常使用 Relaxin 的禁用插件/安全模式恢复，再由 Sileo 卸载本包。不要在本插件设置失效时反复重启已启用的实验模块。

上游依据与原包分析见 [ANALYSIS.zh-CN.md](ANALYSIS.zh-CN.md)。
