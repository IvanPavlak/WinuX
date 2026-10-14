# Open-FoundryVTT

Opens the FoundryVTT virtual tabletop server by starting the FoundryVTT desktop application via `Start-Application`, which reads the executable from `Universal.FoundryVTTExe` (ships empty - set it in `Configuration.local.psd1`, see [Start-Application](Start-Application.md)); this function itself reads nothing.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Open-FoundryVTT
```

## Related

- [`Open-FoundryVTT` in the Application module reference](../../../modules/application.md#open-foundryvtt) - parameters, usage and behaviour
- [Application configuration guides](README.md) - every guide for this module
