# AI Mods

Claude Code mods (function-hook plugins that draw bands, panes and status entries and hook engine events) linked into `~/.claude/mods` and listed in the `env.CLAUDE_CODE_PLUGIN_DIRS` key of `~/.claude/settings.json` by `Deploy-AiMods` (opt-in via `BootstrapConfig.Steps.AiMods`). Design: [docs/ai/mods.md](../../docs/ai/mods.md).

Layout: one subfolder per source, each holding `<mod>/` folders. A folder is a mod when it holds `.claude-plugin/plugin.json`; the rest of a mod is its hooks module (`hooks/hooks.json` naming `hooks/register.tsx`) and, when it keeps values in `$.state`, its type contract (`types/index.d.ts`).

- `<source>/` - an upstream vendored by `Update-AiMods` from `AiMods.Sources.<source>`, pinned to a commit; its `UPSTREAM.md` records the commit and lists every vendored mod, next to the upstream license. Never edit these folders by hand - change the mod upstream and re-run `Update-AiMods -Source <source>`.
- `own/` - hand-written mods (no manifest; never touched by a refresh).

Authoring a mod: load the `plugin-authoring` skill in Claude Code, which writes the engine's type declarations and hot-reloads the mod while you work; check it with `claude plugin validate <folder>` and run its tests with `claude plugin test <folder>`.

Upstream WinuX ships only this file. Every source folder belongs to your fork.
