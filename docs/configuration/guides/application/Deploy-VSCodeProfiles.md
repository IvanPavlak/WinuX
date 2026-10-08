# Deploy-VSCodeProfiles

Brings VS Code to the profiles the configuration selects for this machine type: links each profile's files from the repository into VS Code and installs its extensions.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`VSCodeProfiles.Root`](../../configuration-reference.md#vs-code-profiles) | string | `{RepoRoot}\VSCode\Profiles` | Where the profile folders live, one per catalogue entry. |
| [`VSCodeProfiles.UserData`](../../configuration-reference.md#vs-code-profiles) | string | `{AppData}\Code\User` | VS Code's user data folder. Change it only for a portable or Insiders install. |
| [`VSCodeProfiles.SettingsSync`](../../configuration-reference.md#vs-code-profiles) | boolean | `$false` | Whether extensions install so Settings Sync carries them too (`$true`) or with `--do-not-sync` (`$false`). |
| [`VSCodeProfiles.Prune`](../../configuration-reference.md#vs-code-profiles) | boolean | `$false` | Whether extensions the list does not name are uninstalled. |
| [`VSCodeProfiles.Catalogue`](../../configuration-reference.md#vs-code-profiles) | ordered array | `@()` (empty) | The profiles the repository carries, and the VS Code profile each deploys onto (`Target`). |
| [`VSCodeProfiles.Deploy`](../../configuration-reference.md#vs-code-profiles) | hashtable | `@{ Default = @() }` | Which catalogue entries each machine type deploys. |
| [`BootstrapConfig.Steps.VSCodeProfiles`](../../configuration-reference.md#bootstrapconfig) | boolean | `$false` | Whether Bootstrap runs this function. OFF by default - the base catalogue is empty. |

The profile's UI state (history, layout, signed-in accounts) is not a configuration key and is never deployed: VS Code keeps it in its own database.

## Decisions

1. Which profiles should the repository carry?
    - Options: One catalogue entry per profile, each with a folder under `Root` holding any of `settings.json`, `keybindings.json`, `keybindings.windows.json`, `tasks.json`, `snippets\` and `extensions.txt`. Capture an existing profile with `Export-VSCodeProfile -Name <entry>`.
    - Default: None - the catalogue is empty and nothing is deployed.
    - More detail: [`VSCodeProfiles.Catalogue`](../../configuration-reference.md#vs-code-profiles)
2. Which VS Code profile should each entry deploy onto?
    - Options: Leave `Target` out to use the entry name, or set it to another name. `"Default"` is VS Code's built-in profile, which cannot be removed - point your everyday profile at it to keep a name of your own in the repository.
    - Default: The entry name.
    - More detail: [`VSCodeProfiles.Catalogue`](../../configuration-reference.md#vs-code-profiles)
3. Which entries should each machine type deploy?
    - Options: A list per machine type (`PC`, `Laptop`, `Work`, `Test`, ...), plus `Default` for every machine type not listed.
    - Default: `Default = @()` - nothing.
    - More detail: [`VSCodeProfiles.Deploy`](../../configuration-reference.md#vs-code-profiles)
4. Do you use VS Code's Settings Sync?
    - Options: `$true` installs extensions normally, so Sync carries them too; whatever Sync changes in a linked file then shows up in `git diff`. `$false` installs them with `--do-not-sync`, so Sync neither adds nor removes them - turn Sync off in VS Code to make the repository the only source.
    - Default: `$false`.
    - More detail: [`VSCodeProfiles.SettingsSync`](../../configuration-reference.md#vs-code-profiles)
5. Should extensions that are not listed be removed?
    - Options: `$true` uninstalls every extension `extensions.txt` does not name; `$false` leaves them, and `Deploy-VSCodeProfiles -Prune` removes them for one run.
    - Default: `$false`.
    - More detail: [`VSCodeProfiles.Prune`](../../configuration-reference.md#vs-code-profiles)
6. Should Bootstrap deploy the profiles on every run?
    - Options: `$true` to link and install on every Bootstrap, after the package managers so VS Code is installed; `$false` to run `Deploy-VSCodeProfiles` by hand.
    - Default: `$false` - a vanilla bootstrap deploys nothing.
    - More detail: [`BootstrapConfig.Steps`](../../configuration-reference.md#bootstrapconfig)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you. The profile folders go under `Root` in your fork.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

`Deploy` is a hashtable, so the base `Default = @()` survives the merge: name every machine type you want covered, or set `Default` yourself.

## Steps Overview

1. Add the catalogue entries
2. Choose what each machine type deploys
3. Decide on Settings Sync and pruning
4. Enable `BootstrapConfig.Steps.VSCodeProfiles`
5. Reload and confirm the merge landed

## Step 1: Add the catalogue entries

One single-key hashtable per profile, in the order you want them listed. Then capture each profile's folder from a machine that already has it set up.

```powershell
VSCodeProfiles = @{
    Catalogue = @(
        @{ MyProfile = @{ Target = "Default" } }
        @{ Writing = @{} }
    )
}
```

```powershell
Export-VSCodeProfile -Name MyProfile
```

Review the captured folder before committing it, and delete the lines of extensions you do not want deployed - VS Code's command line cannot tell a disabled extension apart.

## Step 2: Choose what each machine type deploys

```powershell
VSCodeProfiles = @{
    Deploy = @{
        Default = @("MyProfile")
        Work    = @("MyProfile", "Writing")
    }
}
```

## Step 3: Decide on Settings Sync and pruning

```powershell
VSCodeProfiles = @{
    SettingsSync = $true
    Prune        = $false
}
```

## Step 4: Enable `BootstrapConfig.Steps.VSCodeProfiles`

With the step on, Bootstrap runs `Deploy-VSCodeProfiles` after the package managers, so a fresh machine gets VS Code first and its profiles second.

```powershell
BootstrapConfig = @{
    Steps = @{
        VSCodeProfiles = $true
    }
}
```

> [!WARNING]
> A profile other than `Default` that VS Code does not know yet is registered in VS Code's own state file, which VS Code rewrites from memory while it runs. Close VS Code before the first deploy of such a profile; the function refuses otherwise.

## Step 5: Reload and confirm the merge landed

Reload the profile, then read the merged values back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
Resolve-VSCodeProfilesConfig
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
(Resolve-VSCodeProfilesConfig).Selected
(Resolve-VSCodeProfilesConfig).Unknown
Resolve-BootstrapSteps | Where-Object Name -eq "VSCodeProfiles"
Get-VSCodeProfileLocation Default
Get-ChildItem (Get-VSCodeProfileLocation Default) | Select-Object Name, LinkType, Target
Get-VSCodeInstalledExtensions -Command (Get-VSCodeCliPath) -ProfileName Default
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    VSCodeProfiles  = @{
        Root         = "{RepoRoot}\VSCode\Profiles"
        UserData     = "{AppData}\Code\User"
        SettingsSync = $true
        Prune        = $false
        Catalogue    = @(
            @{ MyProfile = @{ Target = "Default" } }
            @{ Writing = @{} }
        )
        Deploy       = @{
            Default = @("MyProfile")
            Work    = @("MyProfile", "Writing")
        }
    }
    BootstrapConfig = @{
        Steps = @{
            VSCodeProfiles = $true
        }
    }
}
```

## Related

- [`Deploy-VSCodeProfiles` in the Application module reference](../../../modules/application.md#deploy-vscodeprofiles) - parameters, usage and behaviour
- [`Export-VSCodeProfile`](Export-VSCodeProfile.md) - captures a live profile into its folder
- [`Resolve-VSCodeProfilesConfig`](Resolve-VSCodeProfilesConfig.md) - reads the same configuration
- [Application configuration guides](README.md) - every guide for this module
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
