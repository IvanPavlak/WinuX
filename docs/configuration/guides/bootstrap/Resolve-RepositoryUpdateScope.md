# Resolve-RepositoryUpdateScope

Resolves which repository groups Bootstrap clones and updates on this machine.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`BootstrapConfig`](../../configuration-reference.md#bootstrapconfig) | hashtable, 9 keys | hashtable, 9 keys | Two keys matter here: `RepositoryUpdateScope` says **which** repository groups this machine type pulls, and `Steps.RepositoryUpdate` says **whether** the repository step runs at all. |

## Decisions

1. Should Bootstrap pull repositories on this machine at all?
    - Options: `BootstrapConfig.Steps.RepositoryUpdate`, a boolean or a per-machine-type hashtable with a `Default` fallback, like every other step. It is **opt-in** - cloning and pulling every repository the scope names reaches outside this repository the moment it runs, and a fresh clone has no repository list worth acting on yet.
    - Default: `$false`. Set it `$true` once `RepositoryGroups` describes the machines you actually provision. `Bootstrap -Skip RepositoryUpdate` and `-Include RepositoryUpdate` override it per run.
    - More detail: [`BootstrapConfig`](../../configuration-reference.md#bootstrapconfig)
2. Which groups should this machine type pull?
    - Options: `BootstrapConfig.RepositoryUpdateScope`, keyed by machine type with a `Default` fallback. Each value is `"All"` or one or more group names from `RepositoryGroups`, written as a comma-separated string (`"Work, Private"`) or as an array (`@("Work", "Private")`). Names are matched case-insensitively and kept in the order given.
    - Default: `@{ Default = "All" }`. An absent key means the same thing, so a fork that configures nothing pulls every repository it defines.
    - More detail: [`BootstrapConfig`](../../configuration-reference.md#bootstrapconfig)
3. Does a machine type need a scope of its own?
    - Options: Add a key named after the machine type, e.g. `Test = "Private"`, alongside `Default`. The machine type's own value wins over `Default`.
    - Default: Only `Default` is shipped, so every machine type gets the same scope.
    - More detail: [`BootstrapConfig`](../../configuration-reference.md#bootstrapconfig)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `BootstrapConfig`
2. Reload and confirm the merge landed

## Step 1: Set `BootstrapConfig`

Turn the step on, then say which groups each machine type pulls. Group names are never validated here - nothing in Bootstrap knows what groups your fork defines. A name that is not configured surfaces from `Update-Repositories -Group`, which lists the configured groups and updates nothing, rather than silently falling back to updating everything.

```powershell
BootstrapConfig = @{
    Steps                 = @{
        RepositoryUpdate = $true
    }
    RepositoryUpdateScope = @{
        Default = "All"
        Test    = "Private"
        Work    = "Work, Private"
    }
}
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.BootstrapConfig.RepositoryUpdateScope
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.BootstrapConfig.RepositoryUpdateScope

# What this machine would pull: @{ All = <bool>; Groups = <string[]> }
Resolve-RepositoryUpdateScope

# Whether the step runs at all
Resolve-BootstrapSteps | Format-Table
Resolve-BootstrapSteps -Skip RepositoryUpdate | Format-Table

# The repositories those groups actually expand to
Resolve-RepositoryTargets -Group (Resolve-RepositoryUpdateScope).Groups | Format-Table Name, Group, LocalPath
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    BootstrapConfig = @{
        Steps                 = @{
            RepositoryUpdate = $true
        }
        RepositoryUpdateScope = @{
            Default = "All"
            Test    = "Private"
        }
    }
}
```

## Related

- [`Resolve-RepositoryUpdateScope` in the Bootstrap module reference](../../../modules/bootstrap.md#resolve-repositoryupdatescope) - parameters, usage and behaviour
- [Bootstrap configuration guides](README.md) - every guide for this module
- [Add New Machine](add-new-machine.md) - the full 7-step walk for bringing a new machine type online
- [`Bootstrap`](Bootstrap.md) - reads the same configuration
- [`Resolve-BootstrapSteps`](Resolve-BootstrapSteps.md) - reads the same configuration
- [`Resolve-RepositoryTargets`](../git/Resolve-RepositoryTargets.md) - expands the group names this page resolves
- [`Update-Repositories`](../git/Update-Repositories.md) - what Bootstrap calls with the resolved scope
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
