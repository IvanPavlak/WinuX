# Start-ProcessDetached

Starts a process through WMI (`Win32_Process.Create`) so it owns no console, or runs `Start-Process` with the `-Fallback` parameters when there is no executable or WMI refuses.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Start-ProcessDetached -FilePath "C:\Apps\Tool\Tool.exe"
Start-ProcessDetached -FilePath "C:\Apps\Tool\Tool.exe" -ArgumentList "-n", "`"C:\My Project`"" -Fallback @{ FilePath = "tool"; NoNewWindow = $true }
```

Why a launcher needs this: [The Workspace Tab Stays Open After [Closing current terminal tab]](../../../reference/troubleshooting.md#the-workspace-tab-stays-open-after-closing-current-terminal-tab).

## Related

- [`Start-ProcessDetached` in the Application module reference](../../../modules/application.md#start-processdetached)
- [Application configuration guides](README.md)
- [`Start-VSCodeDetached`](Start-VSCodeDetached.md) and [`Start-ObsidianDetached`](Start-ObsidianDetached.md) - the launchers built on it
