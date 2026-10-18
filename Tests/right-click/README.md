# Right-click regression

The touch rig's `RIG_POINTER=1` mode leaves the real `InputOverlayView` and `TrackpadSurface` on screen for 90 seconds. The checker uses keyrig's simulator-only virtual mouse to send a primary click, secondary click and a secondary hold longer than the drag threshold over each surface. Each must emit exactly one primary pair and two secondary pairs, with no accidental left-button drag.

Use a private simulator whose name starts with `Sill right-click`, never a simulator used by another task. In one terminal, run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
SILL_TOUCHRIG_SIM='Sill right-click test' SIMCTL_CHILD_RIG_POINTER=1 \
Tests/touchrig/run.sh secondary-click
```

Once that private simulator has booted, run in another terminal:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
python3 Tests/right-click/check.py secondary-click --simulator PRIVATE_UDID
```

For the pre-fix comparison, pass `--rev 37685da` to the touch rig. The checker should fail the hardware secondary-click cases over the on-screen trackpad. Direct finger gestures remain covered by the touch rig's normal mode.

The script posts input only inside the named private simulator. These private HID interfaces never ship in Sill.
