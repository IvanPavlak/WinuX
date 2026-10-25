# CoreAiRules

Always-on, machine-uniform rules for AI coding agents: one rules text every AI app on the machine reads as its global instructions, and, for Claude Code, a managed-settings file that enforces part of it at the tier no project, repository or session setting can override. Rules are one kind of AI artifact: where they live and how they are deployed is the mechanism described on [AI Artifacts](artifacts.md). This page covers what is particular to rules.

The rules are **opt-in and yours**: WinuX ships a skeleton, never a policy, and a vanilla bootstrap deploys nothing until `AiArtifacts.Deploy` names an app and `BootstrapConfig.Steps.AiArtifacts` is on.

## A rules item

A rules item is a folder `AI\Rules\<source>\<Name>\` holding:

- `RULES.md` - the instructions, linked into each app's global instruction file (`File` placement).
- Per-app variants, taken instead of `RULES.md` by the destination that names them: `copilot.md` (Copilot), and Claude Code's `managed-settings.json`.

Only the item `AiArtifacts.Use.Rules` names is deployed; the last wins and a value may be per machine type. The base ships `AI\Rules\example\CoreAiRules\RULES.md` (a skeleton: section headings and one sample rule, "ask before destructive actions") and `Use = @{ Rules = "CoreAiRules" }`. Write your own in `AI\Rules\own\CoreAiRules\` - `own` wins the name clash - and silence the clash warning with `AiArtifacts.Exclude = @("rules/example/CoreAiRules")`.

## Layers, strongest wins

| Layer | File in the rules item | Deployed to | Role |
| ----- | ---------------------- | ----------- | ---- |
| 1. Instructions | `RULES.md` | every app's global instruction file (below) | loaded into every session on the machine, all projects |
| 2. Enforcement | `managed-settings.json` | Claude Code's managed settings path (below) | admin-owned settings: `permissions.ask` rules, hooks, `attribution`; they outrank every project, repository and user file, and Claude Code never writes to them |

Claude Code settings precedence: managed settings > CLI and local > project > user. That is why enforcement belongs in managed settings. `ask` rules give a permission prompt on every matching command in every permission mode, so an explicitly requested action is one approval away; `deny` would force manual terminal work even when wanted. Hooks run in every permission mode and subagents inherit them; `allowManagedHooksOnly` and `allowManagedPermissionRulesOnly` would disable per-project hooks and allow rules, which an enforcement layer rarely needs.

## Deployed paths

Instruction layer (links to `RULES.md`, or the app's variant), from the base catalogue:

| App | Windows | WSL |
| --- | ------- | --- |
| Claude Code | `{User}\.claude\CLAUDE.md` | `/home/<user>/.claude/CLAUDE.md` |
| Codex | `{User}\.codex\AGENTS.md` | `/home/<user>/.codex/AGENTS.md` |
| Gemini CLI | `{User}\.gemini\GEMINI.md` | `/home/<user>/.gemini/GEMINI.md` |
| Copilot | `{User}\.copilot\copilot-instructions.md` | `/home/<user>/.copilot/copilot-instructions.md` |

Enforcement layer (link to `managed-settings.json`, only when the item has one):

| OS | Managed settings path |
| -- | --------------------- |
| Windows | `C:\Program Files\ClaudeCode\managed-settings.json` |
| WSL | `/etc/claude-code/managed-settings.json` (per distribution) |

Claude Code no longer reads the legacy Windows path `C:\ProgramData\ClaudeCode\managed-settings.json`; a link left there from 1.5 has no effect ([managed settings](https://code.claude.com/docs/en/managed-settings)). The WSL link is the `managed-settings` hook of the `claude-code` destination: `/etc` is root-owned, so `Deploy-AiArtifacts` makes that twin with `wsl -u root` (no sudo prompt). The Windows link needs the administrator rights the whole run asks for.

## Deploying

```powershell
# Configuration.local.psd1
@{
    AiArtifacts     = @{
        Exclude = @("rules/example/CoreAiRules")
        Use     = @{ Rules = "CoreAiRules" }
        Deploy  = @{ Default = @("claude-code", "codex", "gemini-cli") }
    }
    BootstrapConfig = @{
        Steps = @{
            AiArtifacts = $true
        }
    }
}
```

`Deploy-AiArtifacts -Kind Rules` deploys only the rules. The 1.5 setup - `PathTemplates.SymbolicLinks.AI` entries, `Deploy-CoreAiRules` and `BootstrapConfig.Steps.CoreAiRules` - keeps working until 2.0.0; see [Migrating from 1.5](artifacts.md#migrating-from-15).

## Verification (per machine, after enabling)

1. Run `Deploy-AiArtifacts -Kind Rules` (or full `Bootstrap`) as admin.
2. `~\.claude\CLAUDE.md`, `~\.codex\AGENTS.md` and `~\.gemini\GEMINI.md` are links into `AI\Rules\<source>\<Name>\`, and so is the managed-settings path of the OS when the item has a `managed-settings.json`.
3. In a throwaway repository, ask the agent for an action your rules restrict: it must follow the instruction layer, and Claude Code must surface the prompt your managed settings demand.

## Known limitations

- **Cloud sessions** (claude.ai/code) have no `~/.claude` and no managed settings. Coverage there comes from each repository's own committed instruction files, so a rule that matters everywhere also belongs in the repository's `AGENTS.md`.
- **Enforcement scope is Claude Code.** Other apps only get the instruction layer; their own permission mechanisms can be added as further variants of the rules item and destinations of their harness.
- **Git symbolic links on Windows.** A git symlink in the repository checks out as a small text file holding its target when `core.symlinks` is false; an app that reads such a file sees a path, not rules. Link the apps straight at `RULES.md` with `Deploy-AiArtifacts` (see [Troubleshooting](../reference/troubleshooting.md)).

## Related

- [AI Artifacts](artifacts.md) - the mechanism, the harness catalogue and migrating from 1.5
- [AI module reference](../modules/ai.md) - `Deploy-AiArtifacts`, `List-AiArtifacts`
- [Deploy-AiArtifacts configuration guide](../configuration/guides/ai/Deploy-AiArtifacts.md) - the keys, decision by decision
- [AI Skills](skills.md) - skills deployed into the same apps
