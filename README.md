# MouseDragFix

A Mac Mouse Fix-style mouse enhancer for **macOS 27**, written because Mac Mouse Fix 3.0.8's
"Spaces & Mission Control" click-and-drag stopped working there
([noah-nuebling/mac-mouse-fix#1871](https://github.com/noah-nuebling/mac-mouse-fix/issues/1871)).

## Features

**Buttons** (middle button and buttons 4–8, each configurable in Settings → Buttons)
- Click, Double Click and Hold actions: Nothing, pass through, Middle Click, Back, Forward,
  Mission Control, App Exposé, Show Desktop, Launchpad/Apps, Move left/right a Space, Look Up,
  Smart Zoom, Spotlight, Notification Center, App Switcher, or any recorded keyboard shortcut.
- Click and Drag: **Spaces & Mission Control** (a real three-finger swipe that follows the pointer,
  drag up for Mission Control, down for App Exposé) or **Scroll & Navigate** (trackpad-style
  drag scrolling with momentum, works for swipe navigation in Safari).
- Click and Scroll (hold the button, turn the wheel): Zoom, Rotate, Switch Spaces, Swift scroll,
  Precise scroll, Horizontal scroll, App Switcher.

**Scrolling** (mouse wheels only; trackpads and Magic Mouse are never touched)
- Mac Mouse Fix's scroll model: tick-speed based acceleration (Medium: 60 px per notch when slow,
  120 px when spinning fast), fast-scroll speedup after three consecutive swipes, and its animator
  (a 110–180 ms linear step per notch plus an inertia tail; High smoothness adds trackpad momentum).
  Off / Regular / High smoothness, Low / Medium / High speed, reverse direction.
- Modifier keys: ⇧ horizontal, ⌥ precise, ⌃ swift, ⌘ zoom (pinch gesture).

**Pointer**
- Speed and acceleration per mouse (acceleration 0 = linear), applied through the HID event
  system exactly like Mac Mouse Fix, restored when you quit. Off by default ("Use macOS pointer settings").

**General**: enable/disable, launch at login, freeze pointer during drags, Spaces natural direction and drag scale.

Defaults mirror the common Mac Mouse Fix setup: Button 4 click = Back, Button 4 drag = Spaces & Mission
Control, Button 4 + wheel = Switch Spaces, Button 5 drag = Scroll & Navigate, Button 5 + wheel = Zoom.

## How it works on macOS 27

macOS 27's WindowServer rejects the field-encoded synthetic gesture events that drove Spaces before.
MouseDragFix builds a real `IOHIDEvent` of type DockSwipe (motion, flavor, progress + exit velocity)
and attaches it to a CGEvent with SkyLight's `SLEventSetIOHIDEvent`, which WindowServer still animates
in lockstep with the drag. Discrete actions use the Mission Control symbolic hotkeys (SkyLight
`CGSGetSymbolicHotKeyValue` & co.). If either private API is missing, the app falls back to
hotkey-based Space switching. Scroll output uses phased pixel scroll events (trackpad simulation).

## Build and install

```bash
./build.sh --install
```

Builds `build/MouseDragFix.app` with `swiftc` (no Xcode project; falls back to the Command Line Tools
toolchain if Xcode's license is not accepted), signs it with your Apple Development identity if one
exists, copies it to `/Applications`, and launches it. Grant **Accessibility** when prompted.

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
