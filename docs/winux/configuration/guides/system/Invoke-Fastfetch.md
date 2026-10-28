# Invoke-Fastfetch

Displays the fastfetch system info panel, shrinking the font step by step until the panel fits the Windows Terminal window. The second step of [`Show-TerminalGreeting`](Show-TerminalGreeting.md); it does not clear the screen.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships the framework defaults, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`TerminalGreeting.Fastfetch`](../../configuration-reference.md#terminal-greeting-startup-and-the-c-alias) | hashtable | `Enabled = $true` | Whether the panel is shown at all. |
| [`TerminalGreeting.Fastfetch.AutoFit`](../../configuration-reference.md#terminal-greeting-startup-and-the-c-alias) | hashtable, 4 keys | `Enabled = $true`, `MaxShrinkSteps = 10`, `ReflowTimeoutMilliseconds = 10`, `PromptReserve = 1` | Whether the font is fitted to the panel, how far it may shrink, how long each reflow is waited for, and how many rows stay free for the prompt. |

Nothing here is per machine. The fit is measured against the live window on every call, so a small laptop display, a high DPI scale or a wide fastfetch configuration needs no value of its own - the base defaults are meant to be left alone. Resolved by [`Resolve-TerminalGreetingSettings`](Resolve-TerminalGreetingSettings.md); an explicit parameter on the call beats the configured value for that one call.

## Decisions

1. Do you want the font fitted at all?
    - Options: `TerminalGreeting.Fastfetch.AutoFit.Enabled`. Off sends no keystrokes whatsoever and shows the panel at whatever font the tab is on - distinct from `MaxShrinkSteps = 0`, which still presses `Ctrl+0` to reset to the default. Off is also what you want if your Windows Terminal has custom `actions` that dropped the `Ctrl+0` / `Ctrl+Minus` bindings.
    - Default: `$true`.
    - More detail: [`TerminalGreeting`](../../configuration-reference.md#terminal-greeting-startup-and-the-c-alias)
2. How far may the font shrink?
    - Options: An integer 0-50 in `TerminalGreeting.Fastfetch.AutoFit.MaxShrinkSteps`. The loop stops earlier whenever the panel fits or the terminal reaches its minimum font, so the cap only matters for a panel that cannot fit. `0` resets the font to the default and never shrinks, which shows whether the panel fits at all at the default size.
    - Default: `10`.
    - More detail: [`TerminalGreeting`](../../configuration-reference.md#terminal-greeting-startup-and-the-c-alias)
3. How long should each reflow be waited for?
    - Options: Any positive integer in `TerminalGreeting.Fastfetch.AutoFit.ReflowTimeoutMilliseconds`, no upper bound - this is the knob to tweak and test. Every shrink step returns as soon as the window has changed; the one wait that runs to this value is the reset when the font is already at the default. Raise it if `Set-LogLevel Verbose { c }` shows `cannot shrink further` after the first step while the panel `still overflows` - the terminal had not reflowed yet when the size was read.
    - Default: `10`.
    - More detail: [`TerminalGreeting`](../../configuration-reference.md#terminal-greeting-startup-and-the-c-alias)
4. How many rows should stay free for the prompt?
    - Options: An integer 0-20 in `TerminalGreeting.Fastfetch.AutoFit.PromptReserve`. One further row is always kept for the line the cursor ends on. A two-line prompt wants `2`.
    - Default: `1`.
    - More detail: [`TerminalGreeting`](../../configuration-reference.md#terminal-greeting-startup-and-the-c-alias)

The rows onefetch will occupy are not configured here. `Show-TerminalGreeting` measures them and passes them as `-ExtraRows`, so the font is fitted to both panels at once; whether it does is [`TerminalGreeting.Onefetch.IncludeInAutoFit`](Invoke-Onefetch.md).

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so setting one key under `TerminalGreeting.Fastfetch.AutoFit` leaves the other three at the base values. **Scalars replace wholesale.** This branch has no arrays.

## Steps Overview

1. Set `TerminalGreeting.Fastfetch`
2. Reload and confirm the merge landed

## Step 1: Set `TerminalGreeting.Fastfetch`

Only the keys you change. Everything else falls through to the base.

```powershell
TerminalGreeting = @{
    Fastfetch = @{
        AutoFit = @{
            PromptReserve = 2
        }
    }
}
```

## Step 2: Reload and confirm the merge landed

```powershell
Reload-PowerShellProfile
$global:Configuration.TerminalGreeting.Fastfetch
(Resolve-TerminalGreetingSettings).Fastfetch.AutoFit
```

## Usage

```powershell
Invoke-Fastfetch
Invoke-Fastfetch -NoResize
Invoke-Fastfetch -MaxShrinkSteps 0
Invoke-Fastfetch -ExtraRows 12
Set-LogLevel Verbose { Invoke-Fastfetch }
```

## Verification

Read-only checks. None of these change anything but the font size of the tab you run them in, which `c` resets on every call.

```powershell
$global:Configuration.TerminalGreeting.Fastfetch
(Resolve-TerminalGreetingSettings).Fastfetch.AutoFit
Set-LogLevel Verbose { Invoke-Fastfetch }
```

The verbose form prints one line of the shape `panel WxH, default window WxH, N of M Ctrl+Minus step(s) => window WxH, panel fits`, with `(including N extra row(s))` after the panel size when onefetch's height is in the budget. `still overflows` after the full cap means the panel is wider or taller than the terminal can accommodate at any font it will shrink to - make the panel smaller rather than raising the cap (see [The Panel Is Cut Off, Or The Font Ends Up Tiny, After `c`](../../../reference/troubleshooting.md#the-panel-is-cut-off-or-the-font-ends-up-tiny-after-c)). `skipped => fastfetch is not installed` means exactly that, and is why a machine without it starts without an error at the prompt.

## Complete Example

```powershell
# Configuration.local.psd1
@{
    TerminalGreeting = @{
        Fastfetch = @{
            Enabled = $true
            AutoFit = @{
                Enabled                   = $true
                MaxShrinkSteps            = 3
                ReflowTimeoutMilliseconds = 150
                PromptReserve             = 2
            }
        }
    }
}
```

## Related

- [`Invoke-Fastfetch` in the System module reference](../../../modules/system.md#invoke-fastfetch) - parameters, usage and behaviour
- [`Show-TerminalGreeting`](Show-TerminalGreeting.md) - the orchestrator, and the `c` alias
- [`Resolve-TerminalGreetingSettings`](Resolve-TerminalGreetingSettings.md) - how the three layers are merged and validated
- [`Test-FastfetchPanelOverflow`](Test-FastfetchPanelOverflow.md), [`Wait-ConsoleReflow`](Wait-ConsoleReflow.md), [`Send-TerminalFontKey`](Send-TerminalFontKey.md), [`Get-ConsoleWindowSize`](Get-ConsoleWindowSize.md) - the pieces the loop is built from
- [`Get-FastfetchLogoArgument`](Get-FastfetchLogoArgument.md) - the image logo, which follows the font on its own
- [System configuration guides](README.md) - every guide for this module
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
