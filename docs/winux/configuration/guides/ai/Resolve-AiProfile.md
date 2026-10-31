# Resolve-AiProfile

Resolves which AI profile this machine runs - the rules, Plan, apps, artifacts, MCP servers, marketplaces, repository ownership and repository policy every AI command then honours - from `AiProfiles`.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`AiProfiles.Profiles`](../../configuration-reference.md#ai-profiles) | hashtable | `@{}` (empty: profiles off) | One entry per profile: `Rules`, `Plan`, `Deploy`, `Include`, `Exclude`, `McpServers`, `Marketplaces`, `Unattended`, `Owns`, `Autonomous`, `Policies`, `DefaultPolicy`, `MergeWithoutChecks`, `EnvVars`. |
| [`AiProfiles.Hosts`](../../configuration-reference.md#ai-profiles) | hashtable | `@{}` | Hostname to profile name. |
| [`AiProfiles.Default`](../../configuration-reference.md#ai-profiles) | string | `""` | The profile of a host `Hosts` does not name. Empty: such a host runs no profile. |
| [`AiProfiles.Shared`](../../configuration-reference.md#ai-profiles) | array | `@()` | `origin` patterns every profile may work on. |
| [`AiProfiles.DefaultOwner`](../../configuration-reference.md#ai-profiles) | string | `""` (the `Default` profile) | The profile owning a repository no pattern matches. |

The environment variable `WINUX_AI_PROFILE`, when it names a configured profile, wins over `Hosts` and `Default` for the shell it is set in.

## Decisions

1. Do the machines of this configuration need different AI setups - other rules, another Claude Plan, other skills or MCP servers?
    - Options: No - leave `AiProfiles` empty and keep the machine-type forms (`AiArtifacts.Use`, `AiArtifacts.Deploy`); Yes - one profile per setup under `Profiles`.
    - Default: No profile; every AI command behaves as without profiles.
    - More detail: [`AiProfiles`](../../configuration-reference.md#ai-profiles)
2. Which host runs which profile, and which profile does every other host run?
    - Options: `Hosts` entries per hostname, plus a `Default` profile for the rest (or no `Default`, so an unmapped host runs none).
    - Default: No host is mapped and there is no default.
    - More detail: [`AiProfiles.Hosts`](../../configuration-reference.md#ai-profiles)
3. Which Claude Plan may each profile log in to?
    - Options: `Plan = @{ Name = "<plan>"; OrgUuid = "<organization uuid>" }`, or an array of them; read the UUID from `oauthAccount.organizationUuid` of `~\.claude.json` on a machine logged in to that Plan.
    - Default: No Plan: the managed settings pin nothing and `Test-AiProfile` reports a mismatch.
    - More detail: [AI Profiles - The Plan Pin](../../../ai/profiles.md#the-plan-pin)
4. Which repositories does each profile own, which are shared, and who owns the rest?
    - Options: `Owns` patterns per profile (`"github.com/my-org/*"`), `Shared` patterns, a `DefaultOwner`.
    - Default: Nothing is owned explicitly; every repository belongs to the `Default` profile.
    - More detail: [AI Profiles - Repository Ownership](../../../ai/profiles.md#repository-ownership)
5. How far may agents go in each repository a profile works on?
    - Options: `Policies` maps a level to `origin` patterns - `autonomous` (also merge a pull request whose CI checks all passed), `branch` (commit, push a feature branch, open pull requests), `draft` (draft pull requests only), `readonly` (no shell, no file edits), `blocked` (no work); `DefaultPolicy` for every other repository; `MergeWithoutChecks` for `autonomous` repositories without CI that may still merge. `Autonomous` is a synonym of `Policies.autonomous`.
    - Default: Every repository is at `branch`; nothing merges on its own.
    - More detail: [AI Profiles - Repository Policies](../../../ai/profiles.md#repository-policies)
6. What else differs per profile: rules item, harnesses, artifacts, MCP servers, marketplaces, unattended runs, environment variables?
    - Options: `Rules`, `Deploy`, `Include`, `Exclude`, `McpServers` (`@()` for none), `Marketplaces`, `Unattended`, `EnvVars`; leave a key out to keep the global value.
    - Default: The global `AiArtifacts`, `AiMcpServers` and `AiMarketplaces` settings apply unchanged.
    - More detail: [AI Profiles - What A Profile Decides](../../../ai/profiles.md#what-a-profile-decides)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Define the profiles
2. Map the hosts and set the default
3. Classify the repositories
4. Set the repository policy
5. Reload and confirm the merge landed

## Step 1: Define the profiles

```powershell
AiProfiles = @{
    Profiles = @{
        Personal = @{
            Rules      = "MyRules"
            Plan       = @{ Name = "Max"; OrgUuid = "00000000-0000-0000-0000-000000000000" }
            Unattended = $true
        }
        Work     = @{
            Rules      = "MyWorkRules"
            Plan       = @{ Name = "Team"; OrgUuid = "11111111-1111-1111-1111-111111111111" }
            McpServers = @()
        }
    }
}
```

A rules item named here must exist under `AI\Rules\<source>\<Name>\`.

## Step 2: Map the hosts and set the default

```powershell
AiProfiles = @{
    Hosts   = @{ "WORKSTATION-01" = "Work" }
    Default = "Personal"
}
```

## Step 3: Classify the repositories

```powershell
AiProfiles = @{
    Shared       = @("github.com/MyUser/Dotfiles")
    DefaultOwner = "Personal"
    Profiles     = @{
        Work     = @{ Owns = @("github.com/my-org/*") }
    }
}
```

## Step 4: Set the repository policy

```powershell
AiProfiles = @{
    Profiles = @{
        Personal = @{
            Policies           = @{
                autonomous = @("github.com/MyUser/MyProject", "github.com/MyUser/MyPrototype")
                branch     = @("github.com/MyUser/Dotfiles")
            }
            MergeWithoutChecks = @("github.com/MyUser/MyPrototype")
        }
        Work     = @{ DefaultPolicy = "draft" }
    }
}
```

A level name outside `autonomous`, `branch`, `draft`, `readonly`, `blocked` is warned about and its patterns skipped; a `DefaultPolicy` that is not a level becomes `readonly`.

## Step 5: Reload and confirm the merge landed

```powershell
Reload-PowerShellProfile
$aiProfile = Resolve-AiProfile
$aiProfile.Name
$aiProfile.Source
$aiProfile.Warnings
```

## Verification

Read-only checks. None of these change anything.

```powershell
Resolve-AiProfile | Select-Object Enabled, Name, Source, HostName, DefaultOwner
(Resolve-AiProfile -HostName "WORKSTATION-01").Name
(Resolve-AiProfile -Override "Work").Profile.Plans
(Resolve-AiProfile).Profile.Policies
(Resolve-AiProfile).Profile.DefaultPolicy
```

An empty `Warnings` list means every name `Hosts`, `Default` and `DefaultOwner` use is a configured profile and every Plan UUID is valid. Then run [`Test-AiProfile`](Test-AiProfile.md).

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    AiProfiles = @{
        Hosts        = @{ "WORKSTATION-01" = "Work" }
        Default      = "Personal"
        DefaultOwner = "Personal"
        Shared       = @("github.com/MyUser/Dotfiles")
        Profiles     = @{
            Personal = @{
                Rules      = "MyRules"
                Plan       = @{ Name = "Max"; OrgUuid = "00000000-0000-0000-0000-000000000000" }
                McpServers = @("my-remote", "my-local")
                Unattended = $true
                Policies   = @{
                    autonomous = @("github.com/MyUser/MyProject", "github.com/MyUser/MyPrototype")
                    branch     = @("github.com/MyUser/Dotfiles")
                }
                MergeWithoutChecks = @("github.com/MyUser/MyPrototype")
                EnvVars    = @("MY_API_KEY")
            }
            Work     = @{
                Rules         = "MyWorkRules"
                Plan          = @{ Name = "Team"; OrgUuid = "11111111-1111-1111-1111-111111111111" }
                Deploy        = @("claude-code")
                Exclude       = @("skills/my-personal-skill")
                McpServers    = @()
                Unattended    = $false
                Owns          = @("github.com/my-org/*")
                DefaultPolicy = "draft"
            }
        }
    }
}
```

## Related

- [`Resolve-AiProfile` in the AI module reference](../../../modules/ai.md#resolve-aiprofile) - the returned keys
- [AI Profiles](../../../ai/profiles.md) - the design
- [AI configuration guides](README.md) - every guide for this module
- [`Test-AiProfile`](Test-AiProfile.md) and [`Initialize-AiProfile`](Initialize-AiProfile.md) - check and set up a machine
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
