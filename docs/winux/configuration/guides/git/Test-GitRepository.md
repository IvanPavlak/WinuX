# Test-GitRepository

Tells whether a path is inside a git repository, by walking up to the root looking for a `.git` entry - the directory a normal clone has, or the file a worktree or submodule carries. No process is spawned.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure. Its caller [`Invoke-Onefetch`](../system/Invoke-Onefetch.md) is gated on [`TerminalGreeting.Onefetch.Enabled`](../../configuration-reference.md#terminal-greeting-startup-and-the-c-alias), which is configured through [`Show-TerminalGreeting`](../system/Show-TerminalGreeting.md).

## Usage

```powershell
Test-GitRepository
Test-GitRepository -Path "C:\Development\WinuX\Windows\PowerShell"
if (Test-GitRepository) { onefetch }
```

## Related

- [`Test-GitRepository` in the Git module reference](../../../modules/git.md#test-gitrepository) - parameters, usage and behaviour
- [`Invoke-Onefetch`](../system/Invoke-Onefetch.md) - the caller it gates
- [`Show-TerminalGreeting`](../system/Show-TerminalGreeting.md) - the greeting the gate belongs to
- [Git configuration guides](README.md) - every guide for this module
