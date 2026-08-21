# CoreAiRules

Always-enforced, machine-uniform rules for AI coding agents: **no commit, no push, no destructive git, no AI co-author attribution, ever on the agent's own initiative; explicit requests still require a confirmation prompt.** Deployed through Bootstrap so every machine gets them, and (for Claude Code) placed at the managed-settings tier so they take precedence over every project, repository, and session setting.

CoreAiRules is **opt-in**: the payloads ship with WinuX, but a vanilla bootstrap deploys nothing. Machine-global AI policy is only applied when a fork enables it in `Configuration.local.psd1` (the `BootstrapConfig.Steps.CoreAiRules` toggle plus the `PathTemplates.SymbolicLinks` entries below).

## Design: layers, strongest wins

The instruction layer is harness-agnostic: one canonical rules file, [`AI/CoreAiRules.md`](https://github.com/IvanPavlak/WinuX/blob/master/AI/CoreAiRules.md), is symlinked into the global instruction file of every harness in use, so the same text governs Claude Code, Codex, Gemini CLI, and anything else that reads one of those files. The enforcement layer is per-harness; today only Claude Code has one (managed settings), and future harness-specific artifacts get their own `AI/<Harness>/` folder next to `AI/Claude/`.

| Layer           | Artifact in the repo              | Deployed to                                            | Role                                                                                                                                                    |
| --------------- | --------------------------------- | ------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1. Instructions | `AI/CoreAiRules.md`                 | Every harness's global instruction file (table below) | Loaded into every session on the machine, all projects. Tells the agent the rules and the confirmation protocol                                        |
| 2. Enforcement  | `AI/Claude/managed-settings.json` | Claude Code's managed settings path (table below)      | `permissions.ask` rules plus a PreToolUse hook physically force a prompt on every commit/push-class command, in every permission mode including bypass |
| 3. Attribution  | same `managed-settings.json`      | same                                                   | `"attribution": { "commit": "", "pr": "" }` removes the Claude co-author trailer and PR footer everywhere, and no lower-precedence file can re-add it  |

Claude Code settings precedence: managed settings (admin-owned) > CLI/local > project > user. Managed settings cannot be overridden by any project, repo `.claude/settings.json`, or user file, and Claude Code never writes to them. That is why enforcement lives there.

Why `ask` and not `deny`: the requirement is "if I ask explicitly, still confirm". `ask` produces exactly that, a permission prompt on every commit/push attempt, so nothing ever lands without a click, but an explicitly requested commit is one approval away. `deny` would force manual terminal work even when wanted.

## Deployed paths

Instruction layer (all symlinks to `AI/CoreAiRules.md`):

| Harness     | Windows                    | WSL (in-distro)                  |
| ----------- | -------------------------- | -------------------------------- |
| Claude Code | `{User}\.claude\CLAUDE.md` | `/home/<user>/.claude/CLAUDE.md` |
| Codex CLI   | `{User}\.codex\AGENTS.md`  | `/home/<user>/.codex/AGENTS.md`  |
| Gemini CLI  | `{User}\.gemini\GEMINI.md` | `/home/<user>/.gemini/GEMINI.md` |

Enforcement layer (symlink to `AI/Claude/managed-settings.json`):

| OS      | Managed settings path                                       |
| ------- | ------------------------------------------------------------ |
| Windows | `C:\ProgramData\ClaudeCode\managed-settings.json`            |
| WSL     | `/etc/claude-code/managed-settings.json` (per distribution) |

Linux and macOS deployment arrives with the future Unix bootstrap (their Claude Code managed paths are `/etc/claude-code/` and `/Library/Application Support/ClaudeCode/` respectively).

## How it deploys

- **Windows and WSL home-directory links**: regular `PathTemplates.SymbolicLinks` entries (the commented `AI` opt-in block in `Configuration.psd1` is the template - copy it into `Configuration.local.psd1`), created and self-healed by [SymbolicLinkMaker](../modules/system.md#symboliclinkmaker) on every Bootstrap run. The managed-settings entry uses a literal `C:\ProgramData\...` path (no placeholder exists for ProgramData; literals pass through expansion untouched) with backslashes only, because any forward slash routes an entry to the WSL branch.
- **WSL `/etc/claude-code`**: created by [Deploy-CoreAiRules](../modules/system.md#deploy-coreairules), gated behind the opt-in `BootstrapConfig.Steps.CoreAiRules` toggle (OFF by default). It exists because `/etc` is root-owned and SymbolicLinkMaker's WSL branch never elevates, while `Deploy-CoreAiRules` runs its `wsl.exe` calls as root. It no-ops when the configured WSL distribution is not installed.

Enable it in `Configuration.local.psd1`:

```powershell
BootstrapConfig = @{
    Steps = @{
        CoreAiRules = $true
    }
}

# Plus the SymbolicLinks entries - copy the commented AI block from the base
# Configuration.psd1 into your PathTemplates.SymbolicLinks and adjust the WSL username.
```

## Managed settings notes

- The permission rules are prefix matches per (sub)command; the PreToolUse hook additionally scans the full raw command text on stdin, so compound commands (`git add && git commit && git push`), `git -C <path> push`, and quoting tricks still trigger the prompt. Hooks run in every permission mode, and subagents inherit them.
- The hook is deliberately jq-free (`sed` + `grep` on the stdin JSON) so it works on a fresh Git Bash/macOS/Linux with zero dependencies. The `sed` pass turns JSON `\n`/`\t`/`\r` escapes into spaces first, so a commit on the second line of a multi-line command still triggers, and the regex allows arbitrary tokens between `git` and the subcommand, so `git -C <path> push` triggers too. A false positive (a command that merely mentions "git push" in a string) costs one extra prompt, never a block, which is acceptable for `ask` semantics.
- `allowManagedHooksOnly` and `allowManagedPermissionRulesOnly` are deliberately NOT set: they would disable per-project hooks and allow rules (project formatter/doc hooks, repo allowlists), which is collateral damage CoreAiRules does not need. Managed `ask`/`deny` already outrank everything.
- Windows caveat: hooks run through bash when Git Bash is present (it is, via Git, which the bootstrap installs).
- `attribution` governs Claude Code's built-in commit/PR flow, and `includeCoAuthoredBy: false` covers older versions of the same switch. A confirmation prompt also means the commit message (and any trailer) is visible before anything is created.

## Verification (per machine, after enabling)

1. Run `SymbolicLinkMaker` (or full `Bootstrap`) as admin, then `Deploy-CoreAiRules`.
2. Check `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, and `~/.gemini/GEMINI.md` are symlinks into the repo, and the managed-settings path for the OS resolves.
3. In a throwaway repo, ask Claude to commit: it must (a) ask for confirmation in chat per CoreAiRules, and (b) even after a yes, surface a permission prompt from the `ask` rule. Any created commit must have no co-author trailer.

## Known limitations

- **Cloud sessions (claude.ai/code)** have no `~/.claude` and no managed settings. Coverage there comes from each repository's own committed instruction files; this repo's `AGENTS.md` and `AI/Context/*.md` safety blocks stay in place (they are exactly what covers cloud and repo-scoped sessions), so the rule text intentionally has a repo-scoped home besides `AI/CoreAiRules.md`.
- Enforcement scope is Claude Code. Other harnesses (Codex, Gemini, Copilot, and so on) only get the instruction layer; their own permission mechanisms are weaker or unstable and can be added later as `AI/<Harness>/` artifacts.
- Managed paths need admin/sudo once per machine, which is already true for the bootstrap as a whole.
