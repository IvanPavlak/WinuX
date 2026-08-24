# Resolve-Steps

The generic step-map resolver shared by every configurable step set (`Resolve-KillAllSteps` and `Resolve-SystemThemeSteps` in the System module, `Resolve-BootstrapSteps` in the Bootstrap module, and `Resolve-RunProjectSteps` in this module are thin wrappers over it).

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Resolve-Steps -Defaults ([ordered]@{ Docker = $true }) -ConfigSteps $global:Configuration.KillAll.Steps
Resolve-Steps -Defaults $defaults -ConfigSteps $configSteps -Skip Docker, Browsers
```

## Related

- [`Resolve-Steps` in the Helper module reference](../../../modules/helper.md#resolve-steps) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module
