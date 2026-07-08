# Copilot Provider Guide

> **Purpose**: Optimization guide for GitHub Copilot usage - model selection, modes, token efficiency.
> **Primary usage**: VS Code CLI/editor (Agent mode, Ask mode)

## Available Models

| Model               | Strengths                                               | Best For                                                                | Token Cost |
| ------------------- | ------------------------------------------------------- | ----------------------------------------------------------------------- | ---------- |
| **Claude Opus 4.6** | Deep reasoning, complex multi-step, large context       | Architecture, refactoring, multi-file changes, debugging complex issues | High       |
| **GPT 5.4**         | Fast, strong general coding, good instruction following | General coding, quick edits, feature implementation                     | High       |
| Sonnet 4.5          | Good balance of quality and speed                       | Mid-complexity tasks when daily limits are tight                        | Medium     |
| Raptor Mini         | Fast, lightweight                                       | Simple edits, boilerplate, quick questions                              | Low        |
| GPT 5.4 Mini        | Fast, lightweight                                       | Simple edits, quick lookups, straightforward changes                    | Low        |

## Model Selection Strategy

### Use Opus 4.6 when:

- Multi-file changes across modules
- Complex debugging with subtle issues
- Architecture decisions or large refactors
- Configuration.psd1 modifications (complex nested structure)
- Writing new modules or functions with dependencies
- Planning and design work

### Use GPT 5.4 when:

- Single-file feature implementation
- Writing functions with clear requirements
- Documentation generation
- Code review and suggestions
- Standard patterns (add a project, browser group, symlink)

### Use Mini models (Raptor Mini / GPT 5.4 Mini) when:

- Simple syntax questions
- Small edits (rename, fix typo, adjust parameter)
- Quick lookups ("what does this function do?")
- Running low on daily usage limits
- Boilerplate generation from clear templates

### Use Sonnet 4.5 when:

- Mid-complexity tasks but usage limits are tight on primary models
- Good fallback when Opus/GPT 5.4 limits are reached

## Copilot Modes

| Mode      | Use Case                                                  | Token Impact         |
| --------- | --------------------------------------------------------- | -------------------- |
| **Agent** | Multi-step tasks, file creation/editing, running commands | Highest - uses tools |
| **Ask**   | Questions, explanations, code review                      | Medium - read-only   |
| **Edit**  | Targeted edits to selected code                           | Low - focused scope  |

**Default to Edit mode** for small changes. Use Agent mode for multi-file work.

## Token Optimization Strategies

### 1. Leverage the instruction system

The `.github/instructions/` files auto-attach conventions when you edit matching files. This means you don't need to re-explain formatting, naming, or patterns - the AI already knows them.

### 2. Use context references, not inline content

Instead of pasting Configuration.psd1 content into the prompt, say:

> "Read Configuration.psd1 and add a new BrowserGroup following ConfigurationPatterns.md"

The AI will read both files itself - more accurate and cheaper than you pasting content.

### 3. Use slash commands

- `/oneoff` - saves conversation context once, instead of re-explaining in future sessions
- `/research` - structured research with saved results, prevents re-researching
- `/document` - generates docs from code, avoids manual documentation work

### 4. Be specific in prompts

Bad (expensive): "Help me set up a new project"
Good (cheap): "Add project 'NewApp' to Configuration.psd1 with Open-VSCode and terminal tabs at {Dev}/GitHub/NewApp"

### 5. Use Explore subagent for research

For "find where X is used" or "how does Y work" questions, the Explore subagent is more efficient than manual searching - it runs in parallel and returns a focused summary.

### 6. Progressive disclosure

Start with Ask mode to understand the scope, then switch to Agent mode for implementation. Don't use Agent mode just to read code.

### 7. Small model for small tasks

Switch to Raptor Mini or GPT 5.4 Mini for quick questions and small edits. Save Opus 4.6 for tasks that actually need deep reasoning.

## File-Specific Instructions

The workspace has two `.instructions.md` files that auto-attach:

| File                            | Triggers On                    | What It Does                                                                         |
| ------------------------------- | ------------------------------ | ------------------------------------------------------------------------------------ |
| `powershell.instructions.md`    | `**/*.ps1,**/*.psm1,**/*.psd1` | Points AI to PowerShellConventions.md, OutputFormatting.md, ConfigurationPatterns.md |
| `documentation.instructions.md` | `docs/**`                      | Points AI to DocumentationStyle.md and context files                                 |

These are intentionally terse (just pointers) - the AI reads the full instruction files only when needed, saving tokens on conversations that don't touch those file types.

## Prompt Files

| Command     | Purpose                                    | When to Use                                     |
| ----------- | ------------------------------------------ | ----------------------------------------------- |
| `/oneoff`   | Save conversation for later continuation   | Important decisions, complex debugging sessions |
| `/research` | Structured research with comparison matrix | Evaluating tools, libraries, approaches         |
| `/document` | Generate docs from code comments           | After writing new functions or modules          |

## Best Practices

1. **Start a new chat** for each distinct task - avoids context pollution from previous conversation
2. **Reference existing files** instead of describing what you want - "follow the pattern in Open-Browser.ps1" is better than describing the pattern
3. **Use the todo list** for multi-step tasks - the AI tracks progress across tool calls
4. **Save important conversations** with `/oneoff` before the session ends
5. **Check usage limits** - if running low, switch to mini models for remaining simple tasks
