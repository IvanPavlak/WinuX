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

**The reproducible form of this had one concrete cause, now fixed.**
[`Rerun-LastCommand`](../modules/helper.md#rerun-lastcommand) - the recovery path the workspace
engine escalates to, and the one that opens the fresh shell you type into afterwards - closed the
original terminal window with a synthesized `Ctrl+Shift+W`. That shortcut closes the very window
hosting the shell doing the injecting, so Windows Terminal tore the process down mid-injection,
before the Ctrl and Shift key-ups were ever sent. Both modifiers stayed logically held for the
rest of the desktop session, and no self-heal could catch it: nothing runs after a process closes
its own host window. It is now closed by posting `WM_CLOSE` to the window handle, which needs no
focus and synthesizes no input, so a rerun can no longer strand a modifier.

A stuck modifier from a genuinely interrupted sequence (a shell closed mid-snap, a killed process,
a blocked injection) remains possible, and the engine self-heals it:
[`Reset-KeyboardModifiers`](../modules/window.md#reset-keyboardmodifiers) releases the stuck keys,
and orchestration calls it automatically at the snapping, retry, rerun, and flow-completion
checkpoints, plus as the last act before a rerun exits the process. The shift-drag snap also
guarantees its Shift/mouse release on every managed exit path.

**Workaround (if it still happens):**

1. Tap both Shift keys (and both Ctrl / Alt / Win keys if input still misbehaves) - a physical
   press and release clears the stuck state for that key and restores Enter.
2. Run `Reset-KeyboardModifiers` to release anything remaining; it reports which keys were stuck.
3. Signing out and back in remains the last resort - the quickest form is locking the session
   (`Win+L`, or Start → your account → **Lock**, just above the power options) and signing back
   in. This resets the keyboard state.
