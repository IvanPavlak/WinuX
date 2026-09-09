# AI Skills

Agent Skills linked into every AI coding harness on the machine by `Deploy-AiSkills` (opt-in via `BootstrapConfig.Steps.AiSkills`). Design: [docs/ai/skills.md](../../docs/ai/skills.md).

Layout: one subfolder per source, each holding flat `<skill>/SKILL.md` folders.

- `<source>/` - an upstream vendored by `Update-AiSkills` from `AiSkills.Sources.<source>`; its `UPSTREAM.md` records the pinned commit and lists every vendored skill.
- `own/` - hand-written skills (no manifest; never touched by a refresh).

Upstream WinuX ships only this file. The source folders belong to your fork.
