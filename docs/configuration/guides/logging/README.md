# Logging Module Configuration Guides

One configuration guide per exported function of the `Logging` module, which covers console and file logging - levels, colours, retention, and the maintenance sweep.

The [Logging module reference](../../../modules/logging.md) is the authority on what each function *does*. These guides cover what to *configure* for it.

> [!TIP]
> Working through a whole module is what [WinuXConfigurator](../../winux-configurator.md) is for - point an AI assistant at it and it walks the table below with you, one decision at a time.

## Configurable Functions

| Function | Configuration keys | Guide |
| -------- | ------------------ | ----- |
| `Initialize-LoggingState` | `Logging` | [Initialize-LoggingState](Initialize-LoggingState.md) |
| `Invoke-LogMaintenance` | `Logging` | [Invoke-LogMaintenance](Invoke-LogMaintenance.md) |

## Functions With No Configuration

These read no `Configuration.psd1` keys. Their guides record that fact and show how to call them.

[Clear-OldLogs](Clear-OldLogs.md), [Get-LogPath](Get-LogPath.md), [Protect-Log](Protect-Log.md), [Set-LogLevel](Set-LogLevel.md), [Start-Logging](Start-Logging.md), [Stop-Logging](Stop-Logging.md), [Test-LogVerbose](Test-LogVerbose.md), [Write-Log](Write-Log.md), [Write-LogDebug](Write-LogDebug.md), [Write-LogError](Write-LogError.md), [Write-LogList](Write-LogList.md), [Write-LogStep](Write-LogStep.md), [Write-LogSuccess](Write-LogSuccess.md), [Write-LogTitle](Write-LogTitle.md), [Write-LogWarning](Write-LogWarning.md)

## Related

- [Logging module reference](../../../modules/logging.md) - what each function does
- [Configuration reference](../../configuration-reference.md) - every key, section by section
- [Configuration overview](../../overview.md) - how the configuration system fits together
- [Fork Model](../../../contributing/fork-model.md) - why your values go in `Configuration.local.psd1`
- [WinuXConfigurator](../../winux-configurator.md) - AI-assisted walkthrough of every module
