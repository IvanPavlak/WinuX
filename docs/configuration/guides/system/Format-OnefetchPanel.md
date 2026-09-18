# Format-OnefetchPanel

Restyles onefetch's output on its way to the screen, reaching the two parts of its appearance that onefetch itself cannot be told about. Driven by `TerminalGreeting.Onefetch.Style`, applied by the global `onefetch` wrapper in the all-hosts profile, and off in the base configuration.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships the framework defaults, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Why This Exists

fastfetch has a configuration file. You dotfile `config.jsonc`, symlink it into `~/.config/fastfetch/`, and every colour, key, icon and separator lives there.

onefetch has nothing of the kind. It reads no configuration file at all - its entire appearance comes from the command line - and two things cannot be said on that command line either:

| What you want | Why the binary cannot do it |
| ------------- | --------------------------- |
| A true colour, so the panel matches a fastfetch palette exactly | `--text-colors` takes ANSI indices `0-15` and nothing else. `--text-colors 33` is rejected outright with `33 is not in 0..16`, and there is no true-colour form, so `38;2;30;144;255` cannot be passed at all. `--true-color` governs only the ASCII art. |
| Something other than `:` after each field name | The colon is hardcoded. In `--text-colors`, "colon" is a *colour* slot, not a string, and `--number-separator` is the thousands separator inside numbers. No flag replaces the character. |

Both are reachable after the fact, because onefetch writes ordinary SGR escape sequences and keeps writing them when its output is piped. `Format-OnefetchPanel` rewrites that stream.

So there is no `Onefetch/` folder to dotfile and no symlink to make. `TerminalGreeting.Onefetch.Arguments` and `TerminalGreeting.Onefetch.Style` together *are* the onefetch dotfile.

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`TerminalGreeting.Onefetch.Style.Enabled`](../../configuration-reference.md#terminal-greeting-startup-and-the-c-alias) | bool | `$false` | Whether the panel is restyled at all. Off, onefetch's output reaches the screen exactly as the binary wrote it. |
| [`TerminalGreeting.Onefetch.Style.Separator`](../../configuration-reference.md#terminal-greeting-startup-and-the-c-alias) | string | `""` | Replaces the hardcoded `:` and the single space after it. `" -> "` reads like a fastfetch separator. `""` keeps the colon. |
| [`TerminalGreeting.Onefetch.Style.Colors`](../../configuration-reference.md#terminal-greeting-startup-and-the-c-alias) | hashtable | `@{}` | Maps an ANSI index onefetch was told to use onto the SGR parameters to paint it with instead. The only route to a true colour. |

## Prerequisites

Two, and the feature is inert without either.

1. **The all-hosts profile must be linked.** The wrapper lives there, so copy `PathTemplates.SymbolicLinks.PowerShell.AllHostsProfile` from `Configuration.psd1` into your `Configuration.local.psd1` and run `SymbolicLinkMaker`. This is the same file the fastfetch image logo uses.
2. **A terminal that renders a true colour.** The wrapper sits behind the same guard as the image logo - Windows Terminal (`$env:WT_SESSION`) or WezTerm. In every other host the file defines nothing and `onefetch.exe` resolves exactly as before.

## Decisions

1. Do you want the panel restyled at all?
    - Options: `TerminalGreeting.Onefetch.Style.Enabled = $true`. Everything else on this page is inert until this is on.
    - Default: `$false` - the panel is onefetch's own unless you ask otherwise.
    - More detail: [`TerminalGreeting`](../../configuration-reference.md#terminal-greeting-startup-and-the-c-alias)
2. What should separate a field name from its value?
    - Options: `TerminalGreeting.Onefetch.Style.Separator`. `" -> "` matches a fastfetch `display.separator` of the same shape. Any string works - `" > "`, `" : "`, `" → "`. Leave it `""` to keep onefetch's colon and use this feature for colour alone.
    - Default: `""`.
    - Note: a separator wider than the `:` it replaces shifts every value right, and the continuation lines are re-padded to follow it. That is handled for you - see [Alignment](#alignment).
    - More detail: [`TerminalGreeting`](../../configuration-reference.md#terminal-greeting-startup-and-the-c-alias)
3. Which colours should be repainted, and as what?
    - Options: `TerminalGreeting.Onefetch.Style.Colors`, a hashtable keyed by the ANSI index (`0-15`) onefetch was told to use, valued by the SGR parameters to paint it with instead. The value is the body of an escape sequence, so a true colour is written exactly as a fastfetch configuration writes one: `"38;2;30;144;255"`.
    - This pairs with `Arguments`: you tell the binary *which index* to use for each slot through `--text-colors`, then map that index to a true colour here. An index you did not ask onefetch to use will simply never appear in the output.
    - Default: `@{}` - repaint nothing.
    - More detail: [`TerminalGreeting`](../../configuration-reference.md#terminal-greeting-startup-and-the-c-alias)

## What the Wrapper Does to a Bare `onefetch`

A bare `onefetch` typed at the prompt gets `TerminalGreeting.Onefetch.Arguments` as well as the styling, the way a bare `fastfetch` gets its configuration file. Without that it would be styled but not *coloured*: `Style.Colors` remaps the indices `--text-colors` was asked for, and with no arguments those indices are never the ones onefetch used.

Arguments on the call replace the configured ones rather than adding to them, so `onefetch --no-art` still does what it says. `Invoke-Onefetch` always passes its own arguments explicitly, which is why they are never sent twice.

## Matching a fastfetch Palette

`--text-colors` takes six values in a fixed order, which map onto fastfetch's own colour keys:

| onefetch slot | What it paints | fastfetch equivalent |
| ------------- | -------------- | -------------------- |
| 1. title | The `user ~ host` line | `title.keyColor` |
| 2. `~` | The separator inside the title | `title.at` |
| 3. underline | The rule below the title | - |
| 4. subtitle | Every field name | `keyColor` |
| 5. colon | The `:`, and so your separator | `display.color.separator` |
| 6. info | Every value | `outputColor` |

Pick a distinct index per fastfetch colour, then map each index to its true colour. Using `12` for everything blue and `9` for everything red:

```powershell
Arguments = @("--text-colors", "12", "9", "9", "12", "9", "15")
Style     = @{
    Colors = @{
        "12" = "38;2;30;144;255"  # dodger blue - fastfetch keyColor
        "9"  = "38;2;255;0;0"     # neon red    - fastfetch display.color.separator
    }
}
```

Index `15` is left unmapped above because bright white already is white.

## Alignment

A separator wider than the `:` it replaces pushes each value right, while onefetch's own continuation lines - the second author, the extra churn entries, the language chips - are already padded and would be left behind. They are re-padded by the difference, and the padding is inserted at the *info column* rather than at column 0, so the rows of the ASCII logo that share a line with a language chip keep their own columns instead of acquiring a slant.

The info column is measured once, off the first field line, as the last run of two spaces before the separator: the gap between the logo and the info is more than one space, while the words inside a field name are separated by exactly one. With `--no-art` there is no such run and no logo to protect, and column 0 is the right answer.

Three kinds of line are never padded - the title and its underline (not in the value column at all), anything carrying a background colour (the colour palette row and the language bar, both drawn to a width of their own), and anything too short to reach the info column.

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so setting `Style.Separator` leaves `Style.Colors` at the base value. **Scalars replace wholesale.** **Arrays replace wholesale**, so `Arguments` must be written out in full, not added to.

## Steps Overview

1. Link the all-hosts profile
2. Set `TerminalGreeting.Onefetch.Style`
3. Reload and confirm

## Step 1: Link the all-hosts profile

```powershell
# Configuration.local.psd1, under PathTemplates.SymbolicLinks.PowerShell
AllHostsProfile = @{
    Path   = "{User}\Documents\PowerShell\profile.ps1"
    Target = "{RepoRoot}\Windows\PowerShell\profile.ps1"
}
```

Then run `SymbolicLinkMaker`.

## Step 2: Set `TerminalGreeting.Onefetch.Style`

```powershell
TerminalGreeting = @{
    Onefetch = @{
        Enabled   = $true
        Arguments = @("--text-colors", "12", "9", "9", "12", "9", "15", "--nerd-fonts", "--no-bold")
        Style     = @{
            Enabled   = $true
            Separator = " -> "
            Colors    = @{
                "12" = "38;2;30;144;255"
                "9"  = "38;2;255;0;0"
            }
        }
    }
}
```

## Step 3: Reload and confirm

```powershell
Reload-PowerShellProfile
(Resolve-TerminalGreetingSettings).Onefetch.Style
(Get-Command onefetch).CommandType   # Function, not Application, when the wrapper is live
onefetch
```

`Function` means the wrapper took: PowerShell resolves functions before external applications, so both the greeting's call and a bare `onefetch` at the prompt are styled. `Application` means the all-hosts profile is not linked, or this host is not one of the two the guard allows.

## Verification

Read-only checks. None of these change anything.

```powershell
(Resolve-TerminalGreetingSettings).Onefetch.Style
(Get-Command onefetch).CommandType
Set-LogLevel Verbose { Invoke-Onefetch }
Invoke-Onefetch -Measure
```

To see the rewrite without running the binary at all:

```powershell
"$([char]27)[94mProject$([char]27)[0m$([char]27)[91m:$([char]27)[0m x" |
    Format-OnefetchPanel -Separator " -> " -Colors @{ "12" = "38;2;30;144;255" }
```

`Invoke-Onefetch -Measure` still reports the height correctly with styling on: the rewrite emits exactly one line per line it is given.

## Troubleshooting

| Symptom | Cause |
| ------- | ----- |
| Nothing is restyled | `Style.Enabled` is `$false`, the all-hosts profile is not linked, or the host is neither Windows Terminal nor WezTerm. `(Get-Command onefetch).CommandType` tells you which. |
| The separator changed but no colour did | The indices in `Colors` are not the ones `--text-colors` was given, so they never appear in the output. Check `Arguments`. |
| A bare `onefetch` looks different from the one in the greeting | Arguments on the call replace the configured ones. Run it bare to get the configured look. |
| A colour key is ignored | An index outside `0-15`, or an empty replacement. `Set-LogLevel Verbose { onefetch }` names it. |
| Nothing has colour at all | `NO_COLOR` is set in the environment. There is nothing in the stream to rewrite, and the panel passes through untouched. |
| The language chips sit two columns off the logo | Expected, and not a defect: the chips move with the values, the logo does not. |

## Complete Example

```powershell
# Configuration.local.psd1
@{
    TerminalGreeting = @{
        Onefetch = @{
            Enabled   = $true
            Arguments = @("--text-colors", "12", "9", "9", "12", "9", "15", "--nerd-fonts", "--no-bold")
            Style     = @{
                Enabled   = $true
                Separator = " -> "
                Colors    = @{
                    "12" = "38;2;30;144;255"
                    "9"  = "38;2;255;0;0"
                }
            }
        }
    }
}
```

## Related

- [`Format-OnefetchPanel` in the System module reference](../../../modules/system.md#format-onefetchpanel) - parameters, usage and behaviour
- [`Invoke-Onefetch`](Invoke-Onefetch.md) - the greeting step whose output this restyles
- [`Get-FastfetchLogoArgument`](Get-FastfetchLogoArgument.md) - the other all-hosts profile addition, and the same terminal guard
- [`Resolve-TerminalGreetingSettings`](Resolve-TerminalGreetingSettings.md) - how the three layers are merged and validated
- [`Show-TerminalGreeting`](Show-TerminalGreeting.md) - the orchestrator, and the `c` alias
- [System configuration guides](README.md) - every guide for this module
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
