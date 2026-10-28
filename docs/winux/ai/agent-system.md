# Agent System

WinuX gives AI agents two things, kept apart on purpose:

- **Contributor guidance** - how to work on this repository: `AGENTS.md`, `AI/Context/`, `AI/Instructions/` and the file-type-scoped instructions in `.github/instructions/`, auto-loaded by `applyTo` patterns. It is the project's development process, like `CONTRIBUTING.md`, and ships with WinuX.
- **AI artifacts** - the skills, mods, rules, prompts and agents a machine's AI apps load in every project. WinuX ships only the mechanism ([AI Artifacts](artifacts.md)) and its two product skills; which prompts, agents and other artifacts a machine gets is the fork's choice.

Both are **provider-agnostic**: the instructions are plain Markdown any assistant can read, and the artifacts are deployed into whichever apps `AiArtifacts.Deploy` names (Claude Code, Codex, Gemini CLI, Copilot, or an app of your own).

---

## Instructions Framework

Instructions auto-attach based on file patterns, eliminating the need to manually load context.

### How Instructions Work

1. **Pattern matching** - Each `.instructions.md` file declares an `applyTo` glob pattern
2. **Auto-load** - When you open a file matching that pattern, the instruction loads automatically
3. **Chaining** - Instructions reference deeper guidance files (e.g., PowerShell conventions)
4. **Scope** - Instructions only load for their matched file types

**Glob pattern examples:**

- `**/*.ps1` - All PowerShell scripts
- `**/*.psm1, **/*.psd1` - Module manifests and loaders
- `docs/**` - All documentation files
- `src/**/*.tsx` - TypeScript React files

### powershell.instructions.md

**File pattern:** `**/*.ps1`, `**/*.psm1`, `**/*.psd1`

**Purpose:** Applies PowerShell coding standards to all PowerShell files in the repository.

**Contains:**

- `applyTo` pattern declaration
- Links to `PowerShellConventions.md` for detailed rules
- Links to `OutputFormatting.md` for help block format
- Links to `ConfigurationPatterns.md` for safe config modifications
- **Critical safety section:** NEVER commit, push, or delete code without explicit user approval

**When triggered:** Opening any `.ps1`, `.psm1`, or `.psd1` file

**Example:** You're editing `Windows/PowerShell/Modules/Helper/Functions/MyFunction.ps1`. Immediately, Copilot loads this instruction and knows:

- Function naming must follow `Verb-Noun` pattern
- Help blocks must have `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`
- Tab indentation (not spaces)
- Cannot commit without approval

### documentation.instructions.md

**File pattern:** `docs/**`

**Purpose:** Applies documentation standards to all Docsify pages.

**Contains:**

- `applyTo` pattern declaration
- Links to `DocumentationStyle.md` for page structure
- Links to repository context files for background knowledge
- **Critical safety section:** Destructive documentation operations require approval

**When triggered:** Opening any `.md` file under `docs/`

**Example:** You're editing `docs/modules/helper.md`. The instruction loads and Copilot knows:

- Heading hierarchy for module pages
- Cross-reference link format (relative with `/` prefix)
- Callout syntax (`> [!NOTE]`, `> [!WARNING]`)
- Cannot delete files or commit changes without approval

---

## Creating New Instructions

To add a new instruction file (e.g., for a new language or framework):

1. **Create the file:** `.github/instructions/{name}.instructions.md`

2. **Define YAML frontmatter:**

    ```yaml
    ---
    applyTo: "path/to/files/**/*.ext"
    ---
    ```

3. **Write the instruction body:**

    ```markdown
    # Brief title describing what this instruction enforces

    Key rules and conventions for this file type...

    See [Detailed Conventions](../../AI/Instructions/detailed-file.md) for full guide.
    ```

4. **Test it:** Open a file matching your pattern - the instruction should load in Copilot Chat

**Best practices:**

- Keep instructions concise - use references for detailed content
- One instruction per file type (don't mix JavaScript + CSS + HTML)
- Include critical safety sections for destructive operations
- Use relative paths to reference detailed files (`../../AI/Instructions/...`)

---

## Skills, Prompts and Agents

WinuX ships no slash commands and no custom agents of its own. Since 1.6.0 they are artifact kinds, deployed by [Deploy-AiArtifacts](../modules/ai.md#deploy-aiartifacts) into each app's own folder:

| Kind | Where a fork keeps it | Where an app reads it (base catalogue) |
| ---- | --------------------- | -------------------------------------- |
| Skills | `AI/Skills/<source>/<skill>/SKILL.md` | `~/.claude/skills`, `~/.agents/skills` |
| Prompts | `AI/Prompts/<source>/<name>/` with `PROMPT.md` or a per-app variant (`claude.md`, `codex.md`, `gemini.toml`) | `~/.claude/commands`, `~/.codex/prompts`, `~/.gemini/commands` |
| Agents | `AI/Agents/<source>/<name>/` with `AGENT.md` or a per-app variant (`claude.md`, `codex.toml`, `gemini.md`, `copilot.agent.md`) | `~/.claude/agents`, `~/.codex/agents`, `~/.gemini/agents`, `~/.copilot/agents` |

Your own go under the `own` source, which no refresh touches and which wins a name clash; vendored ones come from an `AiArtifacts.Sources` entry. Several apps now treat skills as the portable form of a slash command (Claude Code merges custom commands into skills, Codex documents its custom prompts as deprecated), so a new workflow is usually best written as a skill.

### The product skills

WinuX ships two skills in `AI/Skills/winux/`, deployed whenever the AI artifacts are:

- **winux-configurator** - runs the [AI-assisted configuration session](../configuration/winux-configurator.md): it interviews you module by module and writes `Configuration.local.psd1`. It covers what the removed `/add-project`, `/add-workspace`, `/add-browser-group`, `/add-symlink` and `/add-window-layout` prompts did, through the Configuration module writers (`Add-Project`, `Add-Workspace`, `Add-BrowserGroup`, `Add-SymbolicLink`, `Add-WindowLayout`).
- **document** - turns a function's comment-based help into its man-style entry on `docs/modules/<module>.md` and its configuration guide, following `AI/Instructions/DocumentationStyle.md`, and keeps `FunctionsToExport` and the indexes in step.

Leave one out with `AiArtifacts.Exclude = @("skills/winux/document")`.

### Removed in 1.6.0

The base no longer carries `.github/prompts/` (`add-*`, `document`, `oneoff`, `research`), `.github/agents/researcher.agent.md`, `AI/Templates/`, `AI/Models/`, `AI/Providers/` or `AI/InitialConfiguration_2026_03_24.md`. A fork that used them copies them into its own tree before merging 1.6.0 - a conversation-note or research workflow becomes an `own` skill with its template inside the skill folder.

---

## Creating a Skill, Prompt or Agent

1. **Create the item folder** under `own`: `AI/Skills/own/<name>/SKILL.md`, `AI/Prompts/own/<name>/PROMPT.md` or `AI/Agents/own/<name>/AGENT.md`.
2. **Write the frontmatter** the app expects (`name` and `description` for a skill; the app's own format for a prompt or agent), then the workflow in Markdown. The `description` is what `List-AiArtifacts` shows.
3. **Add per-app variants** only where an app needs another format: a file named as the destination's `Files` list expects (`codex.toml`, `gemini.toml`, `copilot.agent.md`). An app none of the item's files suit simply does not get it.
4. **Deploy:** `Deploy-AiArtifacts -Kind Skills` (or `Prompts`, `Agents`), then start a new session of the app.
5. **Check:** `List-AiArtifacts -ListDiscrepancies` reports nothing.

**Examples of useful agents:**

- Debugger - Analyzes errors and suggests fixes
- Refactorer - Suggests code improvements with before/after
- Reviewer - Reviews code for bugs and patterns
- Trainer - Teaches concepts by example

---

## Architecture Principles

The agent system is built on these principles:

1. **Progressive disclosure** - Load only what's needed for the current context
2. **Auto-attachment** - Let file patterns trigger guidance, don't make users remember to load it
3. **Provider-agnostic** - Works with any AI integration, not just GitHub Copilot
4. **Mechanism, not content** - WinuX ships how artifacts are kept, vendored and deployed; what a machine gets is configured
5. **Self-documenting** - Each skill, prompt, agent and instruction explains its purpose and workflow
6. **Safe defaults** - Critical operations require explicit user approval (checked by instructions)

---

## Maintenance

### Updating Instructions

1. Edit `.github/instructions/{file}.instructions.md`
2. Changes apply next Copilot Chat session
3. No restart required

### Updating Artifacts

1. Edit the item under `AI/<Kind>/own/<name>/`
2. Deployed items are links into the repository, so the next session of the app reads the change; a `Copy` destination needs `Deploy-AiArtifacts` again
3. A vendored item is changed upstream and refreshed with `Update-AiArtifacts -Source <name>`

---

## For AI Models

This system gives AI models the tools to:

- **Self-guide:** Know exactly what conventions apply by reading loaded instructions
- **Ask clarifying questions:** Skills and prompts provide templates for interaction
- **Make changes safely:** Instructions enforce approval gates on destructive operations
- **Suggest improvements:** Recommend new skills, prompts or agents when patterns emerge
- **Link to context:** Reference exact files instead of repeating information
