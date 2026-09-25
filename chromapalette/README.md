# iOS全局改色 0.1.6

适用于 iPhone 15 Pro Max / iOS 17.1.1 / Relaxin（RootHide）。原 Chroma Palette 的升级版本；包标识和配置域保留，设置入口及页面名称改为“iOS全局改色”，继续使用 Spectrum 图标。

## 本次修改

- 完全删除“列表视图”“列表项”两组设置及其背景、文字、分隔线、选中背景、图标适配。升级后忽略旧列表配色键。通用强调色仍可处理列表内的蓝色操作文字，不再将普通列表整块换色。
- 移除旧列表代码后，不再由关闭的列表组件对标签属性执行原色恢复，避免覆盖通用强调色。
- 对 Filza 4.0.1-4 官方包作静态检查，确认 `ShortenSortButton.updateLabels` 和 `ButtonsGroup.initWithFrame:` 将固定蓝色传入 `ThemeManager.imageWithName:withMaskColor:` 生成图标。仅在 Filza 中拦截该明确方法的蓝色遮罩参数，在其生成图像前应用通用强调色；不扫描照片或修改全局图像工厂。
- Filza 设置页使用 QuickDialog，补充 `QAppearance` 的启用值、输入文字、操作色及 `ThemeManager` 系统/链接色的只读适配。只替换匹配的蓝色，保留其他原色。
- Filza 的导航、工具栏、底部标签栏及强调色按系统浅深色选择，避免局部深色 trait 把浅色界面的底栏涂为深色。外观变化时使旧转换失效，但不重置冲突写入限额。

现有 9 组、20 个颜色项。通用强调色保持一个开关和浅/深两套颜色选择；没有恢复按 App 的设置页。保留 0.1.5 的 iCleaner mobile 配置路径修复和 Safari 加载条适配。

## 安装和复测

从本次 GitHub Actions 的 `ChromaPalette-RootHide-运行编号` 产物解压，安装 `com.benja.chromapalette_0.1.6_iphoneos-arm64e.deb`。按安装管理器提示重新载入 SpringBoard，彻底关闭后重新打开 Filza。原包标识和产物前缀用于兼容升级；设置中显示“iOS全局改色”。

确认设置入口名称、已移除两组列表选项；检查 Filza 设置页右侧蓝色值、排序上下箭头及右侧折叠箭头。箭头可能在初始化时缓存，选择新颜色后重开 Filza。分别在系统浅色和深色下检查底栏是否选用对应配色。若自己在浅色颜色项中选了深色，底栏仍会按所选颜色显示。

## 验证与边界

CI 校验设置与颜色引用、已删除的列表适配、设置图标及安装包；运行配置迁移、标准蓝色识别、属性恢复及 10000 次重复输入的冲突回归，再编译并检查 arm64/arm64e 架构。构建通过不能替代真机结果。

不增加 UIView/CALayer 通用绘制钩子。Filza 适配在应用标识和 Objective-C 方法签名检查通过后才安装，其他应用不注册这些 Filza 方法。

静态检查使用 [TIGI 官方下载目录](https://www.tigisoftware.com/download/filza.php) 的 Filza 4.0.1-4 安装包；该安装包及反汇编仅留在本地排查目录，不随插件发布。用户手机上的主题插件可能另行改写控件，仍需真机确认。
