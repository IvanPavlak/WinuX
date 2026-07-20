# Known Issues

Problems we know about, with workarounds where they exist. For general problem-solving, see
[Troubleshooting](troubleshooting.md).

## Terminal input locks up during workspace orchestration

While a workspace is being orchestrated (`Open-Workspace` / `w`), the terminal can occasionally
lock up: typed letters come out as if Caps Lock were stuck, and commands stop going through. The
workspace engine positions windows with synthesized keyboard input, and an interrupted sequence
can leave a modifier key logically stuck for the session. A logically held **Shift** is what
produces both symptoms: letters arrive uppercase, and Enter stops submitting because PSReadLine
reads it as `Shift+Enter` (insert line).

The engine now self-heals this state:
[`Reset-KeyboardModifiers`](../modules/window.md#reset-keyboardmodifiers) releases the stuck
keys, and orchestration calls it automatically at the snapping, retry, rerun, and
flow-completion checkpoints. The shift-drag snap also guarantees its Shift/mouse release on
every managed exit path, so the stuck state should no longer occur in the first place.

**Workaround (if it still happens):**

1. Tap both Shift keys (and both Ctrl / Alt / Win keys if input still misbehaves) - a physical
   press and release clears the stuck state for that key and restores Enter.
2. Run `Reset-KeyboardModifiers` to release anything remaining; it reports which keys were stuck.
3. Signing out and back in remains the last resort - the quickest form is locking the session
   (`Win+L`, or Start → your account → **Lock**, just above the power options) and signing back
   in. This resets the keyboard state.
