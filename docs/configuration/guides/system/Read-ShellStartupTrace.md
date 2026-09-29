# Read-ShellStartupTrace

Reads the file a shell start wrote through `WINUX_STARTUP_TRACE` - one tab-separated line per stage, name and milliseconds - into a hashtable of stage name to milliseconds. A missing or empty file is an empty table; a line that does not parse is dropped; a stage that appears twice keeps its last value.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Read-ShellStartupTrace -Path "$env:TEMP\startup.trace"
```

## Related

- [`Read-ShellStartupTrace` in the System module reference](../../../modules/system.md#read-shellstartuptrace) - parameters, usage and behaviour
- [`Complete-StartupStage`](../helper/Complete-StartupStage.md) - writes the lines this reads
- [`Invoke-ShellStartupSample`](Invoke-ShellStartupSample.md) - the caller
- [System configuration guides](README.md) - every guide for this module
