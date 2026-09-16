---
name: winux-configurator
description: Interview the user decision by decision and write their answers into the WinuX configuration (Configuration.local.psd1, app-list overlays, payload files), one module at a time, with a per-module read-back. Use when the user wants to configure WinuX or a WinuX fork, set up a fresh clone, fill in machine-specific values (hostname, base paths, apps, workspaces, layouts), review what is already configured, or resume an interrupted configuration session.
argument-hint: "Everything, a module name, a function name, or 'review'"
---

The user wants their WinuX configuration filled in by interview. The protocol is not in this file: it lives in the repository, in `docs/configuration/winux-configurator.md`, together with the per-function guides it walks. Read it and run it.

## Step 1 - Locate the repository

This skill is linked into the harness's user-level skills directory, so the current working directory is almost never the checkout.

- The skill folder (`~/.claude/skills/winux-configurator` or `~/.agents/skills/winux-configurator`) is a symbolic link to `<RepoRoot>/AI/Skills/own/winux-configurator/`. Resolve the link and take the folder three levels above it. In PowerShell with the WinuX profile loaded, `(Get-RepositoryPath).Repo` answers directly.
- Confirm the result by checking that `<RepoRoot>/Windows/PowerShell/Configuration.psd1` exists. If it does not, ask the user for the checkout path.
- If the repository cannot be reached at all, fetch the protocol from `https://raw.githubusercontent.com/IvanPavlak/WinuX/master/docs/configuration/winux-configurator.md` and tell the user that without the checkout you can interview and print fragments, but not write or verify.

## Step 2 - Read the protocol

Read `<RepoRoot>/docs/configuration/winux-configurator.md` in full before the first question. It carries the ground rules, the prerequisites, the mode choice, the interview loop, the write rules, the per-module verification and the walk order. Read each module's guides from `<RepoRoot>/docs/configuration/guides/<module>/` as you reach it, and read each decision out as written rather than from memory.

## Step 3 - Run the session

Follow the protocol's Session Protocol steps 0 through 5 in order. The session is done when every module in the chosen scope has been walked, written, and read back out of `$global:Configuration`, and the user has the closing summary of what was set, skipped and left empty.
