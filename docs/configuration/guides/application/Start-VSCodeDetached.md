# Start-VSCodeDetached

Launches VS Code (`Code.exe`, resolved by `Get-VSCodeExecutablePath`) through `Start-ProcessDetached` so it owns no console, falling back to `code` through `Start-Process -NoNewWindow` when the executable cannot be located or WMI refuses.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Start-VSCodeDetached
Start-VSCodeDetached -ArgumentList "-n", "`"C:\Projects\MyProject`""
```

`Open-VSCode` and `Open-VSCodeWorkspace` start VS Code this way. The folders and workspace files they offer are configured on their own pages.

## Related

- [`Start-VSCodeDetached` in the Application module reference](../../../modules/application.md#start-vscodedetached)
- [Application configuration guides](README.md)
- [`Open-VSCode`](Open-VSCode.md) and [`Open-VSCodeWorkspace`](Open-VSCodeWorkspace.md) - the launchers that call it
