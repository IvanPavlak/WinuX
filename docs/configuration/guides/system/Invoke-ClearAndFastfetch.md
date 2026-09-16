# Invoke-ClearAndFastfetch

Clears the terminal screen with `Clear-Host` and displays the fastfetch system info panel, shrinking the font step by step until the panel fits the Windows Terminal window. Alias: `c`.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships the framework defaults, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`FastfetchAutoFit`](../../configuration-reference.md#fastfetch-auto-fit-the-c-alias) | hashtable, 3 keys | `MaxShrinkSteps = 10`, `ReflowTimeoutMilliseconds = 10`, `PromptReserve = 1` | How far the font may shrink, how long each reflow is waited for, and how many rows stay free for the prompt. Resolved by [`Resolve-FastfetchAutoFitSettings`](Resolve-FastfetchAutoFitSettings.md); an explicit parameter on the call beats the configured value for that one call. |

Nothing here is per machine. The fit is measured against the live window on every call, so a small laptop display, a high DPI scale or a wide fastfetch configuration needs no value of its own - the base defaults are meant to be left alone.

## Decisions

1. How far may the font shrink?
    - Options: An integer 0-50 in `FastfetchAutoFit.MaxShrinkSteps`. The loop stops earlier whenever the panel fits or the terminal reaches its minimum font, so the cap only matters for a panel that cannot fit. `0` resets the font to the default and never shrinks.
    - Default: `10`.
    - More detail: [`FastfetchAutoFit`](../../configuration-reference.md#fastfetch-auto-fit-the-c-alias)
2. How long should each reflow be waited for?
    - Options: Any positive integer in `FastfetchAutoFit.ReflowTimeoutMilliseconds`, no upper bound - this is the knob to tweak and test. Every shrink step returns as soon as the window has changed; the one wait that runs to this value is the reset when the font is already at the default. Raise it if `Set-LogLevel Verbose { c }` shows `cannot shrink further` after the first step while the panel `still overflows` - the terminal had not reflowed yet when the size was read.
    - Default: `10`.
    - More detail: [`FastfetchAutoFit`](../../configuration-reference.md#fastfetch-auto-fit-the-c-alias)
3. How many rows should stay free for the prompt?
    - Options: An integer 0-20 in `FastfetchAutoFit.PromptReserve`. One further row is always kept for the line the cursor ends on. A two-line prompt wants `2`.
    - Default: `1`.
    - More detail: [`FastfetchAutoFit`](../../configuration-reference.md#fastfetch-auto-fit-the-c-alias)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so setting one key under `FastfetchAutoFit` leaves the other two at the base values. **Scalars replace wholesale.** This section has no arrays.

## Steps Overview

1. Set `FastfetchAutoFit`
2. Reload and confirm the merge landed

## Step 1: Set `FastfetchAutoFit`

Only the keys you change. Everything else falls through to the base.

```powershell
FastfetchAutoFit = @{
    PromptReserve = 2
}
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged section back and what the resolver makes of it. `$global:Configuration` is the ground truth for the merge; `Resolve-FastfetchAutoFitSettings` is the ground truth for what `c` will run with, and it warns about any value out of range.

```powershell
Reload-PowerShellProfile
$global:Configuration.FastfetchAutoFit
Resolve-FastfetchAutoFitSettings
```

## Usage

```powershell
c
Invoke-ClearAndFastfetch
Invoke-ClearAndFastfetch -NoResize
Invoke-ClearAndFastfetch -MaxShrinkSteps 0
Set-LogLevel Verbose { Invoke-ClearAndFastfetch }
```

## Verification

Read-only checks. None of these change anything but the font size of the tab you run them in, which `c` resets on every call.

```powershell
$global:Configuration.FastfetchAutoFit
Resolve-FastfetchAutoFitSettings
Set-LogLevel Verbose { Invoke-ClearAndFastfetch }
```

The verbose form prints one line of the shape `panel WxH, default window WxH, N of M Ctrl+Minus step(s) => window WxH, panel fits`. `still overflows` after the full cap means the panel is wider or taller than the terminal can accommodate at any font it will shrink to - make the panel smaller rather than raising the cap (see [The Panel Is Cut Off, Or The Font Ends Up Tiny, After `c`](../../../reference/troubleshooting.md#the-panel-is-cut-off-or-the-font-ends-up-tiny-after-c)). A `Configuration.FastfetchAutoFit.<Key> must be an integer between` warning means the local value is out of range and the default was used for that key.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    FastfetchAutoFit = @{
        MaxShrinkSteps            = 3
        ReflowTimeoutMilliseconds = 150
        PromptReserve             = 2
    }
}
```

## Related

- [`Invoke-ClearAndFastfetch` in the System module reference](../../../modules/system.md#invoke-clearandfastfetch) - parameters, usage and behaviour
- [`Resolve-FastfetchAutoFitSettings`](Resolve-FastfetchAutoFitSettings.md) - how the three layers are merged and validated
- [`Test-FastfetchPanelOverflow`](Test-FastfetchPanelOverflow.md), [`Wait-ConsoleReflow`](Wait-ConsoleReflow.md), [`Send-TerminalFontKey`](Send-TerminalFontKey.md), [`Get-ConsoleWindowSize`](Get-ConsoleWindowSize.md) - the pieces the loop is built from
- [`Get-FastfetchLogoArgument`](Get-FastfetchLogoArgument.md) - the image logo, which follows the font on its own
- [System configuration guides](README.md) - every guide for this module
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
