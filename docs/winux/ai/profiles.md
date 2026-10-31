# AI Profiles

How one WinuX configuration gives each machine its own AI setup: which rules its agents follow, which Claude Plan it may log in to, which apps, skills, MCP servers and marketplaces it gets, whether it may run agents unattended, which repositories its agents may touch, and how far they may go in each. WinuX ships the mechanism and no profile; the profiles are the fork's, in `Configuration.local.psd1`. The keys are on the [configuration reference](../configuration/configuration-reference.md#ai-profiles), and the commands on the [AI module page](../modules/ai.md).

## One Profile Per Machine

Each machine runs exactly one AI profile, resolved once per command by [Resolve-AiProfile](../modules/ai.md#resolve-aiprofile):

1. the `WINUX_AI_PROFILE` environment variable, when it names a configured profile (one that names none is warned about and ignored);
2. this host's entry in `AiProfiles.Hosts` (`$env:COMPUTERNAME`, case-insensitive);
3. `AiProfiles.Default`.

With no profile configured, or none that resolves, profiles are off: every AI command behaves exactly as without them, scoped by machine type (`AiArtifacts.Use`, `AiArtifacts.Deploy`, `AiArtifacts.Exclude`, the MCP server `Machine` key). Those forms keep working with profiles on too; a profile value wins where it sets one.

```powershell
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
                autonomous = @("github.com/MyUser/MyProject")
                branch     = @("github.com/MyUser/Dotfiles")
            }
        }
        Work     = @{
            Rules         = "MyWorkRules"
            Plan          = @{ Name = "Team"; OrgUuid = "11111111-1111-1111-1111-111111111111" }
            Exclude       = @("skills/my-personal-skill")
            McpServers    = @()
            Unattended    = $false
            Owns          = @("github.com/my-org/*")
            DefaultPolicy = "draft"
        }
    }
}
```

## What A Profile Decides

| Key | Effect | Read by |
| --- | ------ | ------- |
| `Rules` | the rules item deployed as CLAUDE.md, AGENTS.md, GEMINI.md and the managed settings (wins over `AiArtifacts.Use.Rules`) | [Deploy-AiArtifacts](../modules/ai.md#deploy-aiartifacts) |
| `Plan` | `forceLoginOrgUUID` of the managed settings copy: Claude Code refuses any other organization's login, and API-key sessions | [Deploy-AiManagedSettings](../modules/ai.md#deploy-aimanagedsettings), [Test-AiProfile](../modules/ai.md#test-aiprofile) |
| `Deploy` | the harnesses (wins over `AiArtifacts.Deploy`) | Deploy-AiArtifacts |
| `Include`, `Exclude` | which artifacts: `Include` limits a kind it names, `Exclude` joins the global excludes | [Get-AiArtifactRoster](../modules/ai.md#get-aiartifactroster) |
| `McpServers` | which `AiMcpServers.Servers` are registered (left out: all; `@()`: none); a server WinuX registered earlier and no longer listed is removed | [Deploy-AiMcpServers](../modules/ai.md#deploy-aimcpservers) |
| `Marketplaces` | which `AiMarketplaces.Marketplaces` are registered (left out: all; `@()`: none) | [Deploy-AiMarketplaces](../modules/ai.md#deploy-aimarketplaces) |
| `Unattended` | whether unattended agent runs are allowed (`unattended on` or `unattended off` in `ai-profile.conf`) | the ownership guard, orchestration |
| `Owns` | the repositories it owns | the ownership guard |
| `Policies`, `DefaultPolicy`, `MergeWithoutChecks` | the trust level of each repository it works on (see [Repository Policies](#repository-policies)); `Autonomous` is a synonym of `Policies.autonomous` | the repository policy hook, the ownership guard, [Test-AiProfile](../modules/ai.md#test-aiprofile) |
| `EnvVars` | the environment variables its tools need | [Initialize-AiProfile](../modules/ai.md#initialize-aiprofile) |

Manifest rows can be scoped to profiles too (`scope` = profile names): see [AI Artifacts - Manifest sources](artifacts.md#manifest-sources).

## The Plan Pin

A profile's `Plan` reaches Claude Code through the managed settings copy, the one settings tier no project, repository or user file can override (see [CoreAiRules - Managed settings copy](coreairules.md#managed-settings-copy)). With `forceLoginOrgUUID` set, Claude Code refuses at startup a login of any organization the list does not name, and with it every session authenticated by `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN` or `apiKeyHelper`. A Plan that is configured but unusable (an `OrgUuid` that is not a UUID) fails closed: the deploy writes no managed settings copy and leaves the deployed one, pin included, as it is, and `Test-AiProfile` reports a mismatch; a copy without the pin would let any Plan sign in. Moving a profile to another Plan is one configuration value and a redeploy; after a login change every open session must restart, since a session keeps the login it started with.

[Test-AiProfile](../modules/ai.md#test-aiprofile) checks a machine: the profile and how it was picked, the expected Plan, the logged-in Plan (`oauthAccount` of `~\.claude.json`), whether the deployed copy pins exactly the expected UUIDs, every pay-per-use credential (`ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN` in the process, user and machine environment and the shell profiles, `apiKeyHelper` in any Claude settings file), and the profile's OAuth MCP servers, listed as "sign in once with /mcp, not checked". It sets `$LASTEXITCODE` to `0` on a match, `1` on any mismatch or credential, `2` with no profile.

## Repository Ownership

Every repository belongs to one profile, decided from its `origin` remote normalised to `host/owner/name` (lowercase, no scheme, no user, no `.git`):

1. a `Shared` pattern matches: every profile may work on it;
2. a profile's `Owns` pattern matches: that profile owns it (the first matching line wins);
3. otherwise: `DefaultOwner` (empty: `Default`).

With a profile active, `Deploy-AiArtifacts` writes these patterns into `ai-profile.conf` next to the managed settings copy and wires `ai-ownership-guard.sh` into the `UserPromptSubmit` and `PreToolUse` hooks. The guard blocks a prompt or a tool call whose working folder is a repository another profile owns; a folder outside any repository, or a repository without `origin`, is allowed. Verdicts are cached per session and folder, so a tool call costs one file read after the first. The same guard ships in Foundation for macOS, so the two systems refuse the same repositories.

```text
# Written by Deploy-AiArtifacts from the AI profile configuration; do not edit.
profile Personal
default-owner Personal
unattended on
plan Max 00000000-0000-0000-0000-000000000000
shared github.com/myuser/dotfiles
owns Work github.com/my-org/*
autonomous github.com/myuser/myproject
default-policy branch
policy autonomous github.com/myuser/myproject
policy branch github.com/myuser/dotfiles
```

`autonomous`, `default-policy`, `policy` and `merge-without-checks` lines are the active profile's only.

## Repository Policies

A profile gives each repository it works on a trust level, and one hook enforces the level of the repository a session works in. The levels are a closed set, from most to least trust:

| Level | Agents may | Agents may not |
| --- | --- | --- |
| `autonomous` | everything `branch` allows, plus `gh pr merge` when every CI check of the pull request passed | merge with a failing or pending check, or with no check reported (unless the repository is in `MergeWithoutChecks`) |
| `branch` | commit, push a non-default branch, open and ready pull requests | merge |
| `draft` | commit, push a non-default branch, open draft pull requests (`gh pr create --draft`) | `gh pr ready`, merge, a pull request without `--draft` |
| `readonly` | read, search and explain: the reading tools | any Bash or PowerShell call, and the Edit, Write, MultiEdit and NotebookEdit tools |
| `blocked` | nothing: the ownership guard refuses the prompt and every tool call | |

Every level keeps the always-denied list: a push to the default branch (an explicit `master`/`main`/default refspec, or a plain push while it is checked out), a force push (`--force`, `--force-with-lease`, `-f`, `+refspec`), deleting a branch, changing remotes, upstream tracking or git configuration, and a branch cut from a remote branch without `--no-track`.

- `Policies` maps a level to `origin` patterns, normalised like `Owns`. `Autonomous` is a synonym of `Policies.autonomous`, and both may be set. A level name outside the set is warned about and its patterns skipped, so a typo cannot invent a looser level.
- `DefaultPolicy` is the level of a repository no pattern matches, and of a folder outside any repository or without `origin`. Left out it is `branch`; a value that is not a level is warned about and becomes `readonly`.
- Where patterns of several levels match one repository, the least trusting level wins: `ai-profile.conf` lists the levels most trust first, and the hooks take the last matching line.
- `MergeWithoutChecks` lists `autonomous` repositories that may merge a pull request when `gh pr checks` reports no check at all. Left out, "no checks reported" is not green: a repository without CI never merges on its own. A failing or pending check refuses the merge everywhere.

The hook is `AI/Hooks/ai-repository-policy.sh`, one file for WinuX and Foundation (a `mirror` line in both manifests), deployed next to the managed settings copy and wired into `PreToolUse` with matcher `*`, so the file tools are stopped too. It matches a command as a whole, with prose taken out first: the body of a heredoc fed to `cat` or to a `-F -` option, and a quoted value with whitespace given to a message option (`-m`, `--message`, `-t`, `--title`, `-b`, `--body`, `--notes`, `--subject`, a PowerShell here-string included). A commit message that mentions "configuration" or "git push --force" passes; a refspec or flag never holds whitespace, so nothing can be hidden that way. Any review a merge also needs (a judge score, say) is the agent's own check, not the hook's.

**Unattended runs.** The launcher of an unattended run (the orchestrator) sets the `AI_UNATTENDED` environment variable (`1`, `on`, `true` or `yes`). The ownership guard then refuses the run when the profile has `Unattended = $false`, and in a repository at `draft` or `readonly`: unattended work needs `autonomous` or `branch`. An attended session is not affected.

[Test-AiProfile](../modules/ai.md#test-aiprofile) lists the default level, every configured pattern with its level and the `MergeWithoutChecks` patterns; the list never changes its exit code.

## Setting Up A Machine

Once per machine, after Bootstrap, run [Initialize-AiProfile](../modules/ai.md#initialize-aiprofile) at the keyboard, or let Bootstrap run it as its opt-in step `AiProfileInit` (`BootstrapConfig.Steps.AiProfileInit = $true`), right after the AI MCP servers so the Plan pin is deployed before the login is checked. The step waits at the terminal, so it ships off and a run with it off stays unattended, only warning that the sign-ins were skipped. It never asks for a secret: it compares the logged-in Plan with the profile's and says which Plan to `/login` to, runs `gh auth login` when the GitHub CLI is not signed in, lists the profile's OAuth MCP servers for their `/mcp` sign-in, checks the profile's `EnvVars` are set (by name, never by value) and prints the command to set a missing one yourself, then runs `Test-AiProfile`. A machine whose profile allows unattended runs also wants `PowerTimeouts` so it never sleeps on mains power (see [Set-PowerPlan](../modules/system.md#set-powerplan)).

## Verification (per machine)

1. `(Resolve-AiProfile).Name` names the expected profile; `$env:WINUX_AI_PROFILE = "<Other>"; (Resolve-AiProfile).Source` says `override`.
2. `Deploy-AiArtifacts -Kind Rules -WhatIf` reports nothing missing after a deploy.
3. `Test-AiProfile` exits `0`.
4. In a repository another profile owns, a prompt in Claude Code is refused by the guard; in a shared one it is not.
5. In a `branch` repository an agent pushes a feature branch and opens a pull request, but `gh pr merge` is refused; in an `autonomous` one with every check green it merges; in a `readonly` one it cannot run a shell command or edit a file.

## Related

- [AI Artifacts](artifacts.md) - the mechanism, checkout and manifest sources
- [CoreAiRules](coreairules.md) - rules items and the managed settings copy
- [AI MCP Servers](mcp-servers.md) - servers per profile and their removal
- [Configuration reference - AI Profiles](../configuration/configuration-reference.md#ai-profiles)
- [Resolve-AiProfile configuration guide](../configuration/guides/ai/Resolve-AiProfile.md)
