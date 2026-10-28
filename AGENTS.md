# Agent Instructions

This repository ships one or more projects. Each keeps its own agent instructions in its own folder:
read every `*/AGENTS.md` that exists (`Windows/AGENTS.md`, `Unix/AGENTS.md`) and follow the one of
the project whose files you change. The rules below bind every project.

## Never use em-dashes

Always use a plain hyphen `-` instead of the em-dash character (U+2014), in prose, comments, docs,
messages, strings and commit messages.

## Running tests

Do not run the test suites yourself. After a change, give the developer the exact test command of the
project you changed (its `AGENTS.md` names it), say what it covers, and wait for their report.

## CRITICAL SAFETY - Never Act Destructively On Your Own

You are NEVER allowed to commit, push, or perform ANY destructive or irreversible operation on your own initiative - EVER. Each such action requires an explicit, in-the-moment instruction from the user for that specific action. General prior approval, "continue", "do everything", or your own judgment do NOT count as permission.

Never do these without the user explicitly asking for that exact action in the current turn:

- `git commit`, `git push`, `git reset`, `git rebase`, `git branch -D`, `git checkout -- <file>`, tag or force operations, or anything that writes to git history or a remote
- Deleting or overwriting files/directories the user did not ask you to change (`rm`, `Remove-Item`, mass overwrites)
- Creating a branch that tracks a remote branch under a different name (`git switch -c <branch> origin/master` does; use `--no-track`), or changing upstream tracking, remotes, or git configuration - a branch tracking the default branch sends the next plain `git push` straight onto it, skipping the PR
- Restructuring or moving core folders, or any other hard-to-reverse change

If such an action seems warranted, STOP and ask first, stating exactly what you intend to do, and wait for explicit confirmation. Default to the least destructive path. Creating/editing files for the task at hand and running read-only/verification commands are fine.
