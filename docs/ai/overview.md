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
| **Slash commands** (`.github/prompts/`)                  | When you type `/command`    | Guided workflows for common tasks                                 |
| **Custom agents** (`.github/agents/`)                    | When invoked via `@name`    | Specialized agents with restricted tools                          |

This layered approach means simple questions use minimal tokens, while complex tasks automatically pull in deeper context.

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
├── Models/
│   └── ModelSelectionGuide.md     # Decision matrix: which model for which task
├── Providers/
│   └── Copilot.md                 # GitHub Copilot modes, model table, best practices
└── Templates/
    ├── ConversationTemplate.md    # Structured format for saved conversations
    └── ResearchTemplate.md        # Comparison matrix for research topics

.github/
├── instructions/
│   ├── powershell.instructions.md  # Auto-attaches to *.ps1, *.psm1, *.psd1
│   └── documentation.instructions.md  # Auto-attaches to docs/**
├── prompts/                        # Slash commands (see below)
└── agents/
    └── researcher.agent.md         # @researcher agent for structured research
```

## Slash Commands

Type these in Copilot Chat to trigger guided workflows:

| Command              | Purpose                                                  |
| -------------------- | -------------------------------------------------------- |
| `/add-browser-group` | Add a new browser URL group to Configuration.psd1        |
| `/add-workspace`     | Add a new workspace with actions                         |
| `/add-project`       | Add a new project with all optional sections             |
| `/add-symlink`       | Add a symbolic link entry                                |
| `/add-window-layout` | Create a window layout template file                     |
| `/oneoff`            | Save a conversation for future reference                 |
| `/research`          | Structured research with comparison matrix and auto-save |
| `/document`          | Generate documentation from code comments                |

The `/add-*` commands use the [Configuration module](../modules/configuration.md) functions to make reliable modifications.

## Custom Agents

### @researcher

A research agent that auto-saves findings to `AI/Conversations/`. Invoke with:

```
@researcher best SSO solution for .NET
```

It follows a structured workflow: clarify → research → compare → recommend → save.

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

**When to use:** When writing documentation for functions or updating README entries.

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
- How to use `/oneoff` and `/research` commands for context persistence
- Batch operation patterns

**When to use:** When planning AI-assisted work sessions or dealing with large codebases.

---

## Model Selection (AI/Models/)

### ModelSelectionGuide.md

**Purpose:** Decision matrix for selecting which AI model to use for different tasks.

**Contains:**

- Model comparison table (Claude Haiku, Claude 3.5 Sonnet, o1, etc.)
- Task categories (coding, research, documentation, debugging)
- Recommendations by task type
- Token budget considerations
- Trade-offs: speed vs accuracy vs token cost

**When to use:** When deciding which model or provider to use for a task.

---

## Providers (AI/Providers/)

### Copilot.md

**Purpose:** GitHub Copilot-specific configuration and best practices.

**Documents:**

- Chat modes: Ask, Edit, Agent, Research
- When to use each mode
- Model availability and limitations
- Copilot-specific syntax and features
- Troubleshooting common issues
- Performance optimization for Copilot

**When to use:** When using Copilot Chat or debugging Copilot-specific behavior.

---

## Templates (AI/Templates/)

### ConversationTemplate.md

**Purpose:** Standardized format for saved conversations (persistence via `/oneoff`).

**Documents:**

- YAML frontmatter: topic, date, context, outcome
- Conversation sections: objective, key decisions, resolution
- How to structure saved conversations for future reference
- Naming conventions for saved conversation files

**When to use:** When using `/oneoff` to save a conversation for later reference.

**Output location:** `AI/Conversations/{topic}/{subtopic}.md`

### ResearchTemplate.md

**Purpose:** Structured research format with comparison matrix (used by `/research`).

**Documents:**

- Research structure: question → candidates → evaluation criteria → comparison
- Comparison matrix format
- How `/research` auto-saves findings
- Recommendation format

**When to use:** When using `/research` to conduct structured technical research.

**Output location:** `AI/Conversations/Research/{topic}.md`

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

## Configuration Helpers (​.github/prompts/add-\*.prompt.md)

Slash commands that automate common Configuration.psd1 modifications.

### /add-project

**Purpose:** Adds a new project to the configuration.

**Prompts for:**

- Project name
- Root directory path
- VS Code project (optional)
- Visual Studio solution (optional)
- Run command mapping (optional)
- Project terminals (optional)

**Modifies:** `BasePaths.Projects`, `Projects` list, `ProjectActions`, `VisualStudioSolutions`, `VSCodeProjects`, `RunnableProjectMappings`

### /add-workspace

**Purpose:** Adds a new workspace with configurable actions.

**Prompts for:**

- Workspace name
- Actions (Open-Terminal, Open-VSCode, Open-Browser, etc.)
- Action parameters

**Modifies:** `Workspaces` list, `WorkspaceActions`

### /add-browser-group

**Purpose:** Adds a new browser URL group.

**Prompts for:**

- Group name
- Nesting pattern (simple, named, nested, mixed)
- URLs and names

**Modifies:** `BrowserGroups`

**Supported patterns:** All four nesting formats documented in [Configuration Reference](../configuration/configuration-reference.md#browser-groups)

### /add-symlink

**Purpose:** Adds a symbolic link entry.

**Prompts for:**

- Symlink name
- Path (where symlink is created)
- Target (what it points to)
- Type (Windows or WSL - inferred from path slashes)

**Modifies:** `PathTemplates.SymbolicLinks`

### /add-window-layout

**Purpose:** Creates a window layout template file.

**Generates:**

- File: `Layouts/{MachineType}/{LayoutName}_{MachineType}.psd1`
- Template: Monitors section + Layout array structure

**Modifies:** Creates new file (no config changes)

---

## Workflow Commands (​.github/prompts/)

### /document

**Purpose:** Generates Docsify documentation from function comment-based help.

**Input:** Function name or module path

**Output:** Formatted docs section ready to paste into module docs page

**Uses:** PowerShell comment-based help to extract `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE` and formats as Docsify markdown

### /oneoff

**Purpose:** Persist the current conversation for future continuation.

**Creates:** Directory `AI/Conversations/{topic}/` with structured markdown

**Saves:** Conversation overview, key decisions, resolution

**Future use:** Reference with "I want to continue work on {topic} from my /oneoff note"

### /research

**Purpose:** Structured research with automatic comparison and save.

**Workflow:** Clarify question → research candidates → build comparison matrix → recommend → save

**Output:** `AI/Conversations/Research/{topic}.md` with full comparison table and recommendation

---

## Custom Agents (.github/agents/)

### researcher

**Purpose:** Specialized agent for structured technical research.

**Tools available:** Web search, codebase search, file reading, comparison matrix building

**Workflow:**

1. Clarify research question
2. Identify candidate solutions
3. Research each candidate (features, pros/cons, adoption)
4. Build comparison matrix
5. Recommend based on criteria
6. Auto-save to `AI/Conversations/Research/`

**Invocation:** `@researcher <your research question>`

**Output:** Structured research document with comparison matrix and recommendation

---

## How the System Integrates

**Scenario: Working on PowerShell functions**

1. Open `Windows/PowerShell/Modules/Helper/Functions/MyFunction.ps1`
2. `powershell.instructions.md` auto-attaches via `applyTo` pattern
3. It points to `PowerShellConventions.md` (loaded automatically)
4. When asking about Output format, `OutputFormatting.md` becomes relevant
5. When modifying Configuration, `ConfigurationPatterns.md` is referenced
6. When stuck, use `/add-project` or `/oneoff` to stay on track

**Scenario: Writing documentation**

1. Open `docs/modules/helper.md`
2. `documentation.instructions.md` auto-attaches via `applyTo` pattern
3. `DocumentationStyle.md` and `REPOSITORY_CONTEXT.md` become available
4. Use `/document` command to generate formatted sections
5. Use `/oneoff` to save progress

**Scenario: Researching a technical decision**

1. Start with `/research Comparing SSO solutions for .NET`
2. `@researcher` agent conducts structured research
3. Results auto-save to `AI/Conversations/Research/`
4. Future reference: "I want to continue from my research on SSO"

---

## For Maintainers

### To update an instruction file

1. Edit the file in `AI/Instructions/`
2. If it's referenced by a `.github/instructions/*.md` file, that file will auto-load it
3. No restart required - next Copilot Chat session picks up changes

### To create a new command

1. Create `{command-name}.prompt.md` in `.github/prompts/`
2. Add YAML frontmatter: `description`, optional `mode`
3. Write the prompt body (markdown + embedded instructions)
4. It becomes available as `/{command-name}` immediately

### To create a new custom agent

1. Create `{agent-name}.agent.md` in `.github/agents/`
2. Define frontmatter: `description`, `tools`, `invocation`
3. Write the agent workflow in markdown
4. It becomes available as `@{agent-name}` immediately
