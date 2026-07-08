---
description: "Start a structured research session with comparison matrix and recommendation. Saves findings to AI/Conversations/ for future reference."
argument-hint: "Research question (e.g., 'best SSO solution for .NET')"
agent: "agent"
---

# Research Mode

You are conducting structured research on the given topic. Follow these steps:

## 1. Understand the question

- Clarify the research question and scope
- Ask the user about constraints (budget, compatibility, timeline) if not provided

## 2. Research systematically

- Identify 2-4 viable options
- For each option, evaluate: pros, cons, cost, complexity, maintenance burden
- Use web search and documentation when available

## 3. Build a comparison

- Create a comparison matrix with weighted criteria
- Provide a clear recommendation with confidence level

## 4. Save the findings

- Directory: `AI/Conversations/{topic-slug}/`
- Filename: `Conversation_{yyyy}_{MM}_{dd}_{HHmmss}.md`
- Use the template from [ResearchTemplate.md](../../AI/Templates/ResearchTemplate.md)
- Fill in all sections including the summary for future AI continuation

## 5. Token efficiency

- Cite sources concisely (name + one-line takeaway)
- Use tables over prose for comparisons
- The summary section must stand alone - any AI should be able to continue from it
