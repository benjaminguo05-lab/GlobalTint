# GlobalTint Changelog

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
