# Get-TerminalCellSize

Reports the pixel width and height of one character cell by asking the terminal itself with the XTWINOPS `CSI 16 t` query, returning `$null` when nothing answers.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-TerminalCellSize
Get-TerminalCellSize -TimeoutMilliseconds 500
```

## Related

- [`Get-TerminalCellSize` in the System module reference](../../../modules/system.md#get-terminalcellsize) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
- [`Get-FastfetchLogoArgument`](Get-FastfetchLogoArgument.md) - the caller that needs this measurement
