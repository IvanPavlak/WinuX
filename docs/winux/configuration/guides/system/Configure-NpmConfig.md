# Configure-NpmConfig

Authenticates npm against private registries (GitHub Packages) by writing their token lines into the user npmrc, so `npm install` of a private scoped package works.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

> [!NOTE]
> The token is never a configuration value. It is asked on the terminal (a GitHub personal access token with `read:packages`; the one you give [Configure-NuGetConfig](Configure-NuGetConfig.md) works) and written only into the npmrc. An existing real npmrc is copied into the unified [backup sink](../../../reference/backups.md) (`Backups/Windows/System/NpmConfig/<timestamp>/`, gitignored) before it is changed, with every credential value (`_authToken`, `_auth`, `_password`) replaced by `<redacted>` so the copy holds no token; if the backup cannot be taken the write is aborted.

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`NpmRegistries`](../../configuration-reference.md#npm-configuration) | array of hashtables (`Url`, `Scope`) | `@( @{ Url = "https://npm.pkg.github.com/"; Scope = "" } )` | The registries that get a token line (`//<host><path>:_authToken=`). An entry with a `Scope` also gets `<Scope>:registry=<Url>`, so that scope's packages come from the registry. Empty: the function warns and returns. |
| [`PathTemplates.NpmConfig`](../../configuration-reference.md#npm-configuration) | string (placeholder path) | `"{User}\.npmrc"` | The npmrc that is written. Every line it already has for other settings or registries is kept. |
| [`BootstrapConfig.Steps.NpmConfig`](../../configuration-reference.md#bootstrapconfig) | boolean | `$false` | Whether Bootstrap runs this function (read by Bootstrap, not by the function). OFF by default - it prompts for a token. |

The path is read through `$global:MachineSpecificPaths.NpmConfig` (the expanded `PathTemplates.NpmConfig`).

## Decisions

1. Which private registries, and which package scopes do they serve?
    - Options: One `NpmRegistries` entry per registry. Set `Scope` to your organization's scope (`"@my-org"`) when the project's own `.npmrc` does not already route it; leave it `""` when it does. Arrays replace wholesale, so list every registry you want.
    - Default: GitHub Packages (`https://npm.pkg.github.com/`) without a scope.
    - More detail: [`NpmRegistries`](../../configuration-reference.md#npm-configuration)
2. Is the user npmrc the right file?
    - Options: Leave it, or point `PathTemplates.NpmConfig` at another npmrc (npm reads the user file for every project).
    - Default: `{User}\.npmrc`.
    - More detail: [`PathTemplates.NpmConfig`](../../configuration-reference.md#npm-configuration)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `NpmRegistries`
2. Set `PathTemplates.NpmConfig`
3. Reload and confirm the merge landed

## Step 1: Set `NpmRegistries`

List every private registry. `NpmRegistries` is an array, so this replaces the base entry.

```powershell
NpmRegistries = @(
    @{ Url = "https://npm.pkg.github.com/"; Scope = "@my-org" }
)
```

## Step 2: Set `PathTemplates.NpmConfig`

Only needed when the user npmrc is the wrong file for you.

```powershell
PathTemplates = @{
    NpmConfig = "{User}\.npmrc"
}
```

## Step 3: Reload and confirm the merge landed

Reload the profile, then read the merged values back. If what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.NpmRegistries
$global:MachineSpecificPaths.NpmConfig
```

## Verification

Read-only checks. None of these change anything, and `npm config list` shows a token as `(protected)`.

```powershell
Reload-PowerShellProfile
$global:Configuration.NpmRegistries
Test-Path $global:MachineSpecificPaths.NpmConfig
npm config list
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    NpmRegistries = @(
        @{ Url = "https://npm.pkg.github.com/"; Scope = "@my-org" }
    )
    PathTemplates = @{
        NpmConfig = "{User}\.npmrc"
    }
    BootstrapConfig = @{
        Steps = @{ NpmConfig = $true }
    }
}
```

## Related

- [`Configure-NpmConfig` in the System module reference](../../../modules/system.md#configure-npmconfig) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
