# Configure-NuGetConfig

Configures NuGet package source settings by copying the repository's `nuget.config` template, with your GitHub username and personal access token substituted in, to the user's NuGet folder.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

> [!NOTE]
> An existing real `NuGet.Config` at the destination (which may carry credentials for feeds the template knows nothing about) is copied into the unified [backup sink](../../../reference/backups.md) (`Backups/Windows/System/NuGetConfig/<timestamp>/`, gitignored) before it is overwritten, with every `ClearTextPassword` and `Password` value replaced by `REDACTED`, so the copy keeps the sources but no token; if the backup cannot be taken the write is aborted.

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`PathTemplates.NuGetConfig.SourcePath`](../../configuration-reference.md#nuget-configuration) | string (placeholder path) | `"{RepoRoot}\NuGet\nuget.config"` | The template that is copied. Its `[Username]` and `[Token]` placeholders are replaced with the values you are prompted for, and its `packageSources` are what an existing config is compared against. |
| [`PathTemplates.NuGetConfig.DestinationPath`](../../configuration-reference.md#nuget-configuration) | string (placeholder path) | `"{AppData}\NuGet\nuget.config"` | Where the configured file is written (UTF-8). When it already exists and `-Override` is not passed, it is only rewritten if its package sources differ from the template's. |
| [`BootstrapConfig.Steps.NuGetConfig`](../../configuration-reference.md#bootstrapconfig) | boolean | `$false` | Whether Bootstrap runs this function (read by Bootstrap, not by the function). OFF by default - it prompts for a token. |

Both paths are read through `$global:MachineSpecificPaths.NuGetConfig` (the expanded `PathTemplates.NuGetConfig`).

## Decisions

1. Which feeds should the template carry?
    - Options: Edit the repository's `NuGet\nuget.config` (or point `SourcePath` at your own template) and add your private feed under `packageSources`, with a `packageSourceCredentials` block that uses the `[Username]` and `[Token]` placeholders. Never commit a real token.
    - Default: The shipped template, which lists only `nuget.org` and carries the private-feed block commented out.
    - More detail: [`PathTemplates.NuGetConfig`](../../configuration-reference.md#nuget-configuration)
2. Is the standard user NuGet folder the right destination?
    - Options: Leave it, or override `DestinationPath` (for example for a solution-level `nuget.config`).
    - Default: `{AppData}\NuGet\nuget.config`.
    - More detail: [`PathTemplates.NuGetConfig`](../../configuration-reference.md#nuget-configuration)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `PathTemplates.NuGetConfig`
2. Reload and confirm the merge landed

## Step 1: Set `PathTemplates.NuGetConfig`

Only needed when the shipped template or destination is wrong for you. `NuGetConfig` is a hashtable, so you can override one path and keep the other as shipped.

```powershell
PathTemplates = @{
    NuGetConfig = @{
        SourcePath      = "{RepoRoot}\NuGet\nuget.config"
        DestinationPath = "{AppData}\NuGet\nuget.config"
    }
}
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:MachineSpecificPaths` after a reload is the ground truth for expanded `PathTemplates` - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:MachineSpecificPaths.NuGetConfig
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:MachineSpecificPaths.NuGetConfig
Test-Path $global:MachineSpecificPaths.NuGetConfig.SourcePath
Test-Path $global:MachineSpecificPaths.NuGetConfig.DestinationPath
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    PathTemplates = @{
        NuGetConfig = @{
            SourcePath      = "{RepoRoot}\NuGet\nuget.config"
            DestinationPath = "{AppData}\NuGet\nuget.config"
        }
    }
    BootstrapConfig = @{
        Steps = @{ NuGetConfig = $true }
    }
}
```

## Related

- [`Configure-NuGetConfig` in the System module reference](../../../modules/system.md#configure-nugetconfig) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
