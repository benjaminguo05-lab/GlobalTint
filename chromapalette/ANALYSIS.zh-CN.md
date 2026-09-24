# 原包静态分析与新实现依据

## 输入与分析范围

用户提供的 `liuf系统改色绿色3.0(2).deb`，14,578 字节。

SHA256：`1ec60c274ade3198310bdcb5e1803031b2cc750f5af697ba450a2b5031cb3370`。

仅做解包、Mach-O 结构检查与 arm64 反汇编；未在手机或电脑执行原插件。包内文字只作为分析数据，不作为用户指令。新项目不包含原包的动态库。

## 已直接确认的结构

- Debian ar 容器，`control.tar.zst` 和 `data.tar.zst`。
- 包标识 `com.liuf.color`，版本 `3.0.0`，安装架构 `iphoneos-arm64e`。
- 依赖 `mobilesubstrate`，预依赖 `rootless-compat (>= 0.9)`。
- 主动态库 `全局颜色调整.dylib`，含 arm64 与 arm64e（CPU subtype `0x80000002`）切片。
- 过滤配置仅包含 `com.apple.UIKit`。
- 依赖 UIKit、Foundation、CoreFoundation、libobjc 和 `@rpath/CydiaSubstrate.framework/CydiaSubstrate`。
- 主库 rpath 中存在 `@loader_path/.jbroot/Library/Frameworks` 和 `@loader_path/.jbroot/usr/lib`。
- `var/mobile/Library/pkgmirror/` 中保留原 `iphoneos-arm64` 包信息和镜像动态库，镜像仍含 `/var/jb` rpath。结合 `rootless-compat` 依赖，可判断这是经过兼容处理的 rootless 包，而非证明其源码采用原生 RootHide API。
- 没有 PreferenceBundle、PreferenceLoader 设置入口或独立颜色配置文件。

## 改色机制的证据

保留的 C++ 符号包括：

| 函数（去掉 mangling） | arm64 虚拟地址 |
|---|---|
| `colorFromHex(unsigned int)` | `0x42c4` |
| `isColorMatched(UIColor *, double, double, double, double)` | `0x4308` |
| `replaceColorIfMatched(UIColor *)` | `0x43c4` |
| `replaceBlueColor(UIColor *)` | `0x5d60` |
| `replaceRedColor(UIColor *)` | `0x5e30` |
| `replaceYellowColor(UIColor *)` | `0x5f08` |
| `replaceGreenColor(UIColor *)` | `0x5fd8` |
| `replaceOrangeColor(UIColor *)` | `0x60b8` |

`isColorMatched` 的指令先调用 `getRed:green:blue:alpha:`；成功后计算 RGBA 与参考值的绝对差，四个分量分别使用严格小于 `0.08 / 0.07 / 0.08 / 0.1` 的阈值。不是单个十六进制常量的精确相等判断，也不是只设置窗口 tint。

初始化代码中存在大量 `MSHookMessageEx` 调用。字符串、selector 表与调用参数可对应到 `CALayer`、`UIView`、`UIImageView`、`UIButton`、`UILabel`、`UISwitch`、多个私有动态 UIColor 子类以及 UIColor 系统色方法。入口覆盖背景色、tint、文字、动态解析和 CGColor 取得过程；另外出现 `TPBadgeView`。

这能解释同一种颜色跨多个系统组件改变的现象：它追踪颜色值在不同阶段的转换，而不是分别识别“这是导航栏”或“这是控制中心”。广覆盖也意味着失去组件上下文；同一原色被不同控件共用时，难以通过这一层可靠实现各控件独立选色。

**未做出的结论：** 未恢复完整原源码；未证明全部 hook 在 iOS 17.1.1 上生效；未由包名推定所有替换目标都是相同绿色；未把静态分析当作运行稳定性证明。

## 新项目的实现选择

新引擎直接按照控件角色取色。普通控件用各自属性；导航栏、工具栏、标签栏使用 appearance 副本；列表内容使用对应配置；私有系统界面用限定类的适配器。不复用原包或 GlobalTint 的全局 UIColor/CGColor 匹配与替换链。

旧项目只参考其 CHANGELOG 中记录的两项测试结论：

1. 普通 App 的过滤/注入曾存在差异，采用其记录中验证过的 `com.apple.Security` 广匹配后，再检查进程是不是完整 App。
2. 沙盒 App 通过 libSandy + 完整路径 NSUserDefaults 读取配置曾得到验证。该做法也有 libSandy 作者文档支持。

旧项目对 SpringBoard 的隔离不能作为新系统模块的通过记录；新系统库仅注册具体状态栏/控制中心类，并默认关闭颜色功能。

## 上游依据

- [Relaxin 仓库](https://github.com/owngoal-dev/Relaxin)：公开说明采用 RootHide。
- [Relaxin bootstrap 下载脚本](https://github.com/owngoal-dev/Relaxin/blob/main/DevKit/Helpers/download-bootstrap.sh)：bootstrap 1900 来自 RootHide Dopamine2，固定来源 revision 并校验 SHA256。
- [Relaxin BaseBin 构建](https://github.com/owngoal-dev/Relaxin/blob/main/DevKit/Helpers/build-basebin-resources.sh)：包含 ElleKit 的 CydiaSubstrate 兼容 framework。
- [RootHide 开发说明](https://github.com/roothide/Developer)：`THEOS_PACKAGE_SCHEME=roothide` 与 `jbroot()` 路径解析。
- [libSandy 原作者文档](https://github.com/opa334/libSandy#accessing-preferences)：完整 Preferences 路径的 NSUserDefaults 与对应文件沙盒授权。
- [旧 GlobalTint 测试与修改记录](https://github.com/benjaminguo05-lab/GlobalTint/blob/main/CHANGELOG.md)：只作为历史记录，未在本次重现。
- [RuntimeBrowser 导出的 UIKitCore headers](https://github.com/nst/iOS-Runtime-Headers/tree/master/PrivateFrameworks/UIKitCore.framework)：UIKBRenderFactory、UIKBRenderTraits、UIKBColorGradient、状态栏信号和电池类的接口依据。
- [ControlCenterUIKit headers](https://github.com/nst/iOS-Runtime-Headers/tree/master/PrivateFrameworks/ControlCenterUIKit.framework)：CCUIRoundButton、CCUIButtonModuleView、CCUIModuleSliderView 的接口依据。

这些 runtime headers 不是本机 iOS 17.1.1 的转储，所以代码在运行时再次检查接口。尚未验证的类路径在 README 中明确列为实验性。
