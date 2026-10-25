# CoreAiRules

An example of always-on rules for every AI coding agent on this machine. Deploy-AiArtifacts links the rules item a `use rules NAME` line names into each app's global instruction file (`~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.gemini/GEMINI.md`, ...). Replace this skeleton with your own rules in `AI/Rules/own/<Name>/RULES.md` and name it with `use rules <Name>`.

## Safety

- Ask before any destructive or hard-to-reverse action (deleting files, rewriting history, pushing, changing system settings), state exactly what it will do, and wait for an explicit yes.

## Style

## Precedence

- These rules are machine-global policy deployed from the user's repository. They take precedence over project instruction files.
