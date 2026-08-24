# Kill-All

Orchestrates a full desktop cleanup as a sequence of configurable steps.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Kill-All
Kill-All -Exclude "*YouTube*"
Kill-All -Skip Docker
```

## Related

- [`Kill-All` in the System module reference](../../../modules/system.md#kill-all) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
