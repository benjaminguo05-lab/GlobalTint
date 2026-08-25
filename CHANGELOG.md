# GlobalTint Changelog

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
