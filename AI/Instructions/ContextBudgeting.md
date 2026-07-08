# Context Budgeting

> **Purpose**: Token optimization strategies for maximum reliability per token spent.

## Core Principle

**Reliability first, then optimize.** Never sacrifice correctness to save tokens. Instead, structure information so that the AI gets maximum context with minimum tokens.

## Strategy 1: Layered Context (Progressive Disclosure)

Instead of loading all context upfront, load only what's needed:

| Layer             | When                        | What                                     |
| ----------------- | --------------------------- | ---------------------------------------- |
| **Always loaded** | Every conversation          | AGENTS.md (workspace instructions)       |
| **Auto-attached** | When editing matching files | `.instructions.md` files (via `applyTo`) |
| **On-demand**     | When AI detects relevance   | Instruction files (via `description`)    |
| **Explicit**      | When you reference them     | Context documents, configuration files   |

The `.github/instructions/` files are intentionally terse (just pointers). The full content lives in `AI/Instructions/` and is read only when actually needed.

## Strategy 2: Reference, Don't Repeat

Bad (expensive):

> "Here's my Configuration.psd1 format: BrowserGroups use @{ GroupName = @( ... ) } with Named URLs..."

Good (cheap):

> "Add a browser group following the pattern in ConfigurationPatterns.md"

The AI reads the file itself - more accurate and uses file-reading tokens (not prompt tokens).

## Strategy 3: Use the Right Mode

| Task                  | Mode  | Why                            |
| --------------------- | ----- | ------------------------------ |
| Read code, understand | Ask   | Cheapest - no tool overhead    |
| Small edit, one file  | Edit  | Focused - minimal context      |
| Multi-file changes    | Agent | Necessary - but most expensive |

Start with the cheapest mode. Escalate only when needed.

## Strategy 4: Save-and-Resume

Use `/oneoff` to save important conversations. This avoids:

- Re-explaining context in future sessions (expensive)
- Losing decisions and having to re-derive them (expensive)
- Context window pollution from long conversations

Start a new chat for each distinct task - don't let conversations grow unbounded.

## Strategy 5: Specific Prompts

| Prompt Quality                                                                                    | Token Cost              | Reliability |
| ------------------------------------------------------------------------------------------------- | ----------------------- | ----------- |
| "Help me with my config"                                                                          | High (explores broadly) | Low         |
| "Add project 'NewApp' to Configuration.psd1 with VSCode and terminal tabs at {Dev}/GitHub/NewApp" | Low (targeted)          | High        |

Include: what you want, where it goes, what format to use. Skip: background the AI already has (from instruction files).

## Strategy 6: Mini Models for Mini Tasks

Reserve premium models (Opus 4.6, GPT 5.4) for tasks that need deep reasoning. Use mini models for:

- Syntax questions
- Small fixes
- Boilerplate
- Simple lookups

See `AI/Models/ModelSelectionGuide.md` for the full decision matrix.

## Strategy 7: Batch Independent Operations

When working on multiple independent tasks, handle them in the same session rather than separate ones. Each new session loads the full instruction stack again.

## Anti-Patterns to Avoid

1. **Over-context**: Loading all AI/Context files when you only need one section
2. **Re-research**: Not saving findings with `/oneoff`, then re-asking the same questions later
3. **Wrong model**: Using Opus 4.6 to fix a typo
4. **Unbounded conversations**: 50+ messages in one chat - context degrades, costs spike
5. **Copy-paste context**: Pasting file contents into the prompt instead of referencing them
