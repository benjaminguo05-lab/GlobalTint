# GlobalTint Changelog

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
