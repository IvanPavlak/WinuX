# AI Skills

Machine-global Agent Skills: `SKILL.md` skills kept in the repository and linked into every AI app on the machine, so they are available in every project without adding anything to any project. Skills are one kind of AI artifact: where they live, how they are vendored and how they are deployed is the mechanism described on [AI Artifacts](artifacts.md). This page covers what is particular to skills.

Skills are **opt-in**: a vanilla bootstrap deploys into no app until `AiArtifacts.Deploy` names one and `BootstrapConfig.Steps.AiArtifacts` is on.

## What a skill is

A skill is a folder `AI\Skills\<source>\<skill>\` holding `SKILL.md` (YAML frontmatter with `name` and `description`, then the instructions) and any supporting files (`scripts\`, format documents, `agents\openai.yaml`). Every app discovers user-level skills from one flat folder of `<skill>/SKILL.md` and none recurses, which is why each skill is linked individually (`Placement = "Each"`, `Files = @(".")`):

| App | User-level skills folder |
| --- | ------------------------ |
| Claude Code | `~/.claude/skills/<skill>/SKILL.md` |
| Codex | `~/.agents/skills/<skill>/SKILL.md` |
| Gemini CLI | `~/.agents/skills` (alias that wins over `~/.gemini/skills`) |
| Copilot | `~/.agents/skills` (VS Code's Copilot also reads `~/.claude/skills`) |

Linking per skill keeps the app folders machine-local: skills installed by other tools sit next to the linked ones, and a deleted skill disappears on the next run because dangling links into the artifacts root are pruned.

## The product skills

WinuX ships two skills in `AI\Skills\winux\`:

- `winux-configurator` - the entry point to the [WinuXConfigurator](../configuration/winux-configurator.md) session: it locates the checkout from its own symbolic link, then reads and runs the protocol document. It also covers what the removed `add-*` prompts did (browser groups, projects, symbolic links, window layouts, workspaces). In a checkout that also holds Foundation, WinuX's macOS counterpart, it writes the Unix counterpart of every entry in the same session (the protocol's ground rule 8).
- `document` - turns a function's comment-based help into its man-style module page entry and its configuration guide, and keeps the manifest and indexes in step.

`own\` ships empty. Leave a product skill out with `AiArtifacts.Exclude = @("skills/winux/document")`.

## Vendored skills

A `Sources` entry with `Skills` folders vendors an upstream's skills ([Vendoring](artifacts.md#vendoring)). Upstreams nest skills by category (`skills/engineering/grill-me`) while every app requires `<skill>/SKILL.md` at the top level, so `Update-AiArtifacts` drops the category level; supporting files are copied as they are.

## Name collisions

A personal skill replaces a bundled skill of the same name in Claude Code, so vendoring an upstream `code-review` hides Claude Code's built-in `/code-review`. Leave such a skill out with `AiArtifacts.Exclude = @("skills/code-review")` if you want the built-in one. Within the repository, `own` wins a name two sources carry, then the first source by name, with a warning.

## Listing what is installed

`List-AiArtifacts -Kind Skills` lists every skill the repository carries, grouped by source, each with the `description:` of its own `SKILL.md`; `List-AiArtifacts -Kind Skills -ListDiscrepancies` checks that each one is linked into every skills destination of the apps turned on. Both read the disk the way `Deploy-AiArtifacts` does, so what is listed is exactly what is deployed.

## Verification (per machine, after enabling)

1. Run `Deploy-AiArtifacts -Kind Skills` (or full `Bootstrap`) as admin.
2. `List-AiArtifacts -Kind Skills -ListDiscrepancies` reports nothing.
3. `~\.claude\skills\<skill>` and `~\.agents\skills\<skill>` are symbolic links into `AI\Skills\<source>\`, and inside WSL `/home/<user>/.claude/skills/<skill>` resolves through `/mnt/<drive>`.
4. In a throwaway folder outside the repository, start the app and confirm the skills appear (`/` in Claude Code, `/skills` in Codex, `gemini skills list`).

## Related

- [AI Artifacts](artifacts.md) - the mechanism, the harness catalogue and migrating from 1.5
- [AI module reference](../modules/ai.md) - `Deploy-AiArtifacts`, `Update-AiArtifacts`, `List-AiArtifacts`
- [Deploy-AiArtifacts configuration guide](../configuration/guides/ai/Deploy-AiArtifacts.md) - the keys, decision by decision
- [CoreAiRules](coreairules.md) - the rules that sit in front of the same apps
