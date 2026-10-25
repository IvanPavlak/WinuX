# AI Skills

Agent Skills, one kind of AI artifact, linked into the AI apps a machine uses by `Deploy-AiArtifacts` (opt-in via `BootstrapConfig.Steps.AiArtifacts`, the apps named by `AiArtifacts.Deploy`). Design: [docs/ai/artifacts.md](../../docs/ai/artifacts.md); what is particular to skills: [docs/ai/skills.md](../../docs/ai/skills.md).

Layout: one subfolder per source, each holding flat `<skill>/SKILL.md` folders.

- `own/` - your own skills (no manifest; never touched by a refresh). Read first, so an `own` skill wins a name clash. WinuX ships it empty.
- `winux/` - the product skills WinuX ships: [winux-configurator](winux/winux-configurator/SKILL.md), which runs the [AI-assisted configuration session](../../docs/configuration/winux-configurator.md), and [document](winux/document/SKILL.md), which turns a function's comment-based help into its module page entry and configuration guide. Leave one out with `AiArtifacts.Exclude = @("skills/winux/document")`.
- `<source>/` - an upstream vendored by `Update-AiArtifacts` from `AiArtifacts.Sources.<source>`; its `UPSTREAM.md` records the pinned commit and lists every vendored skill.

Any other folder is not read.
