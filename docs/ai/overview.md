# AI Integration

WinuX includes a **layered AI context system** that makes AI assistants (GitHub Copilot, etc.) understand the repository automatically - no need to re-explain the architecture, conventions, or configuration patterns each session.

## How It Works

The system uses progressive disclosure - only load what's needed for the current task:

| Layer                                                    | When Loaded                 | Purpose                                                           |
| -------------------------------------------------------- | --------------------------- | ----------------------------------------------------------------- |
| **Workspace instructions** (`AGENTS.md`)                 | Every conversation          | Top-level architecture, module list, conventions                  |
| **Auto-attached instructions** (`.github/instructions/`) | When editing matching files | Thin pointers that trigger based on file type                     |
| **On-demand context** (`AI/Context/`)                    | When AI detects relevance   | Full architecture map, complete function reference                |
| **Deep instructions** (`AI/Instructions/`)               | When referenced             | PowerShell conventions, output formatting, configuration patterns |
| **AI artifacts** (`AI/<Kind>/<source>/<item>`)           | In every project, once deployed | Skills, prompts and agents (plus mods and rules) linked into each AI app by `Deploy-AiArtifacts` |

This layered approach means simple questions use minimal tokens, while complex tasks automatically pull in deeper context.

## AI Artifacts (machine-global)

Separate from the per-repository context system above, the [AI artifacts](artifacts.md) are deployed machine-globally, so every AI app on the machine loads them in every project: skills, Claude Code mods, rules, prompts and agents, kept under `AI/<Kind>/<source>/<item>` and linked by `Deploy-AiArtifacts` into the apps `AiArtifacts.Deploy` names (Claude Code, Codex, Gemini CLI, Copilot, or an app of your own), on Windows and in WSL. `Update-AiArtifacts` vendors upstream repositories at a pinned commit. WinuX ships the mechanism, the inactive harness catalogue, an example rules skeleton and two product skills; the rest is the fork's. Deployment is opt-in via `BootstrapConfig.Steps.AiArtifacts`. The kind specifics are on [CoreAiRules](coreairules.md) (always-on rules and Claude Code's managed settings), [AI Skills](skills.md) and [AI Mods](mods.md).

MCP servers are deployed machine-globally as well, but they are not artifacts: each app keeps them in its own configuration file. [AI MCP Servers](mcp-servers.md) covers `Deploy-AiMcpServers`, which adds the servers under `AiMcpServers` to Claude Code (through its CLI) and Codex (its `config.toml`), opt-in via `BootstrapConfig.Steps.AiMcpServers`.

## Directory Structure

```
AI/
├── Context/
│   ├── REPOSITORY_CONTEXT.md      # Architecture map for AI consumption
│   └── WINDOWS_CONTEXT.md         # Full function reference
├── Instructions/
│   ├── PowerShellConventions.md   # Module structure, naming, parameter patterns
│   ├── OutputFormatting.md        # Function signatures, console output, config format
│   ├── ConfigurationPatterns.md   # How to modify Configuration.psd1
│   ├── DocumentationStyle.md      # Docsify conventions and page structure
│   └── ContextBudgeting.md        # Token optimization strategies
├── Mods/
│   └── README.md                  # Claude Code mods: <source>/<mod>/.claude-plugin/plugin.json (fork adds sources)
├── Rules/
│   └── example/
│       └── CoreAiRules/
│           └── RULES.md           # Example rules skeleton; a fork writes Rules/own/<Name>/
└── Skills/
    ├── README.md                  # Agent Skills: <source>/<skill>/SKILL.md
    ├── own/                       # Your own skills (ships empty)
    └── winux/
        ├── winux-configurator/    # SKILL.md + agents/openai.yaml - the WinuXConfigurator entry point
        └── document/              # SKILL.md + agents/openai.yaml - docs from comment-based help

.github/
└── instructions/
    ├── powershell.instructions.md  # Auto-attaches to *.ps1, *.psm1, *.psd1
    └── documentation.instructions.md  # Auto-attaches to docs/**
```

A fork adds `AI/Prompts/<source>/<name>/` and `AI/Agents/<source>/<name>/` the same way; see [Agent System](agent-system.md).

## Product Skills

| Skill | What it does |
| ----- | ------------ |
| `winux-configurator` | Runs the [AI-assisted configuration session](../configuration/winux-configurator.md) and writes `Configuration.local.psd1`; covers browser groups, projects, symbolic links, window layouts and workspaces through the Configuration module writers |
| `document` | Generates or updates a function's module page entry and configuration guide from its comment-based help |

## Context Files (AI/Context/)

These files provide comprehensive background for AI models. They are large (~10-50KB each) and loaded on-demand when tackling complex tasks.

### REPOSITORY_CONTEXT.md

**Purpose:** High-level architecture overview for AI consumption.

**Contains:**

- Repository structure and directory layout
- Module descriptions and interdependencies
- Placeholder system explanation
- Configuration flow (how settings are loaded and applied)
- Key design patterns and conventions
- Links to detailed instructions

**When to use:** Start here when asking about overall architecture or how different components relate.

**Size:** ~40KB | **Audience:** All AI models

### WINDOWS_CONTEXT.md

**Purpose:** Complete function reference for all PowerShell modules.

**Contains:**

- Full list of all exported functions grouped by module
- One-line description of each function
- Parameter names for major functions
- Consumer relationships (which functions call which)
- Alias mappings

**When to use:** When writing functions or understanding dependencies between modules.

**Size:** ~50KB | **Audience:** AI models working on PowerShell code

---

## Instruction Files (AI/Instructions/)

These files define specific conventions and patterns for the repository. They are progressively loaded based on context.

### PowerShellConventions.md

**Purpose:** Defines PowerShell coding standards for this repository.

**Documents:**

- Module structure: `.psd1` manifest → `.psm1` loader → `Functions/` directory
- Function naming: `Verb-Noun` pattern with specific verb choices
- Comment-based help blocks: `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE` format
- Parameter conventions: parameter validation, splatting patterns
- Error handling: `Write-Error` vs exceptions
- Logging and output: color conventions, transcript patterns
- Alias definitions and when to use them

**Applied to:** Files matching `**/*.ps1`, `**/*.psm1`, `**/*.psd1`

**Critical safety section:** "NEVER commit, push, or delete code/files without explicit user approval first. See AGENTS.md for full critical operations policy."

**When to use:** When implementing or modifying any PowerShell function or module.

### OutputFormatting.md

**Purpose:** Standardizes how functions display information to users.

**Documents:**

- Function signature format (parameter tables with Type, Required, Description columns)
- Configuration entry examples (how to show config section examples)
- Help block examples with proper indentation
- Console output color conventions:
    - Green `=>` for success
    - Red `=>` for errors
    - Yellow for warnings
    - Cyan `[FunctionName]` for debug output
- Alias documentation format
- Comment style and indentation (tabs per codebase)

**When to use:** When writing documentation for functions or updating their entries in the module reference pages.

### ConfigurationPatterns.md

**Purpose:** Explains how to safely and correctly modify Configuration.psd1.

**Documents:**

- How to add configuration sections without breaking dependent functions
- Placeholder expansion mechanics
- Path template conventions
- Machine-specific overrides pattern
- Testing configuration changes
- Safe refactoring strategies

**When to use:** When adding new settings or restructuring config sections.

### DocumentationStyle.md

**Purpose:** Defines standards for the Docsify documentation site.

**Documents:**

- Page structure and heading hierarchy
- Cross-reference link format (relative paths with `/` prefix)
- Callout syntax: `> [!NOTE]`, `> [!TIP]`, `> [!WARNING]`
- Code block formatting
- Table conventions
- Navigation sidebar structure

**When to use:** When writing or updating any Docsify documentation pages.

**Critical safety section:** "Before deleting .md files or committing changes, describe changes and request approval."

### ContextBudgeting.md

**Purpose:** Token optimization strategies for AI-assisted work.

**Documents:**

- 7 strategies for maximizing token efficiency
- When to use references vs inline content
- Mode selection (Ask, Edit, Agent, Research)
- How to keep context across sessions with saved notes
- Batch operation patterns

**When to use:** When planning AI-assisted work sessions or dealing with large codebases.

---

## Instructions Framework (.github/instructions/)

File-type-scoped instructions that auto-attach based on `applyTo` patterns.

### powershell.instructions.md

**Applied to:** `**/*.ps1`, `**/*.psm1`, `**/*.psd1`

**Contains:**

- Pointer to `PowerShellConventions.md` for detailed rules
- Pointer to `OutputFormatting.md` for signature format
- Pointer to `ConfigurationPatterns.md` for config modifications
- Critical safety guardrails: no commits/pushes/deletes without approval

**Behavior:** When you open any `.ps1`, `.psm1`, or `.psd1` file, Copilot automatically loads this instruction.

### documentation.instructions.md

**Applied to:** `docs/**`

**Contains:**

- Pointer to `DocumentationStyle.md` for page structure
- Pointer to `REPOSITORY_CONTEXT.md` and `WINDOWS_CONTEXT.md` for background
- Critical safety section for destructive documentation operations
- Cross-reference conventions

**Behavior:** When you open any file in `docs/`, Copilot automatically loads this instruction.

---

## How the System Integrates

**Scenario: Working on PowerShell functions**

1. Open `Windows/PowerShell/Modules/Helper/Functions/MyFunction.ps1`
2. `powershell.instructions.md` auto-attaches via `applyTo` pattern
3. It points to `PowerShellConventions.md` (loaded automatically)
4. When asking about Output format, `OutputFormatting.md` becomes relevant
5. When modifying Configuration, `ConfigurationPatterns.md` is referenced
6. To add a project, workspace or browser group, ask the `winux-configurator` skill

**Scenario: Writing documentation**

1. Open `docs/modules/helper.md`
2. `documentation.instructions.md` auto-attaches via `applyTo` pattern
3. `DocumentationStyle.md` and `REPOSITORY_CONTEXT.md` become available
4. Use the `document` skill to generate the entry and guide from the function's help

---

## For Maintainers

### To update an instruction file

1. Edit the file in `AI/Instructions/`
2. If it's referenced by a `.github/instructions/*.md` file, that file will auto-load it
3. No restart required - next Copilot Chat session picks up changes

### To add a skill, prompt or agent

1. Create the item folder under `AI/Skills/own/`, `AI/Prompts/own/` or `AI/Agents/own/` with its `SKILL.md`, `PROMPT.md` or `AGENT.md` (and per-app variants where an app needs another format)
2. Run `Deploy-AiArtifacts` to link it into every app `AiArtifacts.Deploy` names
3. Check with `List-AiArtifacts -ListDiscrepancies`

See [AI Artifacts](artifacts.md) and [Agent System](agent-system.md).
