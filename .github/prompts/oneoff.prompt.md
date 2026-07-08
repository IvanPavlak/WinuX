---
description: "Persist the current conversation as a one-off topic for future continuation by any AI. Creates a structured markdown file in AI/Conversations/."
argument-hint: "Topic name (e.g., 'powershell-module-refactor')"
agent: "agent"
---

# One-Off Conversation Persistence

You are saving this conversation for future continuation. Follow these steps exactly:

## 1. Create the conversation file

- Directory: `AI/Conversations/{topic-slug}/` (create if it doesn't exist)
- Filename: `Conversation_{yyyy}_{MM}_{dd}_{HHmmss}.md`
- Use the template from [ConversationTemplate.md](../../AI/Templates/ConversationTemplate.md)

## 2. Fill in the template

- **title**: Use the topic provided by the user
- **date**: Current date/time in ISO 8601
- **model**: The model being used in this conversation
- **provider**: The AI provider (Copilot, Claude, etc.)
- **status**: `open` (unless the user says it's resolved)

## 3. Write the content

- **Context**: Why this conversation started - include enough background for a cold start
- **Key Findings**: Summarize all significant discoveries or solutions
- **Decisions Made**: List every decision with its rationale
- **Open Questions**: Any unresolved questions
- **Action Items**: Concrete next steps with checkboxes
- **Summary**: Write a 2-3 paragraph summary that contains ALL context needed for any AI (Copilot, Claude, local model) to resume this conversation without access to the original chat history

## 4. Prioritize token efficiency

- Summarize, don't transcribe - no verbatim chat logs
- Use structured formats (tables, bullet lists) over prose
- The summary section is the most important - it's what future AI sessions will read first
