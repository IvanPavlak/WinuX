# Invoke-TerminateWindowsTerminalTabsIncludeCurrentCleanup

Finalizes the `-IncludeCurrent` cleanup path for `Terminate-WindowsTerminalTabs`.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Invoke-TerminateWindowsTerminalTabsIncludeCurrentCleanup -ClosedTabs @("TabA") -StartingTitle "CurrentTab" -OriginalHostTitle "OriginalTitle"
Invoke-TerminateWindowsTerminalTabsIncludeCurrentCleanup -ClosedTabs @("TabA") -StartingTitle "CurrentTab" -OriginalHostTitle "OriginalTitle" -CloseWaitSeconds 5
```

## Related

- [`Invoke-TerminateWindowsTerminalTabsIncludeCurrentCleanup` in the System module reference](../../../modules/system.md#invoke-terminatewindowsterminaltabsincludecurrentcleanup) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
