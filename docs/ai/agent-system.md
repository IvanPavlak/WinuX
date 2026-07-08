# VS Code Agent System

The `.github/` directory configures the VS Code Copilot agent system. This framework defines:

- **Instructions** - File-type-scoped guidance auto-loaded based on `applyTo` patterns
- **Custom Agents** - Specialized AI personas for specific workflows
- **Slash Commands** - Guided workflows for common tasks (`/add-project`, `/research`, etc.)
- **Prompts** - Reusable templates for consistent interaction

All of these are **provider-agnostic** and will work with any AI integration (not just Copilot).

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

## Slash Commands (Prompts)

Slash commands trigger pre-written workflows. Each is a separate file with specific instructions.

### Configuration Helpers

#### /add-project

**File:** `.github/prompts/add-project.prompt.md`

**Purpose:** Interactively add a new project to Configuration.psd1.

**Workflow:**

1. Prompt for project name
2. Prompt for root directory (with placeholder expansion suggestions)
3. Prompt for VS Code project settings (optional)
4. Prompt for Visual Studio solution path (optional)
5. Prompt for run command mapping
6. Prompt for terminal configurations (optional)
7. Call `Add-Project` function to modify configuration

**Modifies:** Multiple config sections:

- `BasePaths.Projects.{ProjectName}.Root`
- `Projects` array (adds project name)
- `ProjectActions.{ProjectName}` (with default actions)
- `VisualStudioSolutions` (if provided)
- `VSCodeProjects` (if provided)
- `RunnableProjectMappings` (if provided)

**Example usage:**

```
/add-project
→ Project name? OtherProject
→ Root directory? {Dev}\OtherProject
→ Setup VS Code? Yes
→ Solution file? Yes
→ Run command? dnbr
→ Create terminals? Yes
```

#### /add-workspace

**File:** `.github/prompts/add-workspace.prompt.md`

**Purpose:** Interactively add a new workspace with actions.

**Workflow:**

1. Prompt for workspace name
2. Prompt for actions (multi-select menu):
    - Open Terminal
    - Open VS Code
    - Open Visual Studio
    - Open Browser
    - Open Applications (Discord, Obsidian, etc.)
    - Custom function calls
3. For each action, prompt for parameters
4. Create layout template file for window management (optional)
5. Call `Add-Workspace` function

**Modifies:**

- `Workspaces` array
- `WorkspaceActions.{WorkspaceName}`
- Creates `Layouts/{MachineType}/{WorkspaceName}_{MachineType}.psd1` (optional)

#### /add-browser-group

**File:** `.github/prompts/add-browser-group.prompt.md`

**Purpose:** Add a new browser URL group.

**Workflow:**

1. Prompt for group name
2. Prompt for nesting pattern:
    - Simple (array of URLs)
    - Named (array of named URLs)
    - Nested (hashtable of subgroups)
    - Mixed (combination)
3. Prompt for URLs or structure based on pattern
4. Validate name uniqueness (all names used for idempotency checking)
5. Call `Add-BrowserGroup` function

**Modifies:** `BrowserGroups`

**Supported patterns:**

- **Simple:** `@("https://github.com", "https://google.com")`
- **Named:** `@(@{Name="GitHub"; Url="https://github.com"})`
- **Nested:** `@{Backend=@(...); Frontend=@(...)}`
- **Mixed:** `@("https://url", @{Name="..."; Url="..."}, @{Sub=@(...)})`

#### /add-symlink

**File:** `.github/prompts/add-symlink.prompt.md`

**Purpose:** Add a symbolic link entry.

**Workflow:**

1. Prompt for symlink name
2. Prompt for target path (source in WinuX)
3. Prompt for destination path (where symlink is created)
4. Detect type: forward slashes `/` → WSL, backslashes `\` → Windows
5. Call `Add-SymbolicLink` function

**Modifies:** `PathTemplates.SymbolicLinks`

#### /add-window-layout

**File:** `.github/prompts/add-window-layout.prompt.md`

**Purpose:** Create a window layout template file for a workspace.

**Workflow:**

1. Prompt for layout name (usually `{WorkspaceName}_{MachineType}`)
2. Prompt for machine type
3. Prompt for monitors (number and arrangement)
4. Prompt for window placement rules:
    - Process name (e.g., "Code", "firefox")
    - Window title pattern
    - Desktop number
    - Zone name
    - Monitor assignment
5. Generate `.psd1` file in `Layouts/{MachineType}/`

**Creates:** `Layouts/{MachineType}/{LayoutName}.psd1`

---

### Workflow Commands

#### /document

**File:** `.github/prompts/document.prompt.md`

**Purpose:** Generate Docsify documentation from PowerShell comment-based help.

**Workflow:**

1. Prompt for function name or module path
2. Extract comment-based help:
    - `.SYNOPSIS`
    - `.DESCRIPTION`
    - `.PARAMETER` entries (with types and descriptions)
    - `.EXAMPLE` entries (with descriptions)
3. Format as Docsify-compliant markdown:
    - Heading with function name
    - Syntax block
    - Parameter table (Name | Type | Required | Description)
    - Examples with code blocks
4. Output formatted markdown (copy to docs page)

**Input:** Any PowerShell function

**Output:** Formatted markdown section ready to paste into module documentation

**Example:**

````
Input: Get-ProjectPath
Output:
### Get-ProjectPath

Resolves project name to full path from configuration.

**Syntax:**
```powershell
Get-ProjectPath -ProjectName <string> [-PathKey <string>]
````

**Parameters:**

| Parameter   | Type   | Required | Description                          |
| ----------- | ------ | -------- | ------------------------------------ |
| ProjectName | String | Yes      | Name of project to resolve           |
| PathKey     | String | No       | Config key to return (default: Root) |

**Examples:**

```powershell
Get-ProjectPath -ProjectName "MyProject"
Get-ProjectPath -ProjectName "MyProject" -PathKey "Solution"
```

````

#### /oneoff

**File:** `.github/prompts/oneoff.prompt.md`

**Purpose:** Save the current conversation for future continuation.

**Workflow:**
1. Prompt for topic name
2. Prompt for optional subtopic
3. Auto-extract conversation summary:
   - Objective
   - Key decisions made
   - Current state
   - Remaining work
4. Create directory: `AI/Conversations/{Topic}/`
5. Save as `{Subtopic}.md` with frontmatter and content

**Output location:** `AI/Conversations/{Topic}/{Subtopic}.md`

**Output format:**

```markdown
---
Topic: {Topic}
Subtopic: {Subtopic}
Date: {Date}
Objective: {Extracted objective}
Status: In Progress
---

## Objective
{User's stated goal}

## Context
{Conversation summary}

## Key Decisions
- Decision 1
- Decision 2

## Current State
{What has been completed}

## Remaining Work
{What still needs to be done}

## Notes
{Any important context for future sessions}
````

**Future usage:** Start a new conversation with:

```
I want to continue work on {Topic} from my /oneoff note
```

#### /research

**File:** `.github/prompts/research.prompt.md`

**Purpose:** Conduct structured research with automatic comparison and save.

**Workflow:**

1. Clarify research question
2. Identify candidate solutions (3-5 options)
3. Research each candidate:
    - Core features
    - Pros and cons
    - Adoption/community
    - Cost/licensing
    - Integration effort
4. Build comparison matrix
5. Recommend best option with reasoning
6. Auto-save to `AI/Conversations/Research/{Topic}.md`

**Output location:** `AI/Conversations/Research/{Topic}.md`

**Output format:**

```markdown
---
Topic: { Research Topic }
Date: { Date }
Question: { Original question }
Recommendation: { Best candidate }
---

## Research Question

{Full question}

## Candidates Evaluated

1. {Option A}
2. {Option B}
3. {Option C}
   ...

## Evaluation Criteria

- Feature set
- Community/Support
- Integration effort
- Cost
- Performance
- Maintenance burden

## Comparison Matrix

| Aspect       | Option A | Option B | Option C |
| ------------ | -------- | -------- | -------- |
| {Criteria 1} | ...      | ...      | ...      |
| {Criteria 2} | ...      | ...      | ...      |

...

## Analysis

### {Option A}

**Pros:**

- Pro 1
- Pro 2

**Cons:**

- Con 1
- Con 2

### {Option B}

...

## Recommendation

**Best choice: {Option}**

**Reasoning:**

- Reason 1
- Reason 2
- Reason 3

**Integration notes:**

- How to implement
- Gotchas to watch for
- Next steps
```

---

## Custom Agents

Agents are specialized AI personas with restricted tools for specific workflows.

### researcher

**File:** `.github/agents/researcher.agent.md`

**Purpose:** Structured research agent for technical decisions.

**Tools available:**

- Web search
- GitHub code search
- File reading
- Semantic codebase search
- Comparison matrix building

**Specialization:**

- Deep research into multiple options
- Structured comparison methodology
- Auto-saves findings to `AI/Conversations/Research/`

**Workflow:**

1. **Clarify** - Ask follow-up questions to understand decision criteria
2. **Research** - Search and document each candidate
3. **Compare** - Build side-by-side comparison table
4. **Recommend** - Evaluate against criteria and make recommendation
5. **Save** - Auto-save research document

**Invocation:** `@researcher <research question>`

**Example:**

```
@researcher What's the best way to implement OAuth2 in .NET?
```

Agent will:

1. Ask about: existing auth system, compliance needs, user count, integration scope
2. Research: Identity Server, Azure AD B2C, Auth0, Keycloak
3. Compare: Setup complexity, cost, features, community support
4. Recommend: Based on your specific requirements
5. Save: Research document to `AI/Conversations/Research/OAuth2-DotNet.md`

---

## Creating New Agents

To add a custom agent:

1. **Create file:** `.github/agents/{name}.agent.md`

2. **Define YAML frontmatter:**

    ```yaml
    ---
    description: "One-line description of what this agent does"
    tools: ["tool1", "tool2", ...]
    invocation: "@{name} <parameter>"
    ---
    ```

3. **Write the workflow in markdown:**

    ```markdown
    # {Agent Name}

    ## Purpose

    Clear explanation of what this agent handles

    ## Workflow

    1. Step 1
    2. Step 2
    3. Step 3

    ## Example Invocation
    ```

    @{name} example query

    ```

    ## Output Format
    Description of what the agent returns
    ```

4. **Test:** Invoke with `@{name}` in Copilot Chat

**Examples of useful agents:**

- Debugger - Analyzes errors and suggests fixes
- Refactorer - Suggests code improvements with before/after
- Reviewer - Reviews code for bugs and patterns
- Trainer - Teaches concepts by example

---

## Creating New Prompts

To add a new slash command:

1. **Create file:** `.github/prompts/{command-name}.prompt.md`

2. **Define YAML frontmatter:**

    ```yaml
    ---
    description: "Brief description of what /command-name does"
    mode: "ask" # or "edit", "agent", optional
    ---
    ```

3. **Write the prompt workflow:**

    ```markdown
    # {Command Name}

    ## Purpose

    What problem does this solve?

    ## Workflow

    1. Clarify...
    2. Analyze...
    3. Generate...
    4. Output...

    ## Example Usage
    ```

    /{command-name} <example>

    ```

    ## Output Format
    What will the user receive?
    ```

4. **Test:** Type `/{command-name}` in Copilot Chat

**Naming conventions:**

- `/add-*` for adding configuration entries
- `/generate-*` for creating files or code
- `/fix-*` for debugging or correction
- `/analyze-*` for investigation or review

---

## Integration Example: Adding a New Configuration Type

If you wanted to support a new type of configuration (e.g., "Environments"), here's how the system works together:

1. **Add instruction:** `.github/instructions/environments.instructions.md` (if needed)

2. **Create slash command:** `.github/prompts/add-environment.prompt.md`
    - Prompts for environment name, settings, etc.
    - Calls function to modify Configuration.psd1

3. **Update PowerShell instruction:** Add reference to new prompt in `powershell.instructions.md`

4. **Update documentation:**
    - Add section to `docs/configuration/configuration-reference.md`
    - Reference in `WINDOWS_CONTEXT.md`

5. **Test workflow:**
    - Open a `.ps1` file → PowerShell instruction loads → Shows `/add-environment` is available
    - Use `/add-environment` → Interactively configure
    - Configuration updated automatically
    - Ready to use in code

---

## Architecture Principles

The agent system is built on these principles:

1. **Progressive disclosure** - Load only what's needed for the current context
2. **Auto-attachment** - Let file patterns trigger guidance, don't make users remember to load it
3. **Provider-agnostic** - Works with any AI integration, not just GitHub Copilot
4. **Self-documenting** - Each agent/prompt/instruction explains its purpose and workflow
5. **Composable** - Agents and prompts can chain together (e.g., /research output fed to @researcher)
6. **Safe defaults** - Critical operations require explicit user approval (checked by instructions)
7. **Persistent learning** - /oneoff and /research save insights for future reference

---

## Maintenance

### Updating Instructions

1. Edit `.github/instructions/{file}.instructions.md`
2. Changes apply next Copilot Chat session
3. No restart required

### Updating Agents

1. Edit `.github/agents/{name}.agent.md`
2. Next invocation of `@{name}` uses updated version
3. No restart required

### Monitoring Usage

Check `AI/Conversations/` to see which prompts and agents are being used. This helps identify:

- Frequently used workflows (keep them simple)
- Unused features (remove if not needed)
- Requests for new workflows (create new prompts)

---

## For AI Models

This system gives AI models the tools to:

- **Self-guide:** Know exactly what conventions apply by reading loaded instructions
- **Ask clarifying questions:** Prompts provide templates for interaction
- **Make changes safely:** Instructions enforce approval gates on destructive operations
- **Suggest improvements:** Recommend new prompts/agents when patterns emerge
- **Link to context:** Reference exact files instead of repeating information
