# Initialize-PSReadLine

Applies every PSReadLine editing, history and prediction option from the `PSReadLine` section to the current session - the configuration-driven form of the `Set-PSReadLineOption` / `Set-PSReadLineKeyHandler` block the profile used to hardcode.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships the framework defaults, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`PSReadLine`](../../configuration-reference.md#psreadline-interactive-shell-options) | hashtable, 7 keys | Windows edit mode, prefix-search arrows, `HistoryNoDuplicates` on, history predictions in a list, history limits untouched | Everything the profile applies to PSReadLine on shell start. Any key set to `$null` is skipped and PSReadLine keeps its own default. |

## Decisions

1. How many commands should the shell recall?
    - Options: A positive integer in `PSReadLine.MaximumHistoryCount`. It sets both the PSReadLine recall cap (arrow keys, `Ctrl+R`) and the session `$MaximumHistoryCount` (`Get-History`); the latter is clamped at PowerShell's 32767 ceiling, so 32767 is the value at which both agree exactly.
    - Default: `$null` - PSReadLine's own 4096, and `Get-History`'s own 4096.
    - More detail: [`PSReadLine`](../../configuration-reference.md#psreadline-interactive-shell-options)
2. Should the history file live somewhere else?
    - Options: A path in `PSReadLine.HistorySavePath`. `%ENV%` variables are expanded. Useful to keep the file inside a synced folder.
    - Default: `$null` - PSReadLine's `%APPDATA%\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt`.
    - More detail: [`PSReadLine`](../../configuration-reference.md#psreadline-interactive-shell-options)
3. Do you want different key bindings?
    - Options: Add entries under `PSReadLine.KeyHandlers` as `<Key> = "<PSReadLine function>"`, for example `Tab = "MenuComplete"`. Hashtables merge per key, so adding one binding keeps the base arrows; to drop a base binding, set that key to `$null`.
    - Default: `UpArrow = "HistorySearchBackward"`, `DownArrow = "HistorySearchForward"`.
    - More detail: [`PSReadLine`](../../configuration-reference.md#psreadline-interactive-shell-options)
4. Do you want a different edit mode or prediction style?
    - Options: `EditMode` is `Windows`, `Emacs` or `Vi`. `PredictionSource` is `None`, `History`, `Plugin` or `HistoryAndPlugin`. `PredictionViewStyle` is `InlineView` or `ListView`.
    - Default: `Windows`, `History`, `ListView`.
    - More detail: [`PSReadLine`](../../configuration-reference.md#psreadline-interactive-shell-options)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to `PSReadLine` or `PSReadLine.KeyHandlers` leaves every other entry alone. **Scalars replace wholesale.** This section has no arrays.

## Steps Overview

1. Set `PSReadLine`
2. Reload and confirm the merge landed

## Step 1: Set `PSReadLine`

Only the keys you change. Everything else falls through to the base.

```powershell
PSReadLine = @{
    MaximumHistoryCount = 32767
}
```

## Step 2: Reload and confirm the merge landed

Open a new shell (the profile applies the section at start), then read the merged value back and what PSReadLine actually took. `$global:Configuration` is the ground truth for the merge; `Get-PSReadLineOption` is the ground truth for the session.

```powershell
$global:Configuration.PSReadLine
Get-PSReadLineOption | Select-Object EditMode, MaximumHistoryCount, HistoryNoDuplicates, PredictionSource, PredictionViewStyle
$MaximumHistoryCount
```

## Verification

Read-only checks. None of these change anything.

```powershell
$global:Configuration.PSReadLine
Get-PSReadLineOption | Select-Object EditMode, MaximumHistoryCount, HistorySavePath, HistoryNoDuplicates, PredictionSource, PredictionViewStyle
$MaximumHistoryCount
Get-PSReadLineKeyHandler -Bound | Where-Object Key -in UpArrow, DownArrow
```

`MaximumHistoryCount` reads back as `0` in `Get-PSReadLineOption` when the base `$null` is in effect - that is PSReadLine's own way of saying "defer to `$MaximumHistoryCount`". A value that is not a positive integer produces a `Configuration.PSReadLine.MaximumHistoryCount must be a positive integer` warning at shell start and leaves both limits alone. In a console without virtual-terminal support (redirected output, automation hosts) the two prediction options are skipped silently and everything else still applies.

PSReadLine never trims its history file: it appends every command and loads the newest `MaximumHistoryCount` lines at startup. The cap is what is recallable, not what is stored. `HistoryNoDuplicates` likewise hides repeated commands during recall only - every invocation is still written to the file.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    PSReadLine = @{
        MaximumHistoryCount = 32767
        HistorySavePath     = "%USERPROFILE%\Sync\PowerShell\ConsoleHost_history.txt"
        KeyHandlers         = @{
            Tab = "MenuComplete"
        }
    }
}
```

## Related

- [`Initialize-PSReadLine` in the System module reference](../../../modules/system.md#initialize-psreadline) - parameters, ordering rules and behaviour
- [`Initialize-OhMyPosh`](Initialize-OhMyPosh.md) - runs after this function; the reason `EditMode` must never be applied later
- [System configuration guides](README.md) - every guide for this module
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
