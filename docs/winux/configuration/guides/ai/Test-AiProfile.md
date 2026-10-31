# Test-AiProfile

Checks that this machine runs Claude Code on the Plan its AI profile expects, pinned by the managed settings copy, with no pay-per-use credential anywhere, and sets `$LASTEXITCODE` (`0` match, `1` mismatch or credential, `2` no profile).

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`AiProfiles`](../../configuration-reference.md#ai-profiles) | hashtable | no profile | The profile checked and its expected `Plan`. No profile: exit code `2`. Its `DefaultPolicy`, `Policies` and `MergeWithoutChecks` are listed (informational, never a mismatch). |
| [`AiHarnesses`](../../configuration-reference.md#ai-harnesses) | hashtable | `claude-code` managed settings at `C:\Program Files\ClaudeCode\managed-settings.json` | Where the deployed managed settings are read from (the destination with the `managed-settings` hook). |
| [`AiMcpServers.Servers`](../../configuration-reference.md#ai-mcp-servers) | hashtable | `@{}` | The OAuth servers (a `Url` without `BearerTokenEnvVar` or `Authorization` header) the profile registers, listed as "sign in once with /mcp, not checked" (no sign-in is checked, and the list does not change the exit code). |

## Decisions

1. Which Plan should this machine be logged in to?
    - Options: The profile's `Plan` (one entry, or several when more than one organization is allowed).
    - Default: None: the check fails until the profile names a Plan.
    - More detail: [`AiProfiles`](../../configuration-reference.md#ai-profiles)
2. Is each repository at the level you expect?
    - Options: Read the `Default policy` and `Policy` lines it prints; change `Policies` or `DefaultPolicy` and redeploy.
    - Default: Every repository at `branch`.
    - More detail: [AI Profiles - Repository Policies](../../../ai/profiles.md#repository-policies)
3. Has the managed settings copy been deployed since the profile last changed?
    - Options: Run `Deploy-AiArtifacts -Kind Rules` as administrator after any `AiProfiles` or rules item change.
    - Default: A stale or missing copy is reported as a mismatch.
    - More detail: [CoreAiRules - Managed settings copy](../../../ai/coreairules.md#managed-settings-copy)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Give the profile its Plan
2. Deploy the managed settings copy
3. Run the check

## Step 1: Give the profile its Plan

```powershell
AiProfiles = @{
    Default  = "Personal"
    Profiles = @{
        Personal = @{ Rules = "MyRules"; Plan = @{ Name = "Max"; OrgUuid = "00000000-0000-0000-0000-000000000000" } }
    }
}
```

## Step 2: Deploy the managed settings copy

```powershell
Reload-PowerShellProfile
Deploy-AiArtifacts -Kind Rules
```

## Step 3: Run the check

```powershell
Test-AiProfile
$LASTEXITCODE
```

## Verification

Read-only checks. None of these change anything.

```powershell
Test-AiProfile -PassThru | Select-Object ExitCode, Profile, Source, Pinned, Credentials, OAuthMcp, DefaultPolicy
(Test-AiProfile -PassThru).Policies
(Test-AiProfile -PassThru).Problems
```

A credential is reported by name and place only. Remove it where it is set (an environment variable, a line of a shell profile, `apiKeyHelper` in a settings file), open a new shell and run the check again.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    AiProfiles   = @{
        Hosts    = @{ "WORKSTATION-01" = "Work" }
        Default  = "Personal"
        Profiles = @{
            Personal = @{ Rules = "MyRules"; Plan = @{ Name = "Max"; OrgUuid = "00000000-0000-0000-0000-000000000000" }; McpServers = @("my-remote"); Policies = @{ autonomous = @("github.com/MyUser/MyProject") } }
            Work     = @{ Rules = "MyWorkRules"; Plan = @{ Name = "Team"; OrgUuid = "11111111-1111-1111-1111-111111111111" }; McpServers = @() }
        }
    }
    AiMcpServers = @{
        Deploy  = @{ Default = @("claude-code") }
        Servers = @{ "my-remote" = @{ Url = "https://mcp.example.com/mcp" } }
    }
}
```

## Related

- [`Test-AiProfile` in the AI module reference](../../../modules/ai.md#test-aiprofile)
- [AI Profiles](../../../ai/profiles.md) - the design
- [AI configuration guides](README.md) - every guide for this module
- [`Resolve-AiProfile`](Resolve-AiProfile.md) - the profile keys, decision by decision
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
