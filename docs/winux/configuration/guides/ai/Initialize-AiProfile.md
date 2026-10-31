# Initialize-AiProfile

Walks the one-time sign-ins of this machine's AI profile - the Claude Code login to the expected Plan, the GitHub CLI, the OAuth MCP servers and the profile's environment variables - then runs `Test-AiProfile`. Interactive; it never handles a secret itself. Called by Bootstrap when the opt-in `BootstrapConfig.Steps.AiProfileInit` is on.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`AiProfiles`](../../configuration-reference.md#ai-profiles) | hashtable | no profile | The profile walked: its `Plan` (step 1), its `McpServers` (step 3) and its `EnvVars` (step 4). No profile: nothing to do. |
| [`AiMcpServers.Servers`](../../configuration-reference.md#ai-mcp-servers) | hashtable | `@{}` | The OAuth servers among those the profile registers, listed for their `/mcp` sign-in. |
| [`BootstrapConfig.Steps.AiProfileInit`](../../configuration-reference.md#bootstrapconfig) | boolean | `$false` | Whether Bootstrap runs this function, right after the AI MCP servers step. OFF by default - it waits at the terminal, so a run with it off stays unattended and, with a profile active, only names this function. |

## Decisions

1. Which environment variables do this profile's tools need on every machine?
    - Options: Their names in the profile's `EnvVars` (for example a `BearerTokenEnvVar` of an MCP server); never their values.
    - Default: None: step 4 has nothing to check.
    - More detail: [`AiProfiles`](../../configuration-reference.md#ai-profiles)
2. Which MCP servers does this profile register?
    - Options: The profile's `McpServers` (left out: every `AiMcpServers.Servers` entry; `@()`: none).
    - Default: All of them.
    - More detail: [AI MCP Servers - Per AI Profile](../../../ai/mcp-servers.md#per-ai-profile)
3. Should Bootstrap walk the sign-ins at the end of its AI steps?
    - Options: `$true` so a fresh machine ends the run signed in (Bootstrap waits at each sign-in; `Bootstrap -Skip AiProfileInit` runs unattended); `$false` to run `Initialize-AiProfile` by hand once per machine.
    - Default: `$false`: with a profile active, Bootstrap only warns that the sign-ins were skipped and names this function.
    - More detail: [`BootstrapConfig.Steps`](../../configuration-reference.md#bootstrapconfig)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Name the profile's environment variables
2. Deploy, then walk the sign-ins
3. Optionally enable `BootstrapConfig.Steps.AiProfileInit`

## Step 1: Name the profile's environment variables

```powershell
AiProfiles = @{
    Profiles = @{
        Personal = @{ EnvVars = @("MY_API_KEY") }
    }
}
```

## Step 2: Deploy, then walk the sign-ins

```powershell
Reload-PowerShellProfile
Deploy-AiArtifacts
Deploy-AiMcpServers
Initialize-AiProfile
```

Set a missing variable in your own terminal when the step asks for it, for example `[Environment]::SetEnvironmentVariable("MY_API_KEY", "<value>", "User")`, then open a new shell.

## Step 3: Optionally enable `BootstrapConfig.Steps.AiProfileInit`

With the step on and a profile active, Bootstrap runs `Initialize-AiProfile` right after `Deploy-AiMcpServers`, so the Plan pin of the managed settings is deployed before the Claude login is checked. On with no profile active, the step is skipped with a warning.

```powershell
BootstrapConfig = @{
    Steps = @{
        AiProfileInit = $true
    }
}
```

## Verification

Read-only checks. None of these change anything.

```powershell
Resolve-BootstrapSteps | Where-Object Name -eq "AiProfileInit"
Test-AiProfile
$LASTEXITCODE
claude mcp list
gh auth status
```

`Test-AiProfile` exits `0`. It lists the profile's OAuth MCP servers without checking them; `claude mcp list` (which starts every stdio server, so it takes a moment) shows whether each one is signed in.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    AiProfiles      = @{
        Default  = "Personal"
        Profiles = @{
            Personal = @{
                Rules      = "MyRules"
                Plan       = @{ Name = "Max"; OrgUuid = "00000000-0000-0000-0000-000000000000" }
                McpServers = @("my-remote", "my-keyed")
                EnvVars    = @("MY_API_KEY")
            }
        }
    }
    AiMcpServers    = @{
        Deploy  = @{ Default = @("claude-code", "codex") }
        Servers = @{
            "my-remote" = @{ Url = "https://mcp.example.com/mcp" }
            "my-keyed"  = @{ Url = "https://api.example.com/mcp"; BearerTokenEnvVar = "MY_API_KEY" }
        }
    }
    BootstrapConfig = @{
        Steps = @{
            AiProfileInit = $true
        }
    }
}
```

## Related

- [`Initialize-AiProfile` in the AI module reference](../../../modules/ai.md#initialize-aiprofile)
- [AI Profiles - Setting Up A Machine](../../../ai/profiles.md#setting-up-a-machine)
- [AI configuration guides](README.md) - every guide for this module
- [`Test-AiProfile`](Test-AiProfile.md) - the check it ends with
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
