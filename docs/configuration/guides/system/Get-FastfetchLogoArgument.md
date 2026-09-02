# Get-FastfetchLogoArgument

Builds the fastfetch command-line arguments that render an image logo instead of the text logo, in the terminals that can display one - WezTerm and Windows Terminal - and returns nothing everywhere else.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`Universal.FastFetchImageLogo`](../../configuration-reference.md#universal-paths) | string, or hashtable keyed by machine type | `$null` | The image fastfetch renders as its logo. `$null` turns the whole feature off, so the text logo declared in the fastfetch configuration renders everywhere. A hashtable gives each machine type its own image; a machine with no entry gets none. |
| [`PathTemplates.SymbolicLinks.PowerShell.AllHostsProfile`](../../configuration-reference.md#symbolic-links) | hashtable | absent | The symbolic link that deploys `Windows\PowerShell\profile.ps1`. Without it nothing calls this function, whatever the image key says. |
| [`PathTemplates.SymbolicLinks.FastFetch.Logo`](../../configuration-reference.md#symbolic-links) | hashtable | absent | The deployed text logo. Used only to MEASURE the block of character cells the image is fitted into, so the image and the text logo occupy identical space. Absent means a 36x16 default. |

## Decisions

1. Which image should fastfetch show?
    - Options: Any path ImageMagick can decode - PNG, JPEG, SVG, ICO, WEBP. WinuX ships its own logo at `Windows\WinuX\WinuXLogoTransparent.png`, so `"{RepoRoot}\Windows\WinuX\WinuXLogoTransparent.png"` works out of the box. `$null` keeps the text logo.
    - Default: `$null`, so the text logo renders and nothing is encoded.
    - More detail: [`Universal.FastFetchImageLogo`](../../configuration-reference.md#universal-paths)
2. The same image on every machine, or one per machine?
    - Options: A string for one image everywhere, or a hashtable keyed by machine type. A machine with no entry in the map gets no image, which is the same no-op as leaving the key unset.
    - Default: Neither - the key is `$null`.
    - More detail: [`Universal.FastFetchImageLogo`](../../configuration-reference.md#universal-paths)
3. Do you want the all-hosts profile deployed at all?
    - Options: Add `PowerShell.AllHostsProfile` to `PathTemplates.SymbolicLinks` and run `SymbolicLinkMaker -Name "PowerShell"` elevated, or leave it out and keep the text logo in every terminal.
    - Default: Absent. The base ships framework links only, and this one is opt-in.
    - More detail: [`PathTemplates.SymbolicLinks.PowerShell.AllHostsProfile`](../../configuration-reference.md#symbolic-links)
4. Should the image match the text logo's footprint, or its own size?
    - Options: Leave `FastFetch.Logo` linked and the block is measured from that text logo, which keeps the panel geometry identical whichever logo renders. Pass `-CellWidth` / `-CellHeight` at the call site to size the block yourself.
    - Default: Measured from the linked text logo; 36x16 cells when there is none.
    - More detail: [`PathTemplates.SymbolicLinks.FastFetch.Logo`](../../configuration-reference.md#symbolic-links)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `Universal.FastFetchImageLogo`
2. Add the `PowerShell.AllHostsProfile` symbolic link and create it
3. Reload and confirm the merge landed

## Step 1: Set `Universal.FastFetchImageLogo`

The image fastfetch renders as its logo. Placeholders are expanded, so `{RepoRoot}` and `{User}` both work.

One image for every machine:

```powershell
Universal = @{
    FastFetchImageLogo = "{RepoRoot}\Windows\WinuX\WinuXLogoTransparent.png"
}
```

Or one per machine type. Placeholders expand inside the map too, and a machine you leave out
keeps its text logo - so this is also how you roll the feature out to one machine at a time:

```powershell
Universal = @{
    FastFetchImageLogo = @{
        PC     = "{RepoRoot}\Windows\WinuX\WinuXLogoTransparent.png"
        Laptop = "{RepoRoot}\Windows\WinuX\WinuXLogoTransparent.png"
        Work   = "{RepoRoot}\FastFetch\Windows\CompanyLogo.png"
    }
}
```

> [!WARNING]
> This key is read as a whole, so the hashtable follows the usual merge rule for its own
> entries: a local `FastFetchImageLogo` hashtable deep-merges per machine-type key over the
> base, but switching between the string and hashtable shapes replaces the value outright.

## Step 2: Add the `PowerShell.AllHostsProfile` symbolic link and create it

The link deploys the all-hosts profile, which is what defines the global `fastfetch` function that calls this one. Nest it inside the existing `PowerShell` entry so the framework links are left alone.

```powershell
PathTemplates = @{
    SymbolicLinks = @{
        PowerShell = @{
            AllHostsProfile = @{
                Path   = "{User}\Documents\PowerShell\profile.ps1"
                Target = "{RepoRoot}\Windows\PowerShell\profile.ps1"
            }
        }
    }
}
```

Then create it from an elevated shell and open a new tab - the wrapper is defined at profile load:

```powershell
SymbolicLinkMaker -Name "PowerShell"
```

## Step 3: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.Universal.FastFetchImageLogo
```

## Verification

Read-only checks. None of these change anything.

```powershell
$global:Configuration.Universal.FastFetchImageLogo
$global:MachineType
$global:MachineSpecificPaths.SymbolicLinks.FastFetch.Logo.Path
(Get-Command fastfetch).CommandType
Get-FastfetchLogoArgument
Set-LogLevel Verbose { Get-FastfetchLogoArgument }
```

`(Get-Command fastfetch).CommandType` must read `Function`: if it reads `Application`, the all-hosts profile is not deployed and nothing overrides the logo. `Get-FastfetchLogoArgument` returning nothing is normal in a host that cannot show an image - the verbose form names the check that declined. See [fastfetch Logo Issues](../../../reference/troubleshooting.md#fastfetch-logo-issues) for the full table.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    Universal     = @{
        FastFetchImageLogo = @{
            PC     = "{RepoRoot}\Windows\WinuX\WinuXLogoTransparent.png"
            Laptop = "{RepoRoot}\Windows\WinuX\WinuXLogoTransparent.png"
            Work   = "{RepoRoot}\FastFetch\Windows\CompanyLogo.png"
        }
    }

    PathTemplates = @{
        SymbolicLinks = @{
            PowerShell = @{
                AllHostsProfile = @{
                    Path   = "{User}\Documents\PowerShell\profile.ps1"
                    Target = "{RepoRoot}\Windows\PowerShell\profile.ps1"
                }
            }
            FastFetch  = @{
                Configuration = @{
                    Path   = "{User}\.config\fastfetch\config.jsonc"
                    Target = "{RepoRoot}\FastFetch\Windows\config_{MachineType}.jsonc"
                }
                Logo          = @{
                    Path   = "{User}\.config\fastfetch\FastFetchLogo_{MachineType}.txt"
                    Target = "{RepoRoot}\FastFetch\Windows\FastFetchLogo_{MachineType}.txt"
                }
            }
        }
    }
}
```

## Related

- [`Get-FastfetchLogoArgument` in the System module reference](../../../modules/system.md#get-fastfetchlogoargument) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
- [Add Symbolic Link](add-symbolic-link.md) - link shapes, placeholders and the WSL cases
- [`Get-TerminalCellSize`](Get-TerminalCellSize.md) - the measurement this function depends on
- [`New-SixelImage`](New-SixelImage.md) - the encoder this function depends on
- [`Invoke-ClearAndFastfetch`](Invoke-ClearAndFastfetch.md) - the `c` alias that renders the panel
- [fastfetch Logo Issues](../../../reference/troubleshooting.md#fastfetch-logo-issues) - every fallback and how to diagnose it
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
