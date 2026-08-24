# GlobalTint Changelog

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
