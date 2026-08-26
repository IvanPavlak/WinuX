# WinuXConfigurator

An AI-assisted way to configure WinuX. Point any capable AI assistant at this document and it interviews you, one decision at a time, and writes the answers into your own configuration file. Everything, nothing, or any subset you name.

WinuX ships empty by design. The base `Configuration.psd1` is dozens of top-level keys of shape with almost no content: no hostnames, no paths, no identity, no app choices. That is what makes it forkable, and it is also why a fresh clone does very little until somebody fills it in. Only a subset of the exported functions read configuration at all - each module's guides index says exactly which. This document is the map through that.

## How to Start

Open a session with an AI assistant that can read files in your WinuX checkout, and say:

> Read this document and configure WinuX with me.

Point it at whichever of these it can reach:

- Local file: `docs/configuration/winux-configurator.md` in your checkout.
- Raw URL: `https://raw.githubusercontent.com/IvanPavlak/WinuX/master/docs/configuration/winux-configurator.md`

The assistant does the rest: it reads the guides, asks you the decisions they contain, and writes what you answer into `Configuration.local.psd1`.

> [!NOTE]
> Nothing here is specific to one AI product. The requirements below are stated as capabilities, not tool names, so any assistant that has them can run the session.

## What the Assistant Needs

| Capability | Required | What it is used for |
| ---------- | -------- | ------------------- |
| Read files from disk | Yes | The guides under `docs/configuration/guides/`, the base `Configuration.psd1`, and your existing `Configuration.local.psd1` |
| Ask questions in a conversation and read the answers | Yes | The interview itself |
| Write files to disk | No | Writing `Configuration.local.psd1` directly. Without it, the assistant prints each fragment and you paste it in |
| Run PowerShell commands | No | The per-module verification steps. Without it, the assistant prints the commands and you run them and report back |

An assistant with only the first two capabilities can still run a complete session. It just hands you the text instead of writing it.

## Ground Rules (for the AI assistant)

These are not suggestions. A session that breaks any of them has damaged something the user cannot easily get back.

1. **Never edit the base `Configuration.psd1`, and never edit a committed `Data/*.csv`.** Those files are upstream's. Every value you write goes into one of: `Configuration.local.psd1` (settings), a `<name>.local.csv` overlay beside the committed CSV (app lists), or a payload file the configuration points at (layouts, wallpapers, themes). See [Fork Model](../contributing/fork-model.md) for why this split exists and how it survives a pull from upstream.

2. **Know which way the merge goes before you write.** `Load-PathConfiguration` deep-merges the local file over the base one, and the two halves behave differently. **Hashtables merge per key** - adding one entry leaves the others alone. **Arrays and scalars replace wholesale** - writing an array key discards the entire base array. Before you write an array key, read the base array out of `Configuration.psd1`, and write the base entries plus the user's new entry. Never write a one-element array over a twelve-element base array and call it "added".

3. **Never invent a machine-specific value. Ask.** Hostnames, MAC addresses, drive letters, install paths, usernames, emails, repository URLs, monitor arrangements: all of it is knowledge only the user has. A plausible guess that is wrong is worse than a question, because it looks configured. If the user does not know either, leave the key unset and say so - every consumer in WinuX guards on presence and no-ops rather than failing.

4. **No git, no deletions, no destructive commands.** No `commit`, `push`, `tag`, `rebase`, `reset`, `checkout --`, branch deletion, or force anything. No removing files or directories. No commands that change the machine, install software, or restart anything. Configuration writes plus read-only verification, and nothing else. If the user asks for a git operation, tell them exactly what to run and let them run it.

5. **One question at a time, and every question has three exits.** Ask, wait, then ask the next. Each question must accept: an answer, "use the default" (take the guide's stated default and move on), or "skip" (leave the key untouched entirely). Never batch ten questions into one message, and never treat silence as consent.

6. **After every write, show what you wrote and where.** The exact fragment, and the exact file. The user has to be able to see and undo everything without asking you what happened. Before your first write, if `Configuration.local.psd1` already exists, copy it into the repository's backup sink at `Backups/Windows/Config/Configuration.local/<yyyy-MM-dd_HH-mm-ss>/` (creating the folders) so there is a one-step way back - the same place every WinuX writer keeps its backups (see [Backups](../reference/backups.md)). If you cannot create directories, fall back to a sidecar copy named `Configuration.local.psd1.bak` beside the file; that exact name is gitignored.

7. **Read the guide before you ask its questions.** Do not paraphrase from memory. The decisions in the guides are written to be read out as written, and they carry the defaults and the trade-offs.

## Session Protocol

### Step 0: Prerequisites

Establish these before asking a single configuration question. If any of them is wrong, everything downstream is built on sand.

1. **Find the repository.** Locate the WinuX (or fork) checkout. `Get-RepositoryPath` reports it if PowerShell is available; otherwise ask the user for the path. Confirm `Windows/PowerShell/Configuration.psd1` exists under it.
2. **Find or create the local file.** Check for `Windows/PowerShell/Configuration.local.psd1`. If it exists, read it - it is the current state and you are editing it, not replacing it. If it does not, create the minimal skeleton:

    ```powershell
    # Configuration.local.psd1
    @{
    }
    ```

    `Initialize-Configuration` also writes this skeleton if the user would rather it did.
3. **Establish the machine type.** Ask for the machine's hostname, and check whether `HostnameToMachineType` maps it. If it does not, the machine resolves to `DefaultMachineType` (`Test` in the base configuration), and almost every per-machine-type key will look unconfigured. This is the single most common reason a WinuX setup appears to ignore its own configuration.
4. **Confirm the profile loads.** If PowerShell is available: `Reload-PowerShellProfile`, then check that `$global:Configuration` and `$global:MachineType` are populated. If they are not, stop and fix that first - there is no point configuring a system that is not loading its configuration.

### Step 1: Mode

Ask the user which mode they want, and honour it exactly.

| Mode | What it means |
| ---- | ------------- |
| **Everything** | Walk every module in the [recommended order](#recommended-module-walk-order). Long, thorough, resumable |
| **By module** | The user names one or more modules. Walk only those |
| **Single function** | The user names a function. Open its guide, ask only its decisions |
| **Review only** | Ask nothing and write nothing. Read the current `Configuration.local.psd1`, compare it against the coverage map, and report what is configured, what is not, and what looks inconsistent |

### Step 2: Interview

For each module in scope:

1. Open `docs/configuration/guides/<module>/README.md`.
2. Walk its **Configurable Functions** table top to bottom. Functions listed under **Functions With No Configuration** need nothing - do not ask about them.
3. For each function, open `docs/configuration/guides/<module>/<Function-Name>.md` and read two sections: `## Configuration Keys` (the keys, their types, their base defaults, and what they control) and `## Decisions` (the questions).
4. Ask each numbered decision as written. Each one carries its own `Options:` and `Default:` sub-bullets - offer both. Link the guide so the user can read the depth if they want it.
5. If the user says "skip", move on without writing anything for that key. If they say "use the default", state what the default actually is and move on.

Two shortcuts worth taking: a module's task guide (where it has one) covers several functions at once and is often a better first pass than the individual guides; and if the user answers a key in one function's interview, do not ask for it again when a later function reads the same key - tell them it is already set and move on.

### Step 3: Write As You Go

Write after each function, not at the end of the module. A session that is interrupted after ten answers should have ten answers on disk.

1. Follow the guide's `## Where to Put Values` section for the destination.
2. Apply ground rule 2. For an array key, read the base array first.
3. Write the fragment.
4. Show the user the exact text you wrote and the exact file you wrote it to.

### Step 4: Verify Per Module

At the end of each module, before moving to the next:

1. `Reload-PowerShellProfile`
2. Read back each key that was set: `$global:Configuration.<Key>`. This is the ground truth. If a value is not there, the local file did not parse (`Test-ConfigurationSchema` will say so) or the key landed at the wrong nesting level.
3. Run the read-only commands from the guides' `## Verification` sections. They are chosen to be safe: they inspect and report, they do not act.

If PowerShell is not available to you, print the commands and ask the user to run them and paste the output back.

### Step 5: Finish

1. Summarise: which modules were walked, which keys were set, which were skipped, and which are still empty.
2. Hand the user the commands to confirm the repository is still healthy. Do not run the test suite yourself:

    ```powershell
    Run-Tests
    List-Functions -ListDiscrepancies
    ```

3. Suggest a smoke test that exercises what was configured - `Open-Browser`, `Open-Workspace`, `Visualize-Layouts` - whichever is relevant.
4. Remind the user that `Configuration.local.psd1` is theirs. Upstream WinuX gitignores it; a fork may commit it so it syncs across machines. Either way, the values are now on disk and nothing else has to be done to keep them.

## Recommended Module Walk Order

Order matters. Machine type and base paths gate everything downstream: a wrong `BasePaths` entry makes every later step do the right thing in the wrong place.

| # | Module | Why here |
| - | ------ | -------- |
| 1 | [bootstrap](guides/bootstrap/README.md) | Machine detection, `BasePaths`, `PathTemplates`, step toggles. Everything else resolves through these |
| 2 | [git](guides/git/README.md) | Identity and repository groups. Short, and needed before repositories exist on disk |
| 3 | [application](guides/application/README.md) | App lists, browsers, editors. The first module whose results are visible |
| 4 | [system](guides/system/README.md) | The machine itself: theme, wallpaper, taskbar, locale, keyboard, power, WSL, symbolic links. The widest surface |
| 5 | [workflow](guides/workflow/README.md) | Projects and workspaces, which reference the paths and apps configured above |
| 6 | [window](guides/window/README.md) | Layouts and zones. Depends on knowing which workspaces exist |
| 7 | [helper](guides/helper/README.md) | Spinners, colours, translation defaults. Mostly cosmetic |
| 8 | [configuration](guides/configuration/README.md) | The writers. Useful once there is configuration to edit programmatically |
| 9 | [logging](guides/logging/README.md) | Verbosity and retention. One key, set it whenever |
| 10 | [tests](guides/tests/README.md) | Nothing to configure. Listed for completeness |

## Coverage Map

| Module | What its configuration covers |
| ------ | ----------------------------- |
| [application](guides/application/README.md) | Package-manager app lists, browser groups and the default browser, editor and solution lists, WSL tabs, executable paths |
| [bootstrap](guides/bootstrap/README.md) | Machine detection, base paths, path templates, bootstrap step toggles, package managers, the app-list read path |
| [configuration](guides/configuration/README.md) | The `Add-*` writers, the app-list overlay writer, and the schema and section primitives they use |
| [git](guides/git/README.md) | Git identity and package, repository groups |
| [helper](guides/helper/README.md) | Loading spinners, console colours, translation defaults, project and step resolution, the function reference tooling |
| [logging](guides/logging/README.md) | Console verbosity, per-level colours, file logging, log retention |
| [system](guides/system/README.md) | Theme and wallpaper, taskbar, locale and keyboard, power, environment variables, Wake-on-LAN, WSL provisioning, symbolic links, special folders |
| [tests](guides/tests/README.md) | Nothing. The test runner is configuration-free |
| [window](guides/window/README.md) | FancyZones layout numbers and zone names, per-machine layout overrides, reset defaults, window sizing and snap inset |
| [workflow](guides/workflow/README.md) | Workspaces and their action lists, projects and their action lists, terminal tabs, Docker stacks and cleanup actions, campaigns |

## If the Session Is Interrupted

The guides are idempotent and the state is on disk, so resuming costs nothing:

1. Re-read `Configuration.local.psd1`. That is the record of what was answered - not the conversation, which is gone.
2. Compare it against the coverage map above and the module index tables. Anything present is done.
3. Resume at the first module whose keys are still unset, in the recommended walk order.
4. Re-asking a question that was already answered is harmless: the answer is either the same, or the user changed their mind and wants the new one.

The one thing not to do is start over by writing a fresh `Configuration.local.psd1`. That discards answers the user already gave.

## Related

- [Configuration overview](overview.md) - how the configuration system fits together
- [Configuration reference](configuration-reference.md) - every key, section by section
- [Placeholder system](placeholder-system.md) - `{Dev}`, `{User}`, `{MachineType}`, `{RepoRoot}`, `{AppData}`
- [Machine types](machine-types.md) - detection, valid types, layout overrides
- [Fork Model](../contributing/fork-model.md) - why your values live in `Configuration.local.psd1`
- [CoreAiRules](../ai/coreairules.md) - the machine-global guardrails an AI assistant runs under
