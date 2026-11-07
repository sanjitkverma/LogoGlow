# LogoGlow

A small macOS app that turns the glowing Apple logo on the back of compatible MacBook Pro displays on or off, with an animated glowing-logo UI.

It flips the `LEBacklightMode` setting in `com.apple.CoreBrightness` (needs admin rights). The first time you toggle, it asks for your password once and installs a narrow sudo rule (`/etc/sudoers.d/logoglow`) so later toggles don't prompt.

## Build

```sh
./build.sh
open build/LogoGlow.app
```

Requires Xcode command line tools and macOS 14+ (Apple silicon).
