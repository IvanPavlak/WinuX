# Invoke-Onefetch

Displays the onefetch repository info panel when the shell is inside a git repository, and nothing at all - silently - when it is not. The third step of [`Show-TerminalGreeting`](Show-TerminalGreeting.md), and the one that ships off.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships the framework defaults, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`TerminalGreeting.Onefetch`](../../configuration-reference.md#terminal-greeting-startup-and-the-c-alias) | hashtable, 5 keys | `Enabled = $false`, `IncludeInAutoFit = $true`, `InProjectTerminals = $true`, `Arguments = @()`, `Style` off | Whether the repository panel is shown, whether its height counts towards the font fit, whether project terminals get it too, what arguments the binary gets, and how its output is restyled afterwards. Resolved by [`Resolve-TerminalGreetingSettings`](Resolve-TerminalGreetingSettings.md). |

Turning it on has no effect on machines where `onefetch` is not installed, and none in directories that are not repositories: both are silent no-ops with one debug line. There is no directory where this prints an error.

## Decisions

1. Do you want the repository panel?
    - Options: `TerminalGreeting.Onefetch.Enabled = $true`. Needs the `onefetch` binary - `winget install o2sh.onefetch`.
    - Default: `$false` - opt-in, because it is only meaningful inside a repository and not every machine has the binary.
    - More detail: [`TerminalGreeting`](../../configuration-reference.md#terminal-greeting-startup-and-the-c-alias)
2. Should its height count towards the font fit?
    - Options: `TerminalGreeting.Onefetch.IncludeInAutoFit`. On, `Show-TerminalGreeting` measures the panel before anything is drawn and passes its row count to `Invoke-Fastfetch` as `-ExtraRows`, so the font is chosen for BOTH panels together. Off, fastfetch is fitted to itself, which fits and then scrolls the top of it away as soon as onefetch prints below it. Turn it off only when you want the fastfetch panel at the largest font it can have and do not mind scrolling.
    - Default: `$true`.
    - More detail: [`TerminalGreeting`](../../configuration-reference.md#terminal-greeting-startup-and-the-c-alias)
3. Do you want it in project terminals as well?
    - Options: `TerminalGreeting.Onefetch.InProjectTerminals`. On, `Open-ProjectTerminals` (and so `Open-Workspace`) appends `Invoke-Onefetch` to each project tab's command, after the `Set-Location`. The terminal greeting cannot cover those tabs and no configuration can make it: a tab is spawned as `pwsh -NoExit -EncodedCommand <Set-Location ...>`, and PowerShell runs the profile BEFORE the encoded command, so the greeting tests whatever directory Windows Terminal started the tab in rather than the project it is about to move to. Appending the call after `Set-Location` is the only point at which the tab is standing in the repository. Off leaves project tabs bare while `c` still shows the panel. `-InvokeOnefetch` on the call wins over this key either way.
    - Default: `$true`.
    - More detail: [`TerminalGreeting`](../../configuration-reference.md#terminal-greeting-startup-and-the-c-alias)
4. What arguments should the binary get?
    - Options: `TerminalGreeting.Onefetch.Arguments`, an array. `@("--no-art")` drops the ASCII language logo, which is the usual choice when the fastfetch logo is already on screen; `@("--no-merges")` leaves merge commits out of the contributor counts; `@("--number-of-languages", "3")` shortens the language list. A single string works as one argument, and blank entries are dropped. Run `onefetch --help` for the full list.
    - Default: `@()` - onefetch's own defaults.
    - Note: this is onefetch's ONLY configuration surface. It has no configuration file, so unlike fastfetch there is nothing to dotfile and symlink, and this array is where its whole appearance lives. What the command line still cannot express - a true colour, or a separator other than the hardcoded `:` - is handled afterwards by [`Format-OnefetchPanel`](Format-OnefetchPanel.md).
    - More detail: [`TerminalGreeting`](../../configuration-reference.md#terminal-greeting-startup-and-the-c-alias)
5. Do you want the panel restyled beyond what the command line can say?
    - Options: `TerminalGreeting.Onefetch.Style`, which rewrites onefetch's output on its way to the screen - a true colour (`--text-colors` takes ANSI indices `0-15` and rejects anything above) and a separator other than `:` (hardcoded, with no flag that replaces it). Needs the all-hosts profile linked and a terminal that renders a true colour.
    - Default: off.
    - More detail: [`Format-OnefetchPanel`](Format-OnefetchPanel.md)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so setting `Enabled` leaves `IncludeInAutoFit` and `Arguments` at the base values. **Scalars replace wholesale.** **Arrays replace wholesale**, so `Arguments` must be written out in full, not added to.

## Steps Overview

1. Install `onefetch`
2. Set `TerminalGreeting.Onefetch`
3. Reload and confirm the merge landed

## Step 1: Install `onefetch`

The step is a silent no-op without the binary, so this comes first.

```powershell
winget install o2sh.onefetch
```

## Step 2: Set `TerminalGreeting.Onefetch`

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

```powershell
Reload-PowerShellProfile
$global:Configuration.TerminalGreeting.Onefetch
(Resolve-TerminalGreetingSettings).Onefetch
```

## Usage

```powershell
Invoke-Onefetch
Invoke-Onefetch -Measure
Invoke-Onefetch -Arguments "--no-art"
Invoke-Onefetch -Path "C:\Development\WinuX"
Set-LogLevel Verbose { Invoke-Onefetch }
```

## Verification

Read-only checks. None of these change anything.

```powershell
$global:Configuration.TerminalGreeting.Onefetch
(Resolve-TerminalGreetingSettings).Onefetch
Invoke-Onefetch -Measure
Set-LogLevel Verbose { Invoke-Onefetch }
```

`-Measure` prints the number of rows the panel would take, and `0` whenever nothing would be shown - the quickest way to confirm the step is live in the directory you are standing in. The verbose form names the reason when nothing is shown: `Enabled is false`, `onefetch is not installed`, `[...] is not inside a git repository`, or `exited N` for a repository with no commits.

## Complete Example

```powershell
# Configuration.local.psd1
@{
    TerminalGreeting = @{
        Onefetch = @{
            Enabled            = $true
            IncludeInAutoFit   = $true
            InProjectTerminals = $true
            Arguments          = @("--no-art", "--no-merges")
        }
    }
}
```

## Related

- [`Invoke-Onefetch` in the System module reference](../../../modules/system.md#invoke-onefetch) - parameters, usage and behaviour
- [`Show-TerminalGreeting`](Show-TerminalGreeting.md) - the orchestrator, and the `c` alias
- [`Format-OnefetchPanel`](Format-OnefetchPanel.md) - the true colours and the separator the command line cannot express
- [`Invoke-Fastfetch`](Invoke-Fastfetch.md) - the panel the fit budget is shared with
- [`Test-GitRepository`](../git/Test-GitRepository.md) - the repository test this step is gated on
- [`Resolve-TerminalGreetingSettings`](Resolve-TerminalGreetingSettings.md) - how the three layers are merged and validated
- [`Open-ProjectTerminals`](../workflow/Open-ProjectTerminals.md) - appends this function to each project tab, gated on `InProjectTerminals`
- [System configuration guides](README.md) - every guide for this module
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
