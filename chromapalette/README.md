# Chroma Palette 0.1.5

适用于 iPhone 15 Pro Max / iOS 17.1.1 / Relaxin（RootHide）的独立组件配色插件。

## 本版修改

- “通用蓝色强调色”提供一个开关，统一浅色/深色颜色选择和透明度。移除信息、Filza、备忘录的单独强调色页面；旧配置优先继承原按钮文字强调色，保留总开关及应用排除名单。
- 具体 UILabel、UIButton、UIImageView 属性识别系统蓝色语义值及浅深色标准 sRGB 值（允许一个字节的取整差异）。按钮增加只读的状态文字色适配，控件内符号图像补色；不处理任意照片像素、快捷指令彩色卡片和网页内容。
- 导航/工具栏按钮、标签栏选中项、列表索引、普通进度填充优先跟随统一强调色。关闭统一开关后恢复各组件自己的设置。备忘录链接和信息未读标记也使用统一颜色。
- Safari 地址栏加载条按 `_SFFluidProgressView.progressBarFillColor` 单独适配；接口不存在或签名不符时跳过。
- iCleaner 的诊断已证实插件加载于 UID 0，但配置不可读。本版先读取 `jbroot()` 转换后的 mobile 配置路径，再尝试原路径及偏好服务；增加明确 mobile 用户的回退。诊断显示读取来源，补充真实 bundle 标识 `com.ivanobilenchi.icleaner`。
- 不引入 UIView/CALayer 的通用绘制钩子。继续保留主线程合并、属性原值恢复、每属性冲突熔断和有限次数的启动补色。

共有 11 组、29 个颜色项；统一强调色组仅有一个颜色项（浅/深模式），不再逐 App 设置。首次安装总开关关闭；从 schema 2 的旧版升级保留有效配置。

## 使用

GitHub Actions 工作流 `.github/workflows/chromapalette.yml` 构建原生 RootHide 安装包，架构标识 `iphoneos-arm64e`，包含 arm64/arm64e 二进制。

下载本次 `ChromaPalette-RootHide-运行编号` 产物，解压并安装 `com.benja.chromapalette_0.1.5_iphoneos-arm64e.deb`。按安装管理器提示重新载入 SpringBoard，在设置中打开“通用蓝色强调色”、选择颜色，然后彻底关闭并重开相关 App。依赖 PreferenceLoader、libSandy 和注入框架。

iCleaner 重开后，“配置读取诊断”中的最新记录应显示 0.1.5、配置可读“是”、总开关“开”，以及实际读取来源。时间必须对应本次打开，旧记录不代表当前已加载。诊断只写本地加载状态，不采集页面内容。

## 保留和边界

保留导航栏、工具栏、列表、列表项、开关轨道、滑块、标签栏、进度条、电池填充和控制中心开启色。键盘、开关圆形滑钮、其他状态栏颜色、控制中心普通模块/亮度音量填充以及 HEX 输入入口均不恢复。设置图标继续使用用户提供的 Spectrum.png。

通用表示共用设置和标准控件适配，并非能改写所有自绘或已烘焙在图片中的蓝色。Filza 小箭头、快捷指令按钮、Safari 私有接口和 iCleaner 读取路径需本次真机复测。健康图表、照片、彩色卡片及红色警告颜色不通过全局像素替换处理。

## 验证

本地检查设置组、颜色引用、已删除选项及资源。CI 运行实际配置迁移、配置文件载荷识别、标准蓝色识别和属性更新回归，包含重复 10000 次输入的冲突熔断、原值恢复和链接属性保留；随后编译并校验包内文件及两种 CPU 架构。编译成功不等于真机界面已验证。

路径依据：[Relaxin cfprefsd 路径重定向](https://github.com/owngoal-dev/Relaxin/blob/main/Vendor/Dopamine/BaseBin/roothidehooks/cfprefsd.m)、[RootHide 接口](https://github.com/roothide/Developer/blob/main/interface.md)。Safari 控件依据：[运行时头文件](https://github.com/nst/iOS-Runtime-Headers/blob/master/Frameworks/SafariServices.framework/_SFFluidProgressView.h)；头文件不等于用户手机实时导出。
