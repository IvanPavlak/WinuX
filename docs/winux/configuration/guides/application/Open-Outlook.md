# Open-Outlook

Opens the new Outlook (Microsoft Store app) through the shared `Start-Application` launcher, which starts `Universal.OutlookLauncherExe` (ships `C:\Windows\explorer.exe`, see [Start-Application](Start-Application.md)) with the fixed Outlook `shell:AppsFolder` argument; this function itself reads nothing.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Open-Outlook
```

## Related

- [`Open-Outlook` in the Application module reference](../../../modules/application.md#open-outlook) - parameters, usage and behaviour
- [Application configuration guides](README.md) - every guide for this module
