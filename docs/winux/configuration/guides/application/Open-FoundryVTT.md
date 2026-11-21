# Open-FoundryVTT

Opens the FoundryVTT virtual tabletop server by starting the FoundryVTT desktop application via `Start-Application`, which reads the executable from `Universal.FoundryVTTExe` (ships empty - set it in `Configuration.local.psd1`, see [Start-Application](Start-Application.md)); this function itself reads nothing.

> [!WARNING]
> **Deprecated since 2.17.0, removed in 3.0.0.** `Open-FoundryVTT` serves one personal setup rather than the framework. To keep it, copy the function file (and its test) into your fork's Custom area under `Windows/PowerShell/Modules/Custom/<Module>/Functions/`, list it in `Custom.psd1`, and keep its keys in `Configuration.local.psd1`, where the copy goes on reading them. The function keeps working until 3.0.0 and warns once per session.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Open-FoundryVTT
```

## Related

- [`Open-FoundryVTT` in the Application module reference](../../../modules/application.md#open-foundryvtt) - parameters, usage and behaviour
- [Application configuration guides](README.md) - every guide for this module
