# Open-Docker

Starts Docker Desktop minimized to the system tray via `Start-Application`, which reads the executable from `Universal.DockerExe` (ships the default install location, see [Start-Application](Start-Application.md)); this function itself reads nothing.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Open-Docker
```

## Related

- [`Open-Docker` in the Application module reference](../../../modules/application.md#open-docker) - parameters, usage and behaviour
- [Application configuration guides](README.md) - every guide for this module
