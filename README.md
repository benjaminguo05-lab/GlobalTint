# GlobalTint 0.4.7 — RootHide / iOS 17

GlobalTint is an **app-only** UIKit color tweak for Relaxin / RootHide. Version 0.4.7 keeps the hard SpringBoard quarantine introduced in 0.4.2 and upgrades the existing blue-compatibility path into a multi-layer color interception engine.

## Safety boundary

The package is split into two dylibs:

- `GlobalTintLoader.dylib`: tiny C loader. It rejects SpringBoard, `.appex` processes and non-`.app` processes before loading the UIKit core.
- `GlobalTintCore.dylib`: UIKit / Logos implementation. Its MobileLoader filter is intentionally impossible and it is only `dlopen`'d by the loader inside eligible full apps.

The core constructor checks SpringBoard again before preferences or hooks are initialized. **0.4.7 still does not support SpringBoard/System UI.**

## Existing 0.4.6 features retained

- Global accent color
- Per-App accent colors
- Per-App exclusions
- Per-component enable/disable rules
- Per-component colors
- Switch / slider / progress / segmented / page indicator / refresh control colors
- Navigation bar / tab bar / toolbar / search bar colors
- Tab-bar notification badge background and number colors
- Local configuration save / restore / delete
- Floating `GT` UI inspector

## 0.4.7 multi-layer blue engine

The existing preference key `ForceResolvedBlue` is retained so 0.4.6 backups remain compatible. In Settings it is shown as **“多层蓝色改色增强”**.

When enabled, colors close to the Apple/system-blue family are intercepted at several stages:

1. `+[UIColor systemBlueColor]`
2. `-[UIColor resolvedColorWithTraitCollection:]`
3. Private dynamic UIColor subclasses such as `UIDynamicColor`, `UIDynamicCatalogSystemColor`, `UIDeviceRGBColor`, and `UICGColor`
4. Dynamic UIColor `CGColor`
5. `-[UIView setTintColor:]`
6. `-[UIView setBackgroundColor:]`
7. `-[UILabel setTextColor:]`
8. `-[CALayer setBackgroundColor:]`

The matcher uses tolerant RGBA comparisons (rather than exact equality) plus a conservative blue hue/saturation fallback. Semantic red/green/orange/yellow are deliberately left untouched in 0.4.7.

UIColor/CGColor conversion has a thread-local re-entry guard so obtaining a replacement `CGColor` cannot recursively enter the same hook forever. Original view/layer background colors are remembered and restored when the enhanced engine is disabled.

Colors explicitly configured by GlobalTint (global, per-App, or per-component) are excluded from the generic re-processing path so a user-selected blue output is not unexpectedly recolored again.

## Environment

Designed for:

- Relaxin jailbreak
- RootHide architecture
- iOS 17.x
- arm64 / arm64e, including iPhone 15 Pro / Pro Max

Device packages required:

- PreferenceLoader
- Cephei (`ws.hbang.common`, RootHide build)
- libSandy (`com.opa334.libsandy`)
- RootHide-compatible MobileSubstrate / tweak loader

## Build

Use RootHide Theos:

```bash
export THEOS="$HOME/theos"
make clean
make package FINALPACKAGE=1
```

The resulting package is under `packages/` and uses architecture `iphoneos-arm64e`.

## Install / test

Install the `.deb` with Sileo, then open:

```text
设置 -> Global Tint
```

RootHide / Relaxin does not inject ordinary third-party Apps automatically. Enable tweak injection for the Apps you want to test in the jailbreak App List.

Recommended first test order:

1. Settings
2. Safari
3. App Store
4. One third-party App

Do **not** use SpringBoard as a test target; the loader intentionally refuses it.

For ordinary components, leave **“多层蓝色改色增强”** off first. Turn it on only when a page still contains fixed system-blue / resolved-blue elements that the normal component rules miss. If one App behaves abnormally, disable the option or exclude that App.

## RootHide path rule

Do not hard-code `/var/jb`. Runtime access to jailbreak paths must continue to use RootHide-compatible APIs such as `jbroot(...)` where needed.
