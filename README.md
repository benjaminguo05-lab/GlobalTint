# GlobalTint

A conservative V0.1 UIKit global accent/tint tweak for **Relaxin / RootHide**.

## What V0.1 changes

- `UIWindow.tintColor`
- `UISwitch.onTintColor`
- `UISlider.minimumTrackTintColor`
- `UIProgressView.progressTintColor`
- `UISegmentedControl.selectedSegmentTintColor`
- `UIPageControl.currentPageIndicatorTintColor`
- `UIRefreshControl.tintColor`
- `UINavigationBar.tintColor`
- `UITabBar.tintColor`
- `UIToolbar.tintColor`
- `UISearchBar.tintColor`

It intentionally does **not** replace `+[UIColor systemBlueColor]`, semantic text colors,
background colors, or SwiftUI internals. That is planned for later versions because those
hooks have a much larger compatibility surface.

## Environment

Designed for:

- Relaxin jailbreak
- RootHide architecture
- iOS 17.x
- arm64e devices such as iPhone 15 Pro / Pro Max

## 1. Install RootHide Theos

On macOS:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/roothide/theos/master/bin/install-theos)"
```

Set `THEOS` if your shell does not already have it:

```bash
export THEOS="$HOME/theos"
```

## 2. Device dependencies

Install these from Sileo before installing GlobalTint:

- PreferenceLoader
- Cephei (`ws.hbang.common`, RootHide build)
- MobileSubstrate-compatible tweak loader provided by the RootHide environment

The settings page uses iOS 17's native `UIColorPickerViewController`, so Alderis is not required.

## 3. Build

From the project directory:

```bash
make clean
make package FINALPACKAGE=1
```

The package will appear under:

```text
packages/
```

and should be an `iphoneos-arm64e` `.deb`.

## 4. Install

Transfer the `.deb` to the iPhone and open it with Sileo, or use your normal RootHide
package-install workflow.

After installation, reopen Settings and enter:

```text
Settings -> Global Tint
```

## 5. Third-party apps

RootHide does not inject tweaks into third-party apps by default.

Open the RootHide / Relaxin bootstrap App List and enable tweak injection only for the
apps you want to test. Start with Settings / Safari and then enable third-party apps one
at a time.

## 6. Recommended first test

Use a visible color such as:

```text
#92C5C6
```

Test in this order:

1. Settings
2. Safari
3. App Store
4. SpringBoard
5. One third-party app

Check:

- navigation buttons
- tab bar selected item
- switches
- sliders
- segmented controls
- links / template-image tint that inherit from the window

## 7. Important limitation

V0.1 is UIKit-focused.

SwiftUI views that explicitly use:

```swift
.tint(...)
.foregroundStyle(...)
```

may not follow `UIWindow.tintColor`.

Likewise, Apple private SpringBoard / Control Center components may use their own
semantic colors and will need dedicated iOS 17 hooks in a later module.

## 8. Recovery if a tweak causes UI instability

Because Relaxin is semi-untethered, a normal reboot returns the device to a non-jailbroken
state until the jailbreak is run again. Keep testing conservative hooks first, and only
then add private SpringBoard classes.

Do not hard-code `/var/jb` paths in future RootHide modules. If a future version needs
to access jailbreak files, use RootHide's `jbroot(...)` API.

## Project layout

```text
GlobalTint/
├── Makefile
├── control
├── GlobalTint.plist
├── Tweak.xm
├── README.md
├── globaltintprefs/
│   ├── Makefile
│   ├── GTListController.h
│   ├── GTListController.m
│   └── Resources/
│       ├── Info.plist
│       └── Root.plist
└── layout/
    └── Library/
        └── PreferenceLoader/
            └── Preferences/
                └── GlobalTint.plist
```

## Next modules

Recommended order:

1. V0.2 - per-app exclusions and per-component switches
2. V0.3 - dedicated SpringBoard accent hooks
3. V0.4 - Control Center / Lock Screen
4. V0.5 - selected semantic system colors
5. V0.6 - SwiftUI investigation / bridge handling



## No macOS? Build on GitHub Actions

For arm64e system-process tweaks, using a macOS GitHub Actions runner is the easiest
option if your development computer is Windows.

This project includes:

```text
.github/workflows/build.yml
```

### Steps

1. Create a GitHub repository.
2. Upload the **contents of the `GlobalTint` folder** to the repository root.
3. Open the repository's **Actions** tab.
4. Select **Build GlobalTint**.
5. Click **Run workflow**.
6. When the run finishes, open the run and download the artifact named:
   `GlobalTint-RootHide`.
7. Extract the artifact ZIP. Inside is the compiled `.deb`.
8. Send the `.deb` to the iPhone and install it with Sileo.

Every push to `main` or `master` also triggers a build automatically.

If the workflow fails, copy the complete output of the red **Build RootHide package**
step and send it back for diagnosis.


## V0.2

V0.2 adds three major features:

### 1. App exclusions

In Settings -> Global Tint -> App 排除, enter bundle identifiers separated by commas.

Examples:

```text
com.tencent.xin, com.apple.mobilesafari
```

When the current process bundle identifier is in this list, GlobalTint restores any
remembered colors it changed and stops applying its UIKit tint rules in that process.

This exclusion is separate from RootHide's App List: the app still needs tweak injection
enabled before GlobalTint can run there at all.

### 2. Per-component enable switches

V0.2 has independent switches for Window Tint, Switch, Slider, ProgressView,
SegmentedControl, PageControl, RefreshControl, NavigationBar, TabBar, Toolbar and
SearchBar.

`ApplyControls` and `ApplyBars` remain as master switches for compatibility with V0.1.x.

### 3. Per-component colors

Keep `启用组件独立颜色` off to make every component follow the main accent color.

Turn it on to use individual component colors. A component whose individual color has
not been set still follows the main accent color.

Use `清除全部组件独立颜色` to return every component to main-color inheritance.

### Upgrade

V0.2 can be installed over V0.1.6. Existing `Enabled`, `AccentColor`,
`ApplyWindowTint`, `ApplyControls`, and `ApplyBars` preferences are retained.


## V0.3.0

V0.3.0 adds per-App accent profiles. A Bundle ID can be assigned its own accent
color while all Apps without a profile continue to use the global accent.
Explicit per-component colors still take priority when separate component
colors are enabled.
