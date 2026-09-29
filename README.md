# MouseDragFix

A Mac Mouse Fix-style mouse enhancer for **macOS 27**, written because Mac Mouse Fix 3.0.8's
"Spaces & Mission Control" click-and-drag stopped working there
([noah-nuebling/mac-mouse-fix#1871](https://github.com/noah-nuebling/mac-mouse-fix/issues/1871)).

## Quick start

1. Download the latest zip from [Releases](https://github.com/channelramble/MouseDragFix/releases),
   unzip it, and move **MouseDragFix** to your Applications folder.
2. The first time, right-click the app and choose **Open**, then **Open** again (it isn't notarized).
3. Allow **Accessibility** access when asked: System Settings › Privacy & Security › Accessibility,
   turn on MouseDragFix. It starts working by itself a couple of seconds later.
4. Try it: hold **Button 4** (usually the rear side button) and drag left or right to switch Desktops,
   or hold **Button 5** and drag to scroll.

MouseDragFix lives in the menu bar as a mouse icon. The **Guide** tab in its settings shows exactly what
each button does right now, with tips and fixes for common problems. Anything you don't set up keeps
working as before.

## Features

**Buttons** (middle button and buttons 4–8, each configurable in Settings → Buttons)
- Click, Double Click and Hold actions: Nothing, Normal click, Middle Click, Back, Forward,
  Mission Control, App Exposé, Show Desktop, Launchpad/Apps, Move left/right a Space, Look Up,
  Smart Zoom, Spotlight, Notification Center, App Switcher, or any recorded keyboard shortcut.
- Click and Drag: **Spaces & Mission Control** (a real three-finger swipe that follows the pointer,
  drag up for Mission Control, down for App Exposé) or **Scroll & Navigate** (trackpad-style
  drag scrolling: Mac Mouse Fix's 50 ms linear smoothing animator, which drains rather than flushes on
  release, then coasts on its drag curve from the speed the content was already moving at).
- Click and Scroll (hold the button, turn the wheel): Zoom, Rotate, Switch Spaces, Swift scroll,
  Precise scroll, Horizontal scroll, App Switcher.

**Scrolling** (mouse wheels only; trackpads and Magic Mouse are never touched)
- Mac Mouse Fix's scroll model: tick-speed based acceleration (Medium: 60 px per notch when slow,
  120 px when spinning fast), fast-scroll speedup after three consecutive swipes, and its animator
  (a 110–180 ms linear step per notch plus an inertia tail; High smoothness adds trackpad momentum).
  Off / Regular / High smoothness, Low / Medium / High speed, reverse direction. Defaults are Mac Mouse
  Fix's stock High smoothness (trackpad simulation with momentum) at Medium speed.
- Modifier keys: ⇧ horizontal, ⌥ precise, ⌃ swift, ⌘ zoom (real pinch gesture).

Chromium browsers (Chrome, Brave, Edge, Vivaldi, Opera, Arc) ignore a large amount of pinch before
they start zooming, so the first event of each gesture gets a compensating kick when the pointer is
over one of them, the same way Mac Mouse Fix does it.

**Pointer**
- Speed and acceleration per mouse (acceleration 0 = linear), applied through the HID event
  system exactly like Mac Mouse Fix, restored when you quit. Off by default ("Use macOS pointer settings").

**General**: enable/disable, launch at login, freeze pointer during drags, Spaces natural direction and drag scale.

**Guide**: a plain-language summary of what your mouse does right now, which button is which, and fixes
for common problems. Every setting also explains itself underneath, and hovering shows a short tip.

Defaults mirror the common Mac Mouse Fix setup: Button 4 click = Back, Button 4 drag = Spaces & Mission
Control, Button 4 + wheel = Switch Spaces, Button 5 drag = Scroll & Navigate, Button 5 + wheel = Zoom.

## How it works on macOS 27

macOS 27's WindowServer rejects the field-encoded synthetic gesture events that drove Spaces before.
Scroll events carry Mac Mouse Fix's field layout: point deltas hold the pixels and line deltas are
pixels/10 run through a sub-pixelator, so most frames report zero lines. Letting CoreGraphics fill
those in rounds every frame up to a whole line and makes line-driven apps scroll several times too far.

MouseDragFix builds a real `IOHIDEvent` of type DockSwipe (motion, flavor, progress + exit velocity)
and attaches it to a CGEvent with SkyLight's `SLEventSetIOHIDEvent`, which WindowServer still animates
in lockstep with the drag. Discrete actions use the Mission Control symbolic hotkeys (SkyLight
`CGSGetSymbolicHotKeyValue` & co.). If either private API is missing, the app falls back to
hotkey-based Space switching. Scroll output uses phased pixel scroll events (trackpad simulation).

## Install

Download `MouseDragFix-<version>.zip` from the [Releases](https://github.com/channelramble/MouseDragFix/releases)
page, unzip, and move `MouseDragFix.app` to `/Applications`. The app is signed with an Apple
Development certificate and the hardened runtime but is **not notarized**, so on first launch
right-click the app → **Open** → **Open** (or allow it under System Settings → Privacy & Security).
Then grant **Accessibility** when prompted; the app starts listening automatically.

## Troubleshooting

| Problem | Fix |
|---|---|
| Nothing happens at all | Check that MouseDragFix is on in System Settings › Privacy & Security › Accessibility. After an update, select it, remove it with **−**, open MouseDragFix again and allow it once more. |
| A button stopped doing its usual job | Its Click is probably set to **Nothing**. In Settings › Buttons, set it to **Normal click (no change)**. Button 5 is often the Forward button. |
| A button does two things at once | Another mouse app (Mac Mouse Fix, Logi Options+, …) handles the same button. Turn it off there, or quit that app. |
| Switching Desktops does nothing | You need at least two Desktops. Open Mission Control and click **+** at the top right. |
| Zoom doesn't work in an app | Zoom acts like a trackpad pinch, so it only works in apps that support pinch-to-zoom. |
| Pages bounce at the end | That's the trackpad feel of **High** smoothness. Choose **Regular** in Settings › Scrolling. |

To pause everything without quitting, turn off **Enable MouseDragFix** in the menu bar. Quitting puts
your mouse back to normal too.

## Build from source

```bash
./build.sh --install
```

Builds `build/MouseDragFix.app` with `swiftc` (no Xcode project; falls back to the Command Line Tools
toolchain if Xcode's license is not accepted), signs it with your Apple Development identity if one
exists (hardened runtime), copies it to `/Applications`, and launches it. `./build.sh --release`
produces the zip archive published on the Releases page.

## Using it alongside Mac Mouse Fix

Turn off Mac Mouse Fix's **Buttons** and **Scrolling** switches (menu-bar icon) or quit it, so the two
apps don't both act on the same input. MouseDragFix inserts its event tap ahead of Mac Mouse Fix's and
re-inserts it whenever a new Mac Mouse Fix helper process appears (polled every 3 s, since launchd
relaunches the helper without a launch notification).

## Known behaviour

- Using an action whose Mission Control shortcut is **disabled** in System Settings installs an unreachable
  binding and enables it (same as Mac Mouse Fix); real keys are unaffected.
- Back / Forward send ⌘[ and ⌘] rather than a navigation swipe, which covers Safari, Chrome, Brave and Finder.
- Pointer speed/acceleration originals are saved; if the app is killed with SIGKILL, the next launch restores them.

## Debugging

```bash
MDF_DEBUG=1 MDF_DRYRUN=1 build/MouseDragFix.app/Contents/MacOS/MouseDragFix
```

`MDF_DEBUG` logs gesture state to stderr; `MDF_DRYRUN` logs what would be posted instead of posting it.
`MouseDragFix --post missionControl|appExpose|showDesktop|left|right` fires one hotkey and exits.
