# Known Issues

Problems we know about, with workarounds where they exist. For general problem-solving, see
[Troubleshooting](troubleshooting.md).

## Terminal input locks up during workspace orchestration

While a workspace is being orchestrated (`Open-Workspace` / `w`), the terminal can occasionally
lock up: typed letters come out as if Caps Lock were stuck, and commands stop going through. The
workspace engine positions windows with synthesized keyboard input, and an interrupted sequence
can leave a modifier key logically stuck for the session.

**Workaround:** sign out and back in - the quickest form is locking the session (`Win+L`, or
Start → your account → **Lock**, just above the power options) and signing back in. This resets
the keyboard state.
