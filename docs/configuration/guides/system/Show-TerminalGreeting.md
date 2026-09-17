# Show-TerminalGreeting

The greeting a shell opens with, and what `c` redraws: clear the screen, show the fastfetch system info panel fitted to the window, and - inside a git repository - show the onefetch repository panel. Alias: `c`.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships the framework defaults, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`TerminalGreeting`](../../configuration-reference.md#terminal-greeting-startup-and-the-c-alias) | hashtable, 3 branches | `Clear` on, `Fastfetch` on (auto-fit on, `10` / `10` / `1`), `Onefetch` off | Which of the three steps run, how the font is fitted to the panels, and what arguments onefetch gets. Resolved by [`Resolve-TerminalGreetingSettings`](Resolve-TerminalGreetingSettings.md); an explicit parameter on the call beats the configured value for that one call. |

The whole section is optional. A configuration with no `TerminalGreeting` at all behaves exactly like the shipped values - clear, then a font-fitted fastfetch, no onefetch - so there is nothing you must set to keep the greeting working.

Nothing under `Fastfetch.AutoFit` is per machine. The fit is measured against the live window on every call, so a small laptop display, a high DPI scale or a wide fastfetch configuration needs no value of its own - those defaults are meant to be left alone.

## Decisions

1. Do you want the onefetch repository panel?
    - Options: `TerminalGreeting.Onefetch.Enabled = $true` turns it on. It needs the `onefetch` binary (`winget install o2sh.onefetch`); without it the step is a silent no-op. Outside a git repository it is skipped silently too, so turning it on costs nothing in directories it does not apply to.
    - Default: `$false` - opt-in, because it is only meaningful inside a repository and not every machine has the binary.
    - More detail: [`TerminalGreeting`](../../configuration-reference.md#terminal-greeting-startup-and-the-c-alias)
2. Should onefetch's height count towards the font fit?
    - Options: `TerminalGreeting.Onefetch.IncludeInAutoFit`. On, the font is chosen so that BOTH panels fit the window, which is almost always what you want - fitting fastfetch alone succeeds and then onefetch scrolls the top of it away. Off, fastfetch is fitted to itself and onefetch takes whatever room is left.
    - Default: `$true`.
    - More detail: [`TerminalGreeting`](../../configuration-reference.md#terminal-greeting-startup-and-the-c-alias)
3. Do you want onefetch in project terminals too?
    - Options: `TerminalGreeting.Onefetch.InProjectTerminals`. On, `Open-ProjectTerminals` appends `Invoke-Onefetch` to each project tab after its `Set-Location`. The terminal greeting cannot cover those tabs and no configuration can make it: a tab is spawned as `pwsh -NoExit -EncodedCommand <Set-Location ...>`, and PowerShell runs the profile BEFORE the encoded command, so the greeting tests whatever directory Windows Terminal started the tab in rather than the project it is about to move to. Appending the call after `Set-Location` is the only point at which the tab is standing in the repository.
    - Default: `$true`.
    - More detail: [`TerminalGreeting`](../../configuration-reference.md#terminal-greeting-startup-and-the-c-alias)
4. What arguments should onefetch get?
    - Options: `TerminalGreeting.Onefetch.Arguments`, an array. `@("--no-art")` drops the ASCII language logo, which is the usual choice when the fastfetch logo is already on screen; `@("--no-merges")` leaves merge commits out of the contributor counts. A single string works as one argument.
    - Default: `@()` - onefetch's own defaults.
    - More detail: [`TerminalGreeting`](../../configuration-reference.md#terminal-greeting-startup-and-the-c-alias)
5. Do you want the clear and fastfetch steps at all?
    - Options: `TerminalGreeting.Clear.Enabled` and `TerminalGreeting.Fastfetch.Enabled`. Turning `Clear` off leaves the greeting drawn under whatever was already on screen. Turning `Fastfetch` off with `Onefetch` on gives a repository-only greeting.
    - Default: both `$true`.
    - More detail: [`TerminalGreeting`](../../configuration-reference.md#terminal-greeting-startup-and-the-c-alias)
6. How far may the font shrink?
    - Options: An integer 0-50 in `TerminalGreeting.Fastfetch.AutoFit.MaxShrinkSteps`. The loop stops earlier whenever the panels fit or the terminal reaches its minimum font, so the cap only matters for a panel that cannot fit. `0` resets the font to the default and never shrinks. `Fastfetch.AutoFit.Enabled = $false` skips the fit outright, keystrokes and all, and leaves the tab at whatever size you put it at.
    - Default: `10`, with the fit on.
    - More detail: [`TerminalGreeting`](../../configuration-reference.md#terminal-greeting-startup-and-the-c-alias)
7. How long should each reflow be waited for?
    - Options: Any positive integer in `TerminalGreeting.Fastfetch.AutoFit.ReflowTimeoutMilliseconds`, no upper bound - this is the knob to tweak and test. Every shrink step returns as soon as the window has changed; the one wait that runs to this value is the reset when the font is already at the default. Raise it if `Set-LogLevel Verbose { c }` shows `cannot shrink further` after the first step while the panel `still overflows` - the terminal had not reflowed yet when the size was read.
    - Default: `10`.
    - More detail: [`TerminalGreeting`](../../configuration-reference.md#terminal-greeting-startup-and-the-c-alias)
8. How many rows should stay free for the prompt?
    - Options: An integer 0-20 in `TerminalGreeting.Fastfetch.AutoFit.PromptReserve`. One further row is always kept for the line the cursor ends on. A two-line prompt wants `2`.
    - Default: `1`.
    - More detail: [`TerminalGreeting`](../../configuration-reference.md#terminal-greeting-startup-and-the-c-alias)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so setting `TerminalGreeting.Onefetch.Enabled` leaves every other key - including the whole `Fastfetch` branch - at the base values. **Scalars replace wholesale.** **Arrays replace wholesale**, so `Onefetch.Arguments` must be written out in full, not added to.

## Steps Overview

1. Install `onefetch` if you want the repository panel
2. Set `TerminalGreeting`
3. Reload and confirm the merge landed

## Step 1: Install `onefetch` if you want the repository panel

The step is a silent no-op without the binary, so this comes first.

```powershell
winget install o2sh.onefetch
```

## Step 2: Set `TerminalGreeting`

Only the keys you change. Everything else falls through to the base.

```powershell
TerminalGreeting = @{
    Onefetch = @{
        Enabled   = $true
        Arguments = @("--no-art")
    }
}
```

## Step 3: Reload and confirm the merge landed

Reload the profile, then read the merged section back and what the resolver makes of it. `$global:Configuration` is the ground truth for the merge; `Resolve-TerminalGreetingSettings` is the ground truth for what `c` will run with, and it warns about any value out of range.

```powershell
Reload-PowerShellProfile
$global:Configuration.TerminalGreeting
Resolve-TerminalGreetingSettings
```

## Usage

```powershell
c
Show-TerminalGreeting
Show-TerminalGreeting -NoOnefetch
Show-TerminalGreeting -NoResize
Show-TerminalGreeting -MaxShrinkSteps 0
Set-LogLevel Verbose { Show-TerminalGreeting }
```

## Verification

Read-only checks. None of these change anything but the font size of the tab you run them in, which `c` resets on every call.

```powershell
$global:Configuration.TerminalGreeting
Resolve-TerminalGreetingSettings
Set-LogLevel Verbose { Show-TerminalGreeting }
```

The verbose form prints one line per step. `Invoke-Fastfetch` reports `panel WxH (including N extra row(s)), default window WxH, N of M Ctrl+Minus step(s) => window WxH, panel fits`; the extra rows are onefetch's, and their presence is how you confirm both panels are being fitted together. `still overflows` after the full cap means the panels are wider or taller than the terminal can accommodate at any font it will shrink to - make them smaller rather than raising the cap (see [The Panel Is Cut Off, Or The Font Ends Up Tiny, After `c`](../../../reference/troubleshooting.md#the-panel-is-cut-off-or-the-font-ends-up-tiny-after-c)). `Invoke-Onefetch` reports `skipped => ...` with the reason when nothing is shown. A `Configuration.TerminalGreeting.Fastfetch.AutoFit.<Key> must be an integer between` warning means the local value is out of range and the default was used for that key.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    TerminalGreeting = @{
        Clear     = @{
            Enabled = $true
        }
        Fastfetch = @{
            Enabled = $true
            AutoFit = @{
                Enabled                   = $true
                MaxShrinkSteps            = 3
                ReflowTimeoutMilliseconds = 150
                PromptReserve             = 2
            }
        }
        Onefetch  = @{
            Enabled            = $true
            IncludeInAutoFit   = $true
            InProjectTerminals = $true
            Arguments          = @("--no-art")
        }
    }
}
```

## Related

- [`Show-TerminalGreeting` in the System module reference](../../../modules/system.md#show-terminalgreeting) - parameters, order and behaviour
- [`Invoke-Clear`](Invoke-Clear.md), [`Invoke-Fastfetch`](Invoke-Fastfetch.md), [`Invoke-Onefetch`](Invoke-Onefetch.md) - the three steps
- [`Resolve-TerminalGreetingSettings`](Resolve-TerminalGreetingSettings.md) - how the three layers are merged and validated
- [`Test-FastfetchPanelOverflow`](Test-FastfetchPanelOverflow.md), [`Wait-ConsoleReflow`](Wait-ConsoleReflow.md), [`Send-TerminalFontKey`](Send-TerminalFontKey.md), [`Get-ConsoleWindowSize`](Get-ConsoleWindowSize.md) - the pieces the fit loop is built from
- [`Test-GitRepository`](../git/Test-GitRepository.md) - the repository test the onefetch step is gated on
- [`Get-FastfetchLogoArgument`](Get-FastfetchLogoArgument.md) - the image logo, which follows the font on its own
- [`Open-ProjectTerminals`](../workflow/Open-ProjectTerminals.md) - appends `Invoke-Onefetch` to each project tab, which the greeting cannot reach
- [System configuration guides](README.md) - every guide for this module
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
