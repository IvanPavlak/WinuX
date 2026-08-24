# Run-Tests

Discovers all `.Tests.ps1` Pester tests in the PowerShell Modules Tests directory (every module's test folder plus the Infrastructure checks), and by default also the fork-owned Custom area (`Modules/Custom/<Module>/Tests`), then hands them to `Invoke-TestSuite` to run in parallel worker processes.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Run-Tests
Run-Tests -TestName "Open-Terminal"
Run-Tests -Detailed
```

## Related

- [`Run-Tests` in the Tests module reference](../../../modules/tests.md#run-tests) - parameters, usage and behaviour
- [Tests configuration guides](README.md) - every guide for this module
