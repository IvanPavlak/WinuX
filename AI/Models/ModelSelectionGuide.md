# Model Selection Guide

> **Purpose**: Quick-reference decision matrix for choosing the right model per task.
> **Provider**: GitHub Copilot (all models accessed through VS Code)

## Decision Matrix

| Task Type                          | Recommended Model          | Mode                | Why                                           |
| ---------------------------------- | -------------------------- | ------------------- | --------------------------------------------- |
| **Multi-file refactor**            | Opus 4.6                   | Agent               | Deep reasoning across files                   |
| **New module/function**            | Opus 4.6                   | Agent               | Complex structure, conventions                |
| **Configuration.psd1 changes**     | Opus 4.6 / GPT 5.4         | Agent               | Nested structure, placeholder awareness       |
| **Debug complex issue**            | Opus 4.6                   | Agent               | Needs broad context and reasoning             |
| **Architecture planning**          | Opus 4.6                   | Ask                 | Deep analysis, no file changes                |
| **Single function implementation** | GPT 5.4                    | Agent               | Clear scope, good instruction following       |
| **Code review**                    | GPT 5.4                    | Ask                 | Read-only analysis                            |
| **Documentation generation**       | GPT 5.4                    | Agent + `/document` | Template-driven, structured output            |
| **Add project/workspace/symlink**  | GPT 5.4                    | Agent               | Standard patterns in ConfigurationPatterns.md |
| **Research topic**                 | GPT 5.4 / Opus 4.6         | Agent + `/research` | Depends on complexity                         |
| **Quick syntax question**          | Raptor Mini                | Ask                 | Fast, low cost                                |
| **Fix typo / rename**              | Raptor Mini / GPT 5.4 Mini | Edit                | Minimal reasoning needed                      |
| **Boilerplate / template code**    | GPT 5.4 Mini               | Agent               | Clear patterns to follow                      |
| **Explain existing code**          | Sonnet 4.5 / GPT 5.4 Mini  | Ask                 | Read-only, moderate reasoning                 |
| **Usage limits tight**             | Sonnet 4.5 → Mini models   | Any                 | Fallback chain                                |

## Fallback Chain

When daily limits are reached on your primary model:

```
Opus 4.6 → GPT 5.4 → Sonnet 4.5 → Raptor Mini / GPT 5.4 Mini
```

Each step down trades reasoning depth for availability. Adjust task complexity accordingly - don't attempt multi-file refactors with mini models.

## Cost/Quality Tradeoffs

| Tier         | Models                    | Quality  | Speed    | Usage Budget   |
| ------------ | ------------------------- | -------- | -------- | -------------- |
| **Premium**  | Opus 4.6, GPT 5.4         | Highest  | Moderate | Limited daily  |
| **Standard** | Sonnet 4.5                | Good     | Fast     | More available |
| **Economy**  | Raptor Mini, GPT 5.4 Mini | Adequate | Fastest  | Most available |

## Rules of Thumb

1. **If the task touches >3 files** → Premium model + Agent mode
2. **If the task is "read and tell me"** → Standard/Economy + Ask mode
3. **If the task is "change this one line"** → Economy + Edit mode
4. **If you'll need this answer again** → Use `/oneoff` to save it regardless of model
5. **When in doubt** → Start with GPT 5.4 (good default); escalate to Opus 4.6 if it struggles

## Last Verified

March 2026 - Update this guide when new models become available or pricing changes.
