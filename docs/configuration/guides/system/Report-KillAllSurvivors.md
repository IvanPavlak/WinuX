# Report-KillAllSurvivors

The closing audit of `Kill-All`: lists every visible application window still standing that is neither a `Universal.VisibleWindowExclusions` process nor an `-Exclude` match, and returns them so the run ends on a warning instead of a success line.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Report-KillAllSurvivors
Report-KillAllSurvivors -Exclude "*YouTube*"
```

## Related

- [`Report-KillAllSurvivors` in the System module reference](../../../modules/system.md#reportkillallsurvivors) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
