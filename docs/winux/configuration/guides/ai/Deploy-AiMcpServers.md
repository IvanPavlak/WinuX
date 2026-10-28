# Deploy-AiMcpServers

Adds the configured MCP servers to Claude Code (through its CLI, at user scope) and to Codex (as tables of its `config.toml`), on Windows and inside WSL, so a server reaches every machine and both apps from one configuration entry.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`AiMcpServers.Deploy`](../../configuration-reference.md#ai-mcp-servers) | hashtable or array | empty | The apps to add the servers to, per machine type with a `Default` fallback, or one array for every machine type: `claude-code`, `codex`. |
| [`AiMcpServers.Servers`](../../configuration-reference.md#ai-mcp-servers) | hashtable | empty | The servers, keyed by name: a `Url` (with optional `Transport`, `Headers`, `BearerTokenEnvVar`) or a `Command` (with optional `Args`, `Env`), and an optional `Machine` scope. |
| [`BootstrapConfig.Steps.AiMcpServers`](../../configuration-reference.md#bootstrapconfig) | boolean | `$false` | Whether Bootstrap runs this function. OFF by default - the base names no servers. |
| [`DefaultWSLDistribution`](../../configuration-reference.md#wsl-configuration) | string | empty string | The WSL distribution whose user also receives the servers. Empty means Windows only. |
| [`DefaultWSLUsername`](../../configuration-reference.md#wsl-configuration) | string | empty string | The WSL account whose `~/.claude.json` and `~/.codex/config.toml` also receive the servers. Empty means Windows only. |
| [`ValidMachineTypes`](../../configuration-reference.md#valid-machine-types) | array of strings | `@("Test")` | The tokens a server's `Machine` scope is checked against (through `Test-MachineTypeScope`); an unknown token is reported and never matches. |

The apps' files are not configuration keys: Claude Code's is the user's `~\.claude.json` (`$env:CLAUDE_CONFIG_DIR\.claude.json` when that variable is set), which this function only reads, since the CLI writes it; Codex's is `~\.codex\config.toml` (`$env:CODEX_HOME\config.toml` when set), where only the `[mcp_servers.<name>]` tables of the configured servers are written and every other line is kept. Inside WSL the Claude Code steps run against the Claude Code CLI installed there; without one (or with only the Windows CLI reached through `/mnt/`) the WSL Claude Code half only warns.

## Decisions

1. Which apps should get the servers, on which machine types?
    - Options: `claude-code`, `codex`, or both, under `Deploy.Default`, with a key per machine type that differs (`Work = @("claude-code")`); or one array for every machine type.
    - Default: None - the base names no app, so nothing is added.
    - More detail: [`AiMcpServers.Deploy`](../../configuration-reference.md#ai-mcp-servers)
2. Which servers should every machine have?
    - Options: A remote server is a `Url`; one that runs on the machine is a `Command` with its `Args` (and `Env` for the variables it reads). The key is the name both apps list it under.
    - Default: None.
    - More detail: [`AiMcpServers.Servers`](../../configuration-reference.md#ai-mcp-servers)
3. How does each remote server authenticate?
    - Options: Most remote servers sign in with OAuth: give them only the `Url`, and sign in once per machine and app (`/mcp` in Claude Code, `codex mcp login <name>`), because the tokens stay in the machine's credential store and no configuration can carry them. A server that takes an API key gets `BearerTokenEnvVar`, the name of the environment variable holding it: the key itself never enters the repository. Static, non-secret headers (a project name) go under `Headers`.
    - Default: OAuth (no `BearerTokenEnvVar`).
    - More detail: [`AiMcpServers.Servers`](../../configuration-reference.md#ai-mcp-servers)
4. Is any server for some machine types only?
    - Options: `Machine = "PC/Work"` on its entry; leave it out for every machine type.
    - Default: Every machine type.
    - More detail: [`AiMcpServers.Servers`](../../configuration-reference.md#ai-mcp-servers)
5. Should Bootstrap add the servers on every run?
    - Options: `$true` to add and update the servers on every Bootstrap (a server already configured is left alone); `$false` to run `Deploy-AiMcpServers` by hand.
    - Default: `$false`.
    - More detail: [`BootstrapConfig.Steps`](../../configuration-reference.md#bootstrapconfig)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one server leaves every other entry alone. **Arrays and scalars replace wholesale**, so a `Deploy.Default` or `Args` array you supply replaces the base one entirely.

## Steps Overview

1. Name the apps under `AiMcpServers.Deploy`
2. Name the servers under `AiMcpServers.Servers`
3. Enable `BootstrapConfig.Steps.AiMcpServers`
4. Reload and confirm the merge landed
5. Sign in to the OAuth servers once on each machine

## Step 1: Name the apps

```powershell
AiMcpServers = @{
    Deploy = @{
        Default = @("claude-code", "codex")
        Work    = @("claude-code")
    }
}
```

## Step 2: Name the servers

A server is a `Url` or a `Command`, never both. `Transport = "sse"` marks an SSE server, which reaches Claude Code only (Codex reads stdio and streamable HTTP servers).

```powershell
AiMcpServers = @{
    Servers = @{
        "my-remote" = @{ Url = "https://mcp.example.com/mcp" }
        "my-keyed"  = @{
            Url               = "https://api.example.com/mcp"
            Headers           = @{ "X-Project" = "MyProject" }
            BearerTokenEnvVar = "MY_API_KEY"
        }
        "my-local"  = @{
            Command = "npx"
            Args    = @("-y", "my-mcp-server")
            Env     = @{ LOG_LEVEL = "info" }
            Machine = "PC/Work"
        }
    }
}
```

## Step 3: Enable `BootstrapConfig.Steps.AiMcpServers`

With the step on, Bootstrap runs `Deploy-AiMcpServers` right after `Deploy-AiMarketplaces`. Servers are added and updated, never removed: take a server out of the configuration and remove it from the apps by hand (`claude mcp remove --scope user <name>`, and its table in `config.toml`).

```powershell
BootstrapConfig = @{
    Steps = @{
        AiMcpServers = $true
    }
}
```

## Step 4: Reload and confirm the merge landed

```powershell
Reload-PowerShellProfile
Get-ConfigSetting -Path 'AiMcpServers'
```

## Step 5: Sign in to the OAuth servers

Once per machine (and inside WSL, once more for the WSL user), for each server that signs in with OAuth:

```powershell
claude      # then /mcp, pick the server and sign in
codex mcp login my-remote
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
Resolve-BootstrapSteps | Where-Object Name -eq "AiMcpServers"
(Get-Content "$env:USERPROFILE\.claude.json" -Raw | ConvertFrom-Json -AsHashtable).mcpServers
Select-String -Path "$env:USERPROFILE\.codex\config.toml" -Pattern '^\[mcp_servers\.'
claude mcp list
```

`claude mcp list` connects to every server to report its health, so it takes a moment; a server waiting for its OAuth sign-in shows as needing authentication. If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    DefaultWSLDistribution = "Ubuntu"
    DefaultWSLUsername     = "you"
    AiMcpServers           = @{
        Deploy  = @{
            Default = @("claude-code", "codex")
            Work    = @("claude-code")
        }
        Servers = @{
            "my-remote" = @{ Url = "https://mcp.example.com/mcp" }
            "my-keyed"  = @{
                Url               = "https://api.example.com/mcp"
                Headers           = @{ "X-Project" = "MyProject" }
                BearerTokenEnvVar = "MY_API_KEY"
            }
            "my-local"  = @{
                Command = "npx"
                Args    = @("-y", "my-mcp-server")
                Env     = @{ LOG_LEVEL = "info" }
                Machine = "PC/Work"
            }
        }
    }
    BootstrapConfig        = @{
        Steps = @{
            AiMcpServers = $true
        }
    }
}
```

## Related

- [`Deploy-AiMcpServers` in the AI module reference](../../../modules/ai.md#deploy-aimcpservers) - parameters, usage and behaviour
- [AI MCP Servers](../../../ai/mcp-servers.md) - the design: why servers are written, not linked, and how each app stores them
- [AI configuration guides](README.md) - every guide for this module
- [`Deploy-AiMarketplaces`](Deploy-AiMarketplaces.md) - the other Claude Code CLI step, for plugin marketplaces
- [`Deploy-AiArtifacts`](Deploy-AiArtifacts.md) - the skills, mods, rules, prompts and agents
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
