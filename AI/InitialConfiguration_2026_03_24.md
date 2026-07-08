---
title: AI Utilization System - Initial Configuration
date: 2026-03-24
status: in-progress
providers: [Copilot, Claude, LocalModels]
---

# AI Utilization System - Initial Configuration

## Original Prompt

I've created the `AI/` folder in this repository to plan and implement the best utilization of Copilot and other AI systems, optimizing for both ease of use and token spending.

### Ideas Presented

1. **Specific Instructions**: Instead of repeating formatting/handling rules, use instruction files (e.g., `OutputFormatting.md`) with examples from the repository itself. When something changes, the AI already has the instructions - no tokens wasted on re-discovery.

2. **Comprehensive Documentation**: Create detailed docs for every section (like `Windows/`), explaining inner workings of every function. Enables quick navigation, reduces duplication through refactoring into shared helpers. Code comments (`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`) serve as the source of truth for documentation. Inspiration: a DocFX-based documentation project (AGENT_CONTEXT.md + scaffolding prompts pattern).

3. **Conversation Persistence ("One-Off Mode")**: On-demand mode that saves conversations to `AI/Conversations/{topic}/Conversation_yyyy_mm_dd_hhmmss.md`. Human-readable AND token-optimized. Any AI can continue the thread later - not locked to one provider or model. Triggered via `/oneoff` or `/research` slash commands.

4. **Additional proposals**: Scaffolding prompts, provider-specific guides, model selection matrices, context budgeting strategies, and more.

### Additional Requirement: Scaffolding Module

A PowerShell module (`Scaffolding`) in `Windows/PowerShell/Modules/` that provides reliable functions to:

- Add/modify Browser Groups in `Configuration.psd1`
- Add/modify Workspaces + WorkspaceActions
- Add/modify Projects + ProjectActions
- Add/modify Symbolic Links
- Add/modify Window Layouts

Paired with Copilot `.prompt.md` files that call these functions, and eventually a GUI (web/desktop) application. All documented so setup can be replicated across machines.

## Decisions Made

| Decision                 | Choice                                                                      | Rationale                                                                         |
| ------------------------ | --------------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| AI folder role           | **Centralized hub** - all AI content in `AI/`, `.github/` is thin bootstrap | Prefer centralization; this repo will grow to include Linux configs and more      |
| Copilot config           | `.github/` references `AI/`                                                 | Copilot requires `.github/`; can't be redirected. Content files live in `AI/`     |
| Conversation persistence | **Universal markdown** - any AI can consume                                 | Not locked to Copilot; human-readable; model-agnostic                             |
| Trigger mechanism        | **On-demand** via slash commands                                            | User decides what's worth saving                                                  |
| Documentation format     | **Best tool for the job** - Docsify may be rewritten                        | Single source of truth for developers AND AI, clearly understood by both          |
| Token optimization       | **Both**: minimize context window usage AND minimize requests               | No compromise on either                                                           |
| Scaffolding location     | **PowerShell Module** in `Windows/PowerShell/Modules/Scaffolding/`          | Alongside existing modules, importable, testable, works standalone or via Copilot |
| Scaffolding scope        | Browser Groups, Workspaces, Projects, SymLinks, Window Layouts              | Core configuration operations                                                     |
| Future UI                | **GUI** (web/desktop app)                                                   | Will be built after scaffolding module is stable                                  |
| AI providers             | Copilot, Claude (direct), Local models (Ollama/LM Studio)                   | Current and planned usage                                                         |

## Architecture

```
AI/                                       ← Central hub (provider-agnostic)
├── InitialConfiguration_*.md             ← This file - evolution log
├── Instructions/                         ← Reusable instruction sets
│   ├── OutputFormatting.md
│   ├── PowerShellConventions.md
│   ├── ConfigurationPatterns.md
│   ├── DocumentationStyle.md
│   └── ContextBudgeting.md
├── Context/                              ← Codebase context documents
│   ├── REPOSITORY_CONTEXT.md
│   └── WINDOWS_CONTEXT.md
├── Providers/                            ← Provider-specific optimization guides
│   ├── Copilot.md
│   ├── Claude.md
│   └── LocalModels.md
├── Models/
│   └── ModelSelectionGuide.md
├── Conversations/                        ← One-off conversation persistence
│   └── {topic-name}/
│       └── Conversation_yyyy_mm_dd_hhmmss.md
└── Templates/
    ├── ConversationTemplate.md
    └── ResearchTemplate.md

.github/                                  ← Copilot bootstrap (thin pointers)
├── copilot-instructions.md
├── instructions/
│   ├── powershell.instructions.md
│   └── documentation.instructions.md
├── prompts/
│   ├── oneoff.prompt.md
│   ├── research.prompt.md
│   ├── document.prompt.md
│   ├── add-browser-group.prompt.md
│   ├── add-workspace.prompt.md
│   ├── add-project.prompt.md
│   ├── add-symlink.prompt.md
│   └── add-window-layout.prompt.md
└── agents/
    └── researcher.agent.md

Windows/PowerShell/Modules/Scaffolding/   ← Scaffolding module
├── Scaffolding.psd1
├── Scaffolding.psm1
└── Functions/
    ├── Add-BrowserGroup.ps1
    ├── Add-Workspace.ps1
    ├── Add-Project.ps1
    ├── Add-SymbolicLink.ps1
    └── Add-WindowLayout.ps1
```

## Implementation Phases

### Phase 0: Initial Setup ✅

Save this prompt for iteration tracking.

### Phase 1: Foundation

- `.github/copilot-instructions.md` - bootstrap pointing to `AI/`
- `AI/Context/REPOSITORY_CONTEXT.md` - high-level repo architecture
- `AI/Context/WINDOWS_CONTEXT.md` - module functions, config hierarchy, patterns

### Phase 2: Instructions

- `AI/Instructions/OutputFormatting.md` - output conventions with real examples
- `AI/Instructions/PowerShellConventions.md` - coding standards
- `AI/Instructions/ConfigurationPatterns.md` - Configuration.psd1 modification guide
- `.github/instructions/powershell.instructions.md` - Copilot file instruction
- `.github/instructions/documentation.instructions.md` - Copilot file instruction

### Phase 3: Conversation Persistence

- `AI/Templates/ConversationTemplate.md` - one-off conversation template
- `AI/Templates/ResearchTemplate.md` - research conversation template
- `.github/prompts/oneoff.prompt.md` - `/oneoff` slash command
- `.github/prompts/research.prompt.md` - `/research` slash command

### Phase 4: Documentation Integration

- `AI/Instructions/DocumentationStyle.md` - comment-to-doc conventions
- `.github/prompts/document.prompt.md` - `/document` slash command

### Phase 5: Provider Guides

- `AI/Providers/Copilot.md` - Copilot optimization + model selection
- `AI/Providers/Claude.md` - Claude optimization
- `AI/Providers/LocalModels.md` - Local model guide
- `AI/Models/ModelSelectionGuide.md` - cross-provider decision matrix

### Phase 6: Scaffolding

- `Windows/PowerShell/Modules/Scaffolding/` - PowerShell module for config modification
- `.github/prompts/add-*.prompt.md` - Copilot slash commands wrapping scaffolding functions
- Documentation for multi-machine setup

### Phase 7: Advanced

- `.github/agents/researcher.agent.md` - research agent with auto-save
- `AI/Instructions/ContextBudgeting.md` - token optimization meta-guide
- Hooks evaluation (auto-doc updates, session start)

## Evolution Log

| Date       | Change           | Reason                 |
| ---------- | ---------------- | ---------------------- |
| 2026-03-24 | Initial creation | First planning session |
