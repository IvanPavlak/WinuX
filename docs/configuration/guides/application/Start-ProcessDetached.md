# Start-ProcessDetached

Starts a process through WMI (`Win32_Process.Create`) so it owns no console and is not tied to the current shell; returns the process id, or `$null` when WMI refuses, so the caller decides on a fallback.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Start-ProcessDetached -FilePath "C:\Apps\Tool\Tool.exe"
Start-ProcessDetached -FilePath "C:\Apps\Tool\Tool.exe" -ArgumentList "-n", "`"C:\My Project`"" -WorkingDirectory "C:\My Project"
```

Windows Terminal closes a tab only when every process attached to the tab's console has disconnected. A launcher that runs before a workspace closes its own tab (`Terminate-WindowsTerminalTabs -OnlyCurrent`) must therefore start applications this way rather than with `Start-Process -NoNewWindow`, which hands the console down to the application - see [The Workspace Tab Stays Open After [Closing current terminal tab]](../../../reference/troubleshooting.md#the-workspace-tab-stays-open-after-closing-current-terminal-tab).

## Related

- [`Start-ProcessDetached` in the Application module reference](../../../modules/application.md#start-processdetached)
- [Application configuration guides](README.md)
- [`Start-VSCodeDetached`](Start-VSCodeDetached.md) and [`Start-ObsidianDetached`](Start-ObsidianDetached.md) - the launchers built on it
