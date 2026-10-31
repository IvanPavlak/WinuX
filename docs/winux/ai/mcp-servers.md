# AI MCP Servers

How WinuX adds MCP servers to the AI apps a machine uses, from one definition per server. WinuX ships the mechanism and no servers; which servers a machine gets, and in which apps, is the fork's choice in `Configuration.local.psd1`. The command is [Deploy-AiMcpServers](../modules/ai.md#deploy-aimcpservers), and its keys are on the [Deploy-AiMcpServers configuration guide](../configuration/guides/ai/Deploy-AiMcpServers.md).

## Why Servers Are Written, Not Linked

[AI artifacts](artifacts.md) are files: an item folder is linked into a folder the app reads. An MCP server is not a file of its own. Each app keeps its servers inside its own configuration file, next to settings that are not the repository's business:

| App | Where its user-scope servers live | How WinuX writes them |
| --- | --------------------------------- | --------------------- |
| `claude-code` | the `mcpServers` block of `~\.claude.json` (`$CLAUDE_CONFIG_DIR\.claude.json` when set), a file Claude Code rewrites constantly | through the Claude Code CLI: `claude mcp add --scope user`, and `claude mcp remove --scope user` first when the entry differs; the file is only read |
| `codex` | `[mcp_servers.<name>]` tables of `~\.codex\config.toml` (`$CODEX_HOME\config.toml` when set), a file the user also edits | directly: the configured server's table and its subtables are replaced in place or appended, every other line kept |

So MCP servers are their own section, `AiMcpServers`, and their own Bootstrap step, `AiMcpServers`, beside `AiMarketplaces`, which is the same kind of thing: per-machine state that goes into an app's own configuration.

T3 Code and other front ends that drive these agents need nothing of their own: they run the installed Claude Code and Codex, which read their own configuration.

## A Server Definition

```powershell
AiMcpServers = @{
    Deploy  = @{ Default = @("claude-code", "codex") }
    Servers = @{
        "my-remote" = @{ Url = "https://mcp.example.com/mcp" }
        "my-keyed"  = @{ Url = "https://api.example.com/mcp"; BearerTokenEnvVar = "MY_API_KEY" }
        "my-local"  = @{ Command = "npx"; Args = @("-y", "my-mcp-server"); Machine = "PC/Work" }
    }
}
```

The same entry becomes, in each app:

| Definition | Claude Code (`claude mcp add --scope user ...`) | Codex (`config.toml`) |
| ---------- | ----------------------------------------------- | --------------------- |
| `Url` | `--transport http <name> <url>` | `url = "<url>"` |
| `Transport = "sse"` | `--transport sse` | not added: Codex reads stdio and streamable HTTP servers only |
| `Headers` | one `--header "<name>: <value>"` each | `http_headers = { ... }` |
| `BearerTokenEnvVar` | `--header "Authorization: Bearer ${VAR}"`, expanded by Claude Code when it starts | `bearer_token_env_var = "VAR"` |
| `Command`, `Args` | `<name> -- <command> <args>` | `command = "..."`, `args = [...]` |
| `Env` | one `-e NAME=value` each | `env = { ... }` |

`Machine` keeps an entry off the machine types it does not name. `Deploy` picks the apps per machine type, like `AiArtifacts.Deploy` picks the harnesses.

## Secrets and Sign-In

Nothing secret belongs in the repository, and nothing secret has to:

- **OAuth servers** (most hosted ones): give only the `Url`. The tokens are made by signing in and kept in the machine's own credential store, so each machine signs in once per app: `/mcp` in Claude Code, `codex mcp login <name>` in Codex, and once more inside WSL. `Deploy-AiMcpServers` ends a run that deployed such a server with that reminder.
- **API-key servers**: set `BearerTokenEnvVar` to the name of the environment variable that holds the key, and set that variable on the machine (a user environment variable, or a secret manager that exports it). Only the variable's name is written to either app.

## Lifecycle

- **Added** when an app does not carry the server.
- **Updated** when it carries it with another definition: Claude Code's entry is removed and added again, Codex's table is replaced in place.
- **Left alone** when it carries it as configured, so a run changes nothing on a machine that is up to date.
- **Removed only when WinuX registered it.** Every server `Deploy-AiMcpServers` added, updated or found carried exactly as configured is recorded per app (`claude-code`, `codex`, `wsl:claude-code`, `wsl:codex`) in `%LOCALAPPDATA%\WinuX\ai-mcp-servers.state`. A recorded server the [AI profile](profiles.md) no longer lists is removed: `claude mcp remove --scope user <name>`, or its `config.toml` table taken out. A server the user added by hand, or one an app carries with another definition, is never recorded and never removed. Without profiles every configured server is wanted, so nothing is removed; a server taken out of `Servers` altogether stays until it is removed by hand, the same as a plugin taken out of `AiMarketplaces`.

## Per AI Profile

With an [AI profile](profiles.md) active, its `McpServers` list picks which of the `Servers` the machine registers: left out, all of them; `@()`, none. One catalogue in `Servers` therefore serves every machine, and a machine that changes profile drops the servers it no longer lists on its next deploy:

```powershell
AiProfiles = @{
    Profiles = @{
        Personal = @{ McpServers = @("my-remote", "my-local") }
        Work     = @{ McpServers = @() }
    }
}
```

[Test-AiProfile](../modules/ai.md#test-aiprofile) lists the profile's OAuth servers as "sign in once with /mcp, not checked" (it never runs `claude mcp list`, which would start every stdio server), and [Initialize-AiProfile](../modules/ai.md#initialize-aiprofile) walks their `/mcp` sign-in.

## Stdio Servers on Windows

A stdio server's `Command` and `Args` are written as given, to the Windows and the WSL Claude Code alike, so a `Command = "npx"` entry works in both. Pin the package version in `Args` (`"-y", "my-mcp-server@1.2.3"`) so every machine runs the same server. Older Claude Code documentation asked for `cmd /c npx` on native Windows; the current MCP page no longer does, and `cmd` would not exist inside WSL. When a native-Windows `npx` server fails to start, see [Troubleshooting](../reference/troubleshooting.md#an-mcp-server-is-listed-but-its-tools-are-missing).

Inside WSL (`DefaultWSLDistribution` and `DefaultWSLUsername` set), the Codex tables go to the WSL user's `config.toml` through the `\\wsl.localhost` share, and the Claude Code steps run against the Claude Code CLI installed inside WSL. A `claude` that WSL resolves under `/mnt/` is the Windows CLI reached through interop, which would write the Windows profile, so it counts as missing.

## Deploying

Bootstrap runs `Deploy-AiMcpServers` when the step is on; it is off by default, and the base names no servers.

```powershell
BootstrapConfig = @{
    Steps = @{
        AiMcpServers = $true
    }
}
```

## Verification (per machine, after enabling)

1. `Deploy-AiMcpServers` reports every server as added or already configured, and names any app it could not reach.
2. `claude mcp list` lists every server deployed to Claude Code; one that still needs its OAuth sign-in says so.
3. `Select-String -Path ~\.codex\config.toml -Pattern '^\[mcp_servers\.'` lists every server deployed to Codex.
4. In a new session of each app, the servers' tools are available once signed in.

When one of these fails, see [Troubleshooting](../reference/troubleshooting.md#an-mcp-server-is-listed-but-its-tools-are-missing).

## Related

- [AI module reference](../modules/ai.md#deploy-aimcpservers) - the command
- [Deploy-AiMcpServers configuration guide](../configuration/guides/ai/Deploy-AiMcpServers.md) - the keys, decision by decision
- [AI Artifacts](artifacts.md) - the skills, mods, rules, prompts and agents
- [AI Mods - Marketplaces](mods.md#marketplaces) - Claude Code plugins installed through the CLI
