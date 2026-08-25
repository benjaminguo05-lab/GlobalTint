# GlobalTint Changelog

## 0.4.6

- Added notification badge customization for ordinary App tab bars.
- New global preferences:
  - `ApplyTabBarBadge` (default OFF)
  - `BadgeBackgroundColor`
  - `BadgeTextColor`
- New per-App color keys:
  - `BadgeBackgroundColor`
  - `BadgeTextColor`
- New per-App switch key:
  - `TabBarBadge`
- Supports both legacy `UITabBarItem.badgeColor` /
  `badgeTextAttributes` and modern `UITabBarAppearance`
  `badgeBackgroundColor` / `badgeTextAttributes`.
- Original badge colors/attributes are remembered and restored when disabled.
- Badge background follows the App/global accent when separate colors are OFF;
  badge text defaults to white.
- Added local configuration backup:
  - Save current configuration
  - Restore saved configuration
  - Delete saved configuration
- A saved configuration contains all GlobalTint runtime settings, App profiles,
  component colors/switches, compatibility settings, and exclusion list.
- Reset-to-default now preserves the saved configuration backup.
- No SpringBoard/System UI hooks were added. The V0.4.2 hard quarantine
  architecture remains unchanged.

## 0.4.5

- Fixed a localization regression introduced while translating V0.4.3/V0.4.4.
- Per-App component-switch INTERNAL keys are restored to the exact identifiers
  expected by the runtime:
  `Window`, `Switch`, `Slider`, `Progress`, `Segmented`, `PageControl`,
  `RefreshControl`, `NavigationBar`, `TabBar`, `Toolbar`, `SearchBar`.
- User-facing labels remain fully Chinese.
- Finished Chinese localization in the App detail page.
- No changes to tweak color logic, libSandy preferences, Loader/Core split, or
  hard SpringBoard quarantine.

## 0.4.4

- Further localized the main Settings page and manual configuration dialogs.
- Replaced developer-facing English UI labels with plain Chinese descriptions:
  - GLOBAL TINT -> 全局设置
  - Enable Global Tint -> 启用全局改色
  - App -> 应用 (in user-facing section names/actions)
  - System Blue -> 系统蓝色
  - Link Color -> 链接颜色
  - Window Tint -> 应用整体强调色
  - Switch -> 开关按钮
  - Slider -> 滑动条 / 音量进度条
  - Progress -> 进度条
  - SegmentedControl -> 分段选择按钮
  - PageControl -> 页面圆点指示器
  - RefreshControl -> 下拉刷新指示器
  - NavigationBar -> 顶部导航栏
  - TabBar -> 底部标签栏
  - Toolbar -> 工具栏
  - SearchBar -> 搜索栏
  - Bar -> 导航栏与工具栏
- `Bundle ID` is retained only where technically necessary and is displayed as
  `应用标识（Bundle ID）`.
- Simplified technical help text so normal users can understand what each
  option changes without knowing UIKit class names.
- No runtime code, preference keys, color precedence, loader/core split, or
  SpringBoard quarantine behavior changed.

## 0.4.3

- User-facing terminology cleanup only; no runtime tint logic changes.
- Replaced UIKit class names in Settings with plain Chinese descriptions:
  - Window -> 应用整体强调色
  - UISwitch -> 开关按钮
  - UISlider -> 滑动条 / 音量进度条
  - UIProgressView -> 进度条
  - UISegmentedControl -> 分段选择按钮
  - UIPageControl -> 页面圆点指示器
  - UIRefreshControl -> 下拉刷新指示器
  - UINavigationBar -> 顶部导航栏
  - UITabBar -> 底部标签栏
  - UIToolbar -> 工具栏
  - UISearchBar -> 搜索栏
- Renamed “组件” wording to the more understandable “界面” in App profile
  sections.
- Kept all preference keys, dictionaries, color precedence, loader/core split,
  and SpringBoard quarantine unchanged from V0.4.2.

## 0.4.2

- Rebuilt GlobalTint around a hard SpringBoard quarantine.
- Split the package into two dylibs:
  - `GlobalTintLoader.dylib`: tiny pure-C loader, broadly filtered.
  - `GlobalTintCore.dylib`: proven V0.3.5 UIKit/Logos implementation.
- The broad loader contains no UIKit, Foundation, Objective-C categories,
  Logos hooks, preference code, or UI inspector implementation.
- Before the core is loaded, the loader checks the executable:
  - rejects `SpringBoard`
  - rejects `.appex` extension processes
  - rejects non-`.app` processes/daemons
- The core has an intentionally impossible MobileLoader filter and therefore
  cannot be automatically injected by Substrate/MobileLoader.
- Eligible full App processes explicitly `dlopen` the core from the same
  DynamicLibraries directory.
- Added a second SpringBoard guard inside the core constructor as defense in
  depth.
- System UI support remains removed.
- App-side functionality is based on the proven V0.3.5 baseline.

## 0.3.5

- Fixed the V0.3.4 Preferences bundle compile failure.
- Root cause: `GTAppDetailController -specifiers` was missing its final
  `return _specifiers;` and closing brace before the App-header cell methods.
- Because of that, Clang parsed `gtSpecifierAtIndexPath:` as if it appeared
  inside `-specifiers`, producing the misleading `undeclared identifier`
  error.
- Restored the method boundary and removed the stray `return _specifiers;`
  block that had been emitted near the end of the file.
- Verified `GTAppListController -specifiers` already had the correct structure.
- No tweak runtime/color behavior changes.

## 0.3.4

- Upgraded the App configuration manager UI.
- Added App icons in the installed-App list.
  - First tries UIKit's system application-icon provider dynamically.
  - Falls back to LaunchServices icon data when available.
  - Generates a local monogram icon if neither source is available.
- Added a persistent search bar that matches both App display names and
  Bundle IDs.
- Apps with any GlobalTint configuration are sorted before unconfigured Apps
  within the User/System sections.
- Added compact per-App status text:
  - `已排除`
  - `主色`
  - component color rule count (`N色`)
  - component switch rule count (`N开关`)
  - `未配置`
- Added an App icon/name header row to each App detail page.
- User App / System App grouping and the configured-but-missing fallback group
  remain intact.
- Tweak runtime logic is unchanged from V0.3.2/V0.3.3.

## 0.3.3

- Added a dedicated installed-App configuration manager.
- The Preferences bundle dynamically reads installed applications through
  LaunchServices (`LSApplicationWorkspace`) without linking private headers.
- Apps are separated into user and system groups when LaunchServices provides
  application-type metadata.
- Configured Bundle IDs that are not returned by LaunchServices are still
  shown in a fallback group.
- Added a per-App detail page with:
  - App exclusion toggle
  - App accent color
  - all supported per-App component colors
  - all supported tri-state per-App component switches
  - clear controls for each rule family
  - one-tap reset of the App back to global configuration
- Existing manual Bundle ID configuration remains available as an advanced
  fallback.
- No changes to the V0.3.2 tweak runtime/color precedence.

## 0.3.2

- Added per-App component enable/disable overrides.
- New `EnableAppComponentSwitchOverrides` master preference, enabled by default.
- New `AppComponentSwitchOverrides` nested dictionary:
  `bundleID -> componentKey -> bool`.
- Supported per-App switch keys:
  - Window
  - Switch
  - Slider
  - Progress
  - Segmented
  - PageControl
  - RefreshControl
  - NavigationBar
  - TabBar
  - Toolbar
  - SearchBar
- Enable precedence:
  1. `Enabled` and App exclusion remain absolute global gates.
  2. `ApplyControls` / `ApplyBars` remain group-level master gates.
  3. matching per-App component switch override
  4. global individual component switch
- Settings UI can add/update a rule as `强制开启`, `强制关闭`, or `跟随全局`.
- Added rule count, individual deletion, and clear-all controls.
- Existing V0.3.1 per-App component colors and V0.3.0 per-App accent profiles
  remain unchanged.

## 0.3.1

- Added per-App component color overrides.
- New `AppComponentColorOverrides` nested dictionary:
  `bundleID -> componentKey -> #RRGGBB`.
- Supported per-App component keys:
  - Window
  - Switch
  - Slider
  - Progress
  - SegmentedControl
  - PageControl
  - RefreshControl
  - NavigationBar
  - TabBar
  - Toolbar
  - SearchBar
- Color precedence when `UseSeparateColors` is enabled:
  1. per-App component color
  2. global component color
  3. per-App accent color
  4. global accent color
- Added Settings UI to add/update, list/count, delete and clear per-App
  component rules.
- Existing V0.3.0 App accent profiles and V0.2.20 libSandy runtime path remain
  unchanged.

## 0.3.0

- Added per-App accent color profiles.
- New `EnableAppColorOverrides` preference, enabled by default.
- New `AppColorOverrides` dictionary stores `bundleID -> #RRGGBB`.
- Per-App accent becomes the fallback/main accent only for the matching process.
- Color precedence:
  1. explicit component color when component-independent colors are enabled
  2. matching App accent override
  3. global AccentColor
- Added Settings UI to:
  - add or update an App color using a Bundle ID + native UIColorPicker
  - show configured profile count
  - delete individual App profiles
  - clear all App profiles
- Existing exclusions still take priority: excluded Apps receive no GlobalTint
  coloring even if an App accent profile exists.
- App profiles are stored in the existing preferences plist and are available
  to sandboxed Apps through the proven libSandy preference path.

## 0.2.20

- Stable cleanup release after V0.2.19 fixed sandbox preference access.
- Kept the proven runtime architecture:
  - RootHide/Relaxin injection
  - broad `com.apple.Security` Substrate filter
  - libSandy preference-file access
  - UIKit component / bar hooks
  - optional per-scene floating `GT` inspector
- Removed the obsolete single-finger long-press inspector implementation.
- Removed the runtime `UIApplication sendEvent:` replacement and private
  UIApplication subclass swizzling used only by that old inspector.
- Removed obsolete touch-tracking associated-object keys and sequence state.
- Removed an unused tweak-side preference identifier constant.
- Cleaned the Settings diagnostics footer so it describes only the current
  floating `GT` inspector workflow.
- No intended changes to tint/color behavior.

## 0.2.19

- Identified the core sandbox preference issue: HBPreferences can return only
  default values inside App Store sandboxed apps even when the tweak itself is
  injected.
- The tweak dylib no longer uses Cephei/HBPreferences at runtime.
- Added a libSandy profile granting access only to
  `/var/mobile/Library/Preferences/com.benja.globaltint.plist`.
- The tweak applies that profile and reads preferences with
  `NSUserDefaults initWithSuiteName:` using the full plist path, following
  libSandy's documented preference-access pattern.
- PreferenceLoader bundle still uses HBPreferences because Settings is not
  affected by the same sandbox limitation.
- Added Darwin-notification reload so preference changes still update injected
  processes live.
- Removed Cephei as a runtime dependency of the tweak dylib itself.
- Added `com.opa334.libsandy` package dependency.

## 0.2.18

- Replaced the restrictive UIKit/Class Substrate filter with the classic
  broad-match `com.apple.Security` bundle filter.
- Relaxin/RootHide App List now remains the primary control over which app
  processes receive tweak injection.
- Added a runtime `%ctor` guard: GlobalTint initializes only when the
  `UIApplication` Objective-C class is present.
- App extensions remain excluded.
- This change targets the observed issue where other tweaks loaded in normal
  apps while GlobalTint only loaded in Settings/Sileo/Filza.

## 0.2.17

- Changed the MobileSubstrate injection filter after testing showed that
  ordinary App Store apps could load other tweaks but did not load GlobalTint.
- Added a `Classes` filter for `UIApplication`, so UIKit/SwiftUI application
  processes can match by the Objective-C application class instead of relying
  only on the legacy `com.apple.UIKit` bundle filter.
- Added explicit bundle matches for:
  - `com.apple.AppStore`
  - `com.apple.mobilesafari`
  - `com.apple.Preferences`
  - `com.apple.springboard`
- Kept `com.apple.UIKit` for compatibility with traditional Substrate loaders.

## 0.2.16

- Fixed the scene-overlay inspector only appearing in Settings.
- Inspector creation no longer depends on a later `UIWindow` hook firing.
- Proactively enumerates every connected `UIWindowScene` and its windows.
- Re-scans when the app becomes active, a window becomes key, or a window
  becomes visible.
- Performs delayed refresh passes at 0.0s, 0.2s, 0.6s, 1.2s and 2.5s after
  activation/initialization so dynamically-created App Store/Safari windows
  are discovered.
- Preference changes now explicitly refresh inspector windows across all scenes.

## 0.2.15

- Fixed V0.2.14 compile failure caused by two obsolete inspector associated-object keys.
- Removed `GTInspectorButtonKey`.
- Removed `GTInspectorOverlayKey`.
- These keys belonged to the V0.2.13 in-window floating inspector and are no longer used by the V0.2.14 scene-overlay inspector.
- Added a static source scan for unused file-scope helper variables/functions before packaging.

## 0.2.14

- Fixed the floating `GT` inspector button only being visible in Settings.
- Inspector UI now lives in its own transparent per-`UIWindowScene` window.
- The inspector window stays above dynamic App Store / Safari content.
- Outside the `GT` button the inspector window passes touches through to the app.
- After tapping `GT`, the window temporarily captures one tap, removes the
  capture layer, then hit-tests the real underlying app window.
- Inspector overlay windows are excluded from GlobalTint's normal window hooks
  to avoid recursion.

## 0.2.13

- Replaced the unreliable long-press/raw-touch inspector workflow with a
  deterministic floating inspector button.
- When `UI 元素检查器` is enabled, eligible app windows show a purple `GT`
  floating button.
- Tap `GT`, then tap the target UI element.
- The transparent capture overlay removes itself before calling `hitTest`, so
  the report describes the original underlying app view.
- Inspector still copies the full report to the clipboard automatically.
- Existing raw-touch hook remains only as a fallback; the floating button is
  now the recommended inspection workflow.

## 0.2.12

- Fixed UI Inspector not firing in App Store / Safari after SpringBoard filtering.
- Replaced the Logos hook on base `UIApplication` with a runtime hook on the
  exact UIApplication class used by the current process.
- Handles private UIApplication subclasses that override `sendEvent:`.
- If `sendEvent:` is inherited, adds an override only to the exact runtime class
  instead of modifying UIApplication globally.
- Inspector behavior remains: single-finger hold for ~0.8 seconds.

## 0.2.11

- Fixed V0.2.10 compile error where `GTInspectorViewIsEligible` was referenced before declaration.
- Added forward declarations for all three inspector eligibility helpers:
  - `GTInspectorProcessIsEligible`
  - `GTInspectorWindowIsEligible`
  - `GTInspectorViewIsEligible`
- No runtime behavior changes from V0.2.10.

## 0.2.10

- Fixed UI Inspector reporting SpringBoard's `UISystemGestureView`.
- Inspector now ignores the `com.apple.springboard` process entirely.
- Ignores `_UISystemGestureWindow`, `UISystemGestureView`, hidden windows and near-transparent windows.
- The next report should come from the actual target process such as `com.apple.AppStore` or `com.apple.mobilesafari`.

## 0.2.9

- Reworked the UI inspector because Window-level `UILongPressGestureRecognizer`
  did not fire reliably in App Store and Safari.
- Inspector now hooks `UIApplication -sendEvent:` and tracks raw `UITouch`
  events directly.
- Activation remains a single-finger hold for 0.8 seconds.
- Moving more than approximately 18 pt cancels inspection.
- The inspector does not consume or cancel the original touch event.

## 0.2.8

- Changed the UI inspector activation gesture from two-finger long press to one-finger long press.
- Inspector hold duration is now 0.8 seconds to reduce accidental activation.
- `cancelsTouchesInView` remains disabled so normal controls are disturbed as little as possible.

## 0.2.7

- Added an on-device UI element inspector for private UIKit / SwiftUI diagnosis.
- Enable `UI 元素检查器`, then two-finger long-press a target element.
- Shows the hit view class, parent view hierarchy, tint/text colors and common layer colors.
- Copies the full inspector report to the clipboard automatically.
- Diagnostic release: existing color behavior is otherwise unchanged from V0.2.6.

## 0.2.6

- Fixed build failure caused by `-Werror,-Wunused-function`.
- Removed the unused `GTMaybeReplaceResolvedBlue` helper.
- No runtime behavior changes from V0.2.5.

## 0.2.5

- Fixed V0.2.4 compile error: `GTShouldApplyBase` was referenced before declaration.
- Added an explicit forward declaration for `GTShouldApplyBase(void)`.
- No runtime behavior changes from V0.2.4.

## 0.2.4

- Injection test confirmed App Store and Safari load GlobalTint correctly.
- Added `强制替换已解析蓝色` compatibility mode.
- Intercepts blue values at `UIView.setTintColor:` and `UILabel.setTextColor:`.
- Intercepts blue results from `UIColor.resolvedColorWithTraitCollection:`.
- Preserves the source alpha while replacing blue with the configured semantic compatibility color.
- Re-applies compatibility coloring to already-existing view hierarchies during preference refresh.
- Attempts to restore remembered tint/text colors when compatibility mode is disabled.

## 0.2.3

- Fixed the `语义蓝兼容色` button doing nothing.
- Added the missing `chooseSemanticBlueColor` action method.
- Added a static selector/action sanity check before packaging this revision.

## 0.2.2

- Added an optional System Blue semantic-color replacement.
- Added an optional Link Color semantic-color replacement.
- Added a separate semantic compatibility color (falls back to main accent).
- Added a 3pt injection-test border for confirming per-app tweak injection.
- Added MobileSafari `BrowserToolbar` compatibility and forces `interactionTintColor` when Toolbar coloring is enabled.

## 0.2.1

- Fixed UITabBar selected item colors in apps that use `UITabBarAppearance`.
- Applies selected icon/title color to stacked, inline and compact-inline item appearances.
- Handles `standardAppearance` and `scrollEdgeAppearance`.
- Handles explicit per-`UITabBarItem` appearances on iOS 15+.
- Re-applies TabBar color if the host app replaces its appearance after startup.
- Restores remembered TabBar appearances when the feature is disabled or the app is excluded.

## 0.2.0

- Added per-app exclusion by Bundle ID.
- Added unified color / per-component color mode.
- Added independent colors for:
  - UIWindow tint
  - UISwitch
  - UISlider
  - UIProgressView
  - UISegmentedControl
  - UIPageControl
  - UIRefreshControl
  - UINavigationBar
  - UITabBar
  - UIToolbar
  - UISearchBar
- Added individual enable switches for every supported component.
- Retained V0.1 `ApplyControls` and `ApplyBars` as master switches for upgrade compatibility.
- Added "clear component colors" and "clear exclusions" actions.
- Preference page is now generated in Objective-C instead of relying on Root.plist loading.
- Excluded apps restore remembered UIKit colors when preferences refresh.

## 0.1.6

- Fixed blank PreferenceBundle page on RootHide/iOS 17 by using code-generated fallback specifiers.
