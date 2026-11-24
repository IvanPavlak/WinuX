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

## No personal information in anything you ship

Code, comments, tests, docs, changelog entries, commit messages and pull request text carry generic
values only (`MyProject`, `MyRepo`, `My-PC`, `you@example.com`): never a real workspace or project
name, handle, hostname, path, address, or the story of one particular run. Nothing written to a
public repository names or links a private one: not its name, pull requests, issues, branches or
plans. A link from a private repository to a public pull request leaks too, since GitHub posts a
"mentioned this" event on the public one that cannot be deleted, so name it in words there.

## Keep the working tree runnable

The developer runs the working tree while you work on it. Order a refactor so every intermediate
state works: add the new function first, move the callers to it, and remove the old one last. When a
tree is knowingly broken for a while, say so before they can run it.

## Commits and pull requests

When the user asks you to commit or open a pull request:

- **Commits:** one short subject line in the project's style (its `CONTRIBUTING.md`: imperative,
  sentence case, no trailing period, no prefix), with no body; the detail goes in the pull request.
  No AI co-author trailer or "Generated with" footer.
- **One concern per pull request.** A change that grows past one concern is split before it is
  opened.
- **The body is the repository's own `.github/PULL_REQUEST_TEMPLATE.md`**, every section kept and
  filled in the way the last merged pull request filled it (`gh pr view <number> --json body`).
- **The body describes the finished, tested change.** No test-status hedges ("not run yet", "stays
  a draft until", "pending"): the developer runs the tests before merging, so the body is written for
  that moment. Tick every box that holds for the finished change, a quality line that holds
  vacuously included; a box stays empty only when it is false or its N/A twin is ticked.
- **"Tested on"** gives the full OS line (edition, release and build, or the macOS version) and the
  shell version, each on its own line, and the machine type on its own line.
- **Notes before a checklist are a prose paragraph**, never `-` bullets: GitHub merges the two
  into one loose list.
- **Releases:** each project's `AGENTS.md` says whether a pull request ships as its own release.

## CRITICAL SAFETY - Never Act Destructively On Your Own

You are NEVER allowed to commit, push, or perform ANY destructive or irreversible operation on your own initiative - EVER. Each such action requires an explicit, in-the-moment instruction from the user for that specific action. General prior approval, "continue", "do everything", or your own judgment do NOT count as permission.

Never do these without the user explicitly asking for that exact action in the current turn:

- `git commit`, `git push`, `git reset`, `git rebase`, `git branch -D`, `git checkout -- <file>`, tag or force operations, or anything that writes to git history or a remote
- Deleting or overwriting files/directories the user did not ask you to change (`rm`, `Remove-Item`, mass overwrites)
- Creating a branch that tracks a remote branch under a different name (`git switch -c <branch> origin/master` does; use `--no-track`), or changing upstream tracking, remotes, or git configuration - a branch tracking the default branch sends the next plain `git push` straight onto it, skipping the PR
- Restructuring or moving core folders, or any other hard-to-reverse change

If such an action seems warranted, STOP and ask first, stating exactly what you intend to do, and wait for explicit confirmation. Default to the least destructive path. Creating/editing files for the task at hand and running read-only/verification commands are fine.
