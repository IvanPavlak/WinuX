# Create-CondaEnvironments

Updates Conda and idempotently creates Conda environments from the YAML files in the WinuX `Conda/Environments` folder.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`BootstrapConfig.DataFiles.CondaEnvironments`](../../configuration-reference.md#bootstrapconfig) | string (repository-relative path) | `Conda\Environments` | The folder whose `*.yml` files are the environments; each file's name is the environment name. Joined onto `PathTemplates.Projects.Self.Root`. |
| [`PathTemplates.Projects.Self.Root`](../../configuration-reference.md#path-templates--placeholder-system) | path template | `{RepoRoot}` | The repository root the folder above is resolved against (read from `$global:MachineSpecificPaths.Projects.Self.Root`). |
| [`AutoEnvironmentVariables.Conda`](../../configuration-reference.md#more-sections-quick-reference) | path | not set (`AutoEnvironmentVariables` ships `@{}`) | Not read directly: the function reads the `Conda` user environment variable, which `Set-EnvironmentVariables -Auto` writes from this entry. Without it the function warns and skips; `conda.exe` is expected at `<Conda>\Scripts\conda.exe`. |
| [`BootstrapConfig.Steps.CondaEnvironments`](../../configuration-reference.md#bootstrapconfig) | boolean or per-machine-type hashtable | `$true` (built-in default) | Whether `Bootstrap` runs this function. |

## Decisions

1. Should Conda environments be created on this machine?
    - Options: Install Miniconda3 and set `AutoEnvironmentVariables.Conda` to its install folder (for example `{User}\miniconda3`), then run `Set-EnvironmentVariables -Auto`; leave it unset to skip Conda entirely.
    - Default: Not set - the function warns and skips.
    - More detail: [`AutoEnvironmentVariables`](../../configuration-reference.md#more-sections-quick-reference)
2. Do the environment files live somewhere other than `Conda\Environments`?
    - Options: A repository-relative folder path under `BootstrapConfig.DataFiles.CondaEnvironments`.
    - Default: `Conda\Environments`. Almost nobody changes this.
    - More detail: [`BootstrapConfig`](../../configuration-reference.md#bootstrapconfig)
3. Should Bootstrap run this step?
    - Options: `$true`, `$false`, or a per-machine-type hashtable with a `Default` fallback under `BootstrapConfig.Steps.CondaEnvironments`.
    - Default: `$true` - and the missing `Conda` variable already makes it a no-op on machines without Conda.
    - More detail: [`BootstrapConfig`](../../configuration-reference.md#bootstrapconfig)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `AutoEnvironmentVariables.Conda`
2. Set `BootstrapConfig`
3. Reload and confirm the merge landed

## Step 1: Set `AutoEnvironmentVariables.Conda`

Point the `Conda` variable at the Miniconda3 install folder, then persist it with `Set-EnvironmentVariables -Auto` (Bootstrap does this too) and open a new shell.

```powershell
AutoEnvironmentVariables = @{
    Conda = "{User}\miniconda3"
}
```

## Step 2: Set `BootstrapConfig`

Only needed to move the environments folder or to turn the Bootstrap step off. Hashtables deep-merge, so set only the keys you change.

```powershell
BootstrapConfig = @{
    DataFiles = @{
        CondaEnvironments = "Conda\Environments"
    }
    Steps     = @{
        CondaEnvironments = $true
    }
}
```

## Step 3: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.BootstrapConfig.DataFiles.CondaEnvironments
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$env:Conda
Join-Path $global:MachineSpecificPaths.Projects.Self.Root $global:Configuration.BootstrapConfig.DataFiles.CondaEnvironments
Resolve-BootstrapSteps | Where-Object Name -eq "CondaEnvironments"
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    AutoEnvironmentVariables = @{
        Conda = "{User}\miniconda3"
    }
    BootstrapConfig          = @{
        DataFiles = @{
            CondaEnvironments = "Conda\Environments"
        }
        Steps     = @{
            CondaEnvironments = $true
        }
    }
}
```

## Related

- [`Create-CondaEnvironments` in the Application module reference](../../../modules/application.md#create-condaenvironments) - parameters, usage and behaviour
- [Application configuration guides](README.md) - every guide for this module
- [`Bootstrap`](../bootstrap/Bootstrap.md) - runs this function when `BootstrapConfig.Steps.CondaEnvironments` is on
- [`Set-EnvironmentVariables`](../system/Set-EnvironmentVariables.md) - persists `AutoEnvironmentVariables`, including `Conda`
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
