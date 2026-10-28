# Fork Model

WinuX is meant to be **forked**. Your machine is yours - your identity, your paths, your extra apps
and repositories. At the same time, the engine and documentation should have a single home that
everyone improves together. The fork model reconciles the two.

## The idea

- **WinuX (upstream)** is the single source of truth for the engine, modules, docs, and the generic
  base `Configuration.psd1`.
- **Your fork** is a normal Git fork of WinuX. You pull improvements from upstream like any fork.
- **Your personal values** live in `Configuration.local.psd1` - an override (gitignored by
  default) that is deep-merged over the base at load time. Because the committed base config is
  never edited with personal data, pulling upstream updates never conflicts on configuration.

```
WinuX (upstream)               your fork
─────────────────              ─────────────────────────────────────
Configuration.psd1   ──pull──►  Configuration.psd1         (tracks upstream, unchanged)
                                Configuration.local.psd1   (yours; gitignored by default)
                                          │
                              deep-merged at load time
                                          ▼
                                 effective configuration
```

## How the override works

At load time `Load-PathConfiguration` reads the base `Configuration.psd1`, then - if a sibling
`Configuration.local.psd1` exists - deep-merges it on top. The PowerShell profile performs the same
merge early in startup, so machine detection and the modules path use your values too. Any key you
don't override falls through to the base.

`Configuration.local.psd1` holds only what differs from the base, for example:

```powershell
@{
    GitConfig             = @{
        UserName  = "Jane Doe"
        UserEmail = "jane@example.com"
    }
    BasePaths             = @{
        Machine = @{ Dev = "C:\Users\Jane\Development\GitHub"; User = "C:\Users\Jane" }
    }
    HostnameToMachineType = @{
        "JANE-PC" = "Machine"
    }
}
```

> [!TIP]
> You don't have to write this by hand. [`Initialize-Configuration`](../modules/bootstrap.md#initialize-configuration)
> generates it for you on first run, and the bootstrap one-liner can pass your values straight in.

### One machine vs. several

By default `Configuration.local.psd1` is **gitignored**, which is ideal for a single machine: it stays
local and can never leak personal data upstream. If you run several machines and want your settings to
travel between them, **commit it in your fork** - remove its line from `.gitignore` (or `git add -f
Windows/PowerShell/Configuration.local.psd1`) and commit. Upstream never tracks that file, so committing
it in your fork never conflicts on a pull; it simply syncs across your machines like any other file. Keep
machine-specific values keyed by machine type / hostname so the one committed file serves every machine.

## Keeping your own app lists (the `.local.csv` overlay)

`Configuration.local.psd1` covers your **settings**. Your **app lists** work the same way, for the same
reason. WinuX ships three committed CSVs under `Windows/PowerShell/Modules/Bootstrap/Data/` holding only
the software WinuX itself needs; everything you add for yourself goes in a sibling overlay:

```
WinuX (upstream)                      your fork
─────────────────                     ─────────────────────────────────────────
WinGetApps.csv          ──pull──►      WinGetApps.csv           (tracks upstream, unchanged)
                                       WinGetApps.local.csv     (yours; gitignored by default)
                                                 │
                                       layered at read time
                                                 ▼
                                        effective app list
```

[`Import-AppCsv`](../modules/bootstrap.md#import-appcsv) does the layering, and every reader goes through
it - all three `Install-*Apps` functions and `Get-PinnedApps` - so what the overlay says is what gets
installed. An overlay row **adds** a new app, **replaces** a committed row with the same `App` (to pin a
version, change the scope, or re-target the machine), or - written as `-<id>` - **removes** one you don't
want. [`Save-AppCsvOverlay`](../modules/configuration.md#save-appcsvoverlay) writes it with validation and
a timestamped backup in the gitignored sink; you can also just edit the file. The full reference is in
[Software List: Machine-Local Overlay](../reference/software-list.md#machine-local-overlay).

**Never edit the committed CSVs in your fork.** They are ordinary upstream-tracked files now, exactly like
`Configuration.psd1`: leave them alone and every pull applies cleanly while you keep receiving upstream's
baseline changes.

> [!IMPORTANT]
> **Migrating an older fork.** Before this, the three CSVs were marked `merge=ours` and forks curated them
> in place. That attribute has been removed, so a fork that still keeps its apps in the committed CSVs will
> have them overwritten by the next `git merge winux/master`. Move them first - it is a one-time copy:
> take your added rows out of `WinGetApps.csv` into a new `WinGetApps.local.csv` (same header on line 1),
> write `-<id>` rows for any shipped app you had deleted, restore the committed file to upstream's version
> (`git checkout winux/master -- Windows/PowerShell/Modules/Bootstrap/Data/`), and repeat for Scoop and
> Chocolatey if you use them. Then pull as usual.

## Keeping your own payloads (the `merge=ours` protection)

A few other tracked files are yours but have no "base + override" split - your payload configs. WinuX ships
generic/blank versions; your fork edits them in place. So that an upstream pull never overwrites your
versions, WinuX's `.gitattributes` marks them with the **`ours` merge driver**:

```
Git/.gitconfig                                                 merge=ours
NuGet/nuget.config                                             merge=ours
Firefox/user.js                                                merge=ours
docs/custom/README.md                                          merge=ours
```

`merge=ours` means: when `git merge winux/master` brings a change to one of these files and your fork
has changed it too, Git keeps **your** copy and ignores the incoming one. Your fork inherits this
`.gitattributes` automatically (it is a normal tracked file), so you never have to add it yourself.

The generic `Git/.gitconfig` ends with an `[include] path = ~/.gitconfig.local` block, read last so its
values win: that file is where a fork or another operating system puts machine-local overrides. Git
ignores an include whose file is missing, so a machine without one is unaffected. Keep the include when
you replace the file with your own.

**One-time setup per machine.** The `ours` driver must be _registered_ before Git will run it. The bootstrap
does this for you (`git config --global merge.ours.driver true`). If you set a clone up by hand, run that one
command yourself, once. Git will not auto-register a merge driver from a cloned repo - a deliberate
security boundary - so this can never be fully automatic; the bootstrap (or that one-liner) is as close as
it gets. Until it is registered, Git just does a normal merge for those files, so nothing breaks - you only
lose the "keep mine" behavior.

**What it protects, and what it does not.** Git only runs a merge driver when both sides changed the file.
A payload you have edited is protected: every later upstream change to it is ignored, which is the intent
for payloads that are wholly yours. A payload you never edited is not: Git takes upstream's version
directly, so it keeps following upstream (it is still the generic file) until you edit it. An upstream
deletion of a payload you edited is a modify/delete conflict the driver does not handle; resolve it by hand.

**Trade-off.** Once you have edited a payload, it no longer receives upstream changes. If WinuX later
restructures one and you want the new shape, diff it against upstream and port what you want by hand. That trade-off is exactly why the app lists moved off `merge=ours` and onto an
overlay: there, the base can keep improving upstream while your choices stay yours.

## The Custom area - your code, upstream's layout

`Configuration.local.psd1` covers your **settings**, `*.local.csv` covers your **app lists** and
`merge=ours` covers your **payload configs**; the **Custom area** covers your **code and docs** - everything you build that WinuX does not (yet) ship. It is
a fork-owned subtree that mirrors the module tree, so upstream pulls never touch it and promoting something
into WinuX later is a mechanical move:

```
Windows/PowerShell/Modules/
├── Application/                          # upstream engine - your fork never edits these
├── ...
└── Custom/                               # fork-owned; upstream ships only the loader + README
    ├── Application/
    │   ├── Functions/Open-MyApp.ps1      # extends the Application family
    │   └── Tests/Open-MyApp.Tests.ps1    # discovered by Run-Tests
    └── MyModule/                         # a whole fork-owned module (own .psd1 + .psm1)

docs/
├── winux/modules/application.md          # upstream reference - your fork never edits these
└── custom/application.md                 # your entries, same man-style format
```

- Mirror payload functions are loaded and exported by the `Custom` module, which autoloads on first use
  via its `FunctionsToExport` (empty upstream; your fork adds one entry per function, like any module);
  whole modules under `Modules/Custom/` autoload from their own manifests the same way.
- Upstream never writes inside your payload directories or your `docs/custom/<module>.md` pages, so pulling
  upstream can never conflict with them - no merge driver needed.
- The engine wins on a name collision: a Custom file cannot silently shadow upstream behavior.
- The same quality bar applies: `Run-Tests` discovers Custom tests, and `List-Functions
  -ListDiscrepancies` checks Custom functions against their `docs/custom/` pages.

When something matures, **graduate it**: `git mv` the function, tests, and doc entry into their upstream
locations and open a PR. The step-by-step checklist lives in
[`Windows/PowerShell/Modules/Custom/README.md`](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Custom/README.md).

## Setting up your fork

1. **Fork** WinuX on GitHub and clone your fork.
2. **Add the upstream remote** under the name WinuX's manifest gives it, so you can merge project
   updates:

    ```powershell
    git remote add winux https://github.com/IvanPavlak/WinuX.git
    ```

3. **Personalize** - run [`Initialize-Configuration`](../modules/bootstrap.md#initialize-configuration) (or the bootstrap
   one-liner), which writes your `Configuration.local.psd1`. It is gitignored by default, so it
   never travels to GitHub; if you run several machines, commit it in your fork instead - see
   "One machine vs. several" above.
4. **Add your apps** to `Windows/PowerShell/Modules/Bootstrap/Data/WinGetApps.local.csv` (and the Scoop /
   Chocolatey overlays if you use them), never to the committed CSVs - see
   [Keeping your own app lists](#keeping-your-own-app-lists-the-localcsv-overlay).
5. **Install** as usual - see [Installation](../getting-started/installation.md).

Nothing else is configured: no tag refspec, no `--no-tags`, no fork settings file. That is the
zero-config fork.

A private fork runs no workflow at all: every job of every upstream's workflows is skipped in a
private repository, so no Actions minutes are spent on it. Run `Run-Tests` locally instead; the public
upstreams run the same suites on every pull request.

## Merging upstream updates

```powershell
Merge-Upstreams winux
```

[`Merge-Upstreams`](../modules/git.md#merge-upstreams) fetches the remote, merges its default branch with
`--no-commit --no-ff`, applies the ownership rule below to every changed path, and stops with the
merge staged. It prints what it took, what it declined, the commit message to use
(`Merge winux master: 2.0.0`) and the push command; it never commits, pushes or rebases. Review with
`git diff --cached`, then commit - or undo everything with `git merge --abort`. `-DryRun` lists exactly what the
real run would take, put back and stop on as a conflict, without merging: `git merge-tree` computes the same
merge without touching your index or working tree (git 2.38 or newer). A plain `git merge winux/master` still works for a fork of WinuX alone; the
command adds the ownership rule, which matters as soon as a fork has two upstreams.

Because your personal settings live in the override (not the tracked base config), your apps live in the
`.local.csv` overlays (not the tracked lists), and your payload configs are protected by `merge=ours` (see
above - just make sure the driver is registered once), these updates apply cleanly: neither your
configuration nor your owned files are a source of conflicts. Custom-area code and docs live in fork-owned
paths upstream never touches, so they never conflict either. If you have edited _other_ tracked files
(engine, docs), resolve those as you normally would.

The version number tells you how much attention a merge needs - see
[VERSIONING](https://github.com/IvanPavlak/WinuX/blob/master/Windows/VERSIONING.md). A PATCH or MINOR release
never changes what your override, your overlays or your Custom-area code rely on; a MINOR may *deprecate*
something, in which case the old shape keeps working and the release notes (`### Deprecated`) name the
replacement. A MAJOR is where deprecated shapes are removed, with their migrations repeated under
`### Removed`. So the habit that keeps merges uneventful is: read the `### Deprecated` entries of
each release you merge and migrate them in your override while the old shape still works, and a MAJOR
arrives with nothing left to do.

> [!NOTE]
> Keeping personal values out of tracked files is what makes this work. Avoid editing
> `Configuration.psd1` with machine-specific values or the `Data/*.csv` app lists with your own apps; put
> them in `Configuration.local.psd1` and the `*.local.csv` overlays instead.

## Rooms, mirror files and the hallway

A fork can merge more than one upstream. WinuX ships Windows; its macOS counterpart,
[Foundation](https://github.com/IvanPavlak/Foundation), ships the Mac, and one dotfiles repository can
merge both. Think of the fork as a house: each upstream is a tenant with its own rooms, and the fork is
the landlord of everything else. Each upstream ships a manifest that lists its rooms -
`Windows/PowerShell/Upstream.conf` for WinuX, `Unix/config/upstream.conf` for Foundation - and on a merge
every changed path is handled by exactly one rule:

| The path is | Example | What happens |
| ----------- | ------- | ------------ |
| in that upstream's rooms (`own`) | `Windows/PowerShell/Modules/Git/...`, `docs/winux/modules/git.md` | Always taken. Every WinuX file lives in its rooms, so nothing of the project is ever lost. |
| a `mirror` file, identical in every upstream by contract | `LICENSE`, `CODE_OF_CONDUCT.md`, `Git/.gitconfig` | Taken from whichever upstream merges; the same bytes arrive either way. |
| in another upstream's rooms | `Unix/...` during a WinuX merge | Put back: one upstream never writes into another's rooms. |
| in the hallway (anything else) | `README.md`, `.github/PULL_REQUEST_TEMPLATE.md`, `.gitignore` | Decided by the root owner: taken when the merged upstream owns the root, put back otherwise. |

"Put back" deletes nothing, in the upstream or in the fork: it declines to copy the upstream's version
over yours and lists every declined path. Any declined file is one command away:
`git show winux/master:README.md`. A new hallway file an upstream adds is declined and listed, and you
decide - a `take` line adopts it. A `mirror` file whose merged copy would differ from the upstream's is
flagged by `-DryRun` (the contract is broken somewhere; take it from the upstream that is right).

WinuX's rooms are `Windows/`, `docs/winux/`, its workflows (`winux.yml`, `winux-release.yml`, `lint.yml`,
`release.yml`), its AI context and instructions (`REPOSITORY_CONTEXT.md`, `WINDOWS_CONTEXT.md`,
`ConfigurationPatterns.md`, `ContextBudgeting.md`, `PowerShellConventions.md`), `AI/Skills/winux/`,
`FastFetch/Windows/`, `JetBrainsMonoNerdFont/` and `PSScriptAnalyzerSettings.psd1`. Its project documents
live in its rooms too: `Windows/CHANGELOG.md`, `Windows/CONTRIBUTING.md`, `Windows/VERSIONING.md`,
`Windows/SECURITY.md`, `Windows/AGENTS.md`, `Windows/CONTEXT.md`, `Windows/NOTICE` and
`Windows/THIRD-PARTY-LICENSES.md`. The same eight files at the repository root are generic pointers,
byte-identical in every upstream and never edited, so they never conflict.

### Who owns the root

| Upstreams | Default `root-owner` | Why |
| --------- | -------------------- | --- |
| one (a plain fork of WinuX) | that upstream | The fork keeps receiving the README and templates it forked. |
| two or more (WinuX and Foundation) | `fork` | There is no right answer between two READMEs, so no upstream overwrites the hallway. |

A fork changes it, and adopts single hallway paths, in one optional file neither upstream ships,
`Git/upstreams.local.conf` (a hallway file itself, so always the fork's own):

```text
root-owner fork
take winux .github/ISSUE_TEMPLATE/
```

`root-owner` names an upstream or `fork`. Each `take UPSTREAM PATH` line adopts a hallway path from that
upstream as if it were in its rooms; a `PATH` ending in `/` is a folder.

### Fixed-path hallway files

Some files cannot move into a project's rooms, because a tool reads them at a fixed path. They stay in
the hallway and follow `root-owner`:

| File | Why it stays at that path |
| ---- | ------------------------- |
| `README.md` | GitHub shows the root README as the repository's landing page. |
| `AGENTS.md` | Codex and Gemini read it from the repository root. The root copy is a generic pointer that says to read every `*/AGENTS.md`. |
| `.github/ISSUE_TEMPLATE/*`, `.github/PULL_REQUEST_TEMPLATE.md`, `.github/FUNDING.yml` | GitHub reads them from `.github/`. |
| `.github/rulesets/*`, `.github/instructions/*` | GitHub and Copilot conventions read them from `.github/`. |
| `.gitattributes`, `.gitignore` | git reads the repository root's copies (a folder's own copy covers only that folder). |
| `.vscode/*` | VS Code reads the workspace root's settings. |
| `docs/index.html`, `docs/README.md`, `docs/_sidebar.md`, `docs/.nojekyll` | The docsify site root that GitHub Pages serves. `index.html` is a generic shell, byte-identical in every upstream; the landing and its sidebar list the projects. |

## Tags

Each upstream tags its releases with its own prefix in its own repository: `winux/v2.0.0`,
`foundation/v0.2.0`. A plain `git fetch` in any fork therefore brings every upstream's tags with no
clash, no `--no-tags` and no refspec, and `git tag -l 'winux/*'` lists WinuX's releases. A release is cut
by the changelog: when `## [x.y.z]` lands on `master` in `Windows/CHANGELOG.md`, the `winux-release.yml`
workflow creates the tag and the release (see [VERSIONING](https://github.com/IvanPavlak/WinuX/blob/master/Windows/VERSIONING.md)).

## Two worked configurations

**A plain fork of WinuX.** One remote, `winux`, and no `Git/upstreams.local.conf`. The only upstream owns
the root, so `Merge-Upstreams winux` takes everything WinuX changed, its README included, exactly like
`git merge winux/master` with the summary on top.

**A fork of WinuX and Foundation with a root of its own.** Two remotes, `winux` and `foundation`, and no
settings file: with two manifests the root owner defaults to `fork`. Merge one upstream per run, in
any order, committing in between - on Windows or on a Mac, either command merges either upstream:

```powershell
Merge-Upstreams winux
git commit -m "Merge winux master: 2.0.0"
Merge-Upstreams foundation
git commit -m "Merge foundation master: 0.2.0"
```

The fork writes its own `README.md` and its own docs landing (`docs/README.md`, `docs/_sidebar.md`, one
line per project: `winux/`, `foundation/`, and `custom/` for the Custom area); both upstreams' versions
are declined and listed on every merge. To keep receiving WinuX's issue templates, it adds
`take winux .github/ISSUE_TEMPLATE/` to `Git/upstreams.local.conf`.

## One-time steps for an existing clone

A clone set up before WinuX 2.0.0 runs these once, by hand (`Merge-Upstreams` prints the ones it needs
and never runs them):

```powershell
git remote rename upstream winux                    # the remote is found by URL anyway; this tidies the name
git config --unset remote.winux.tagOpt              # only if an earlier setup added it
git config --unset-all remote.winux.fetch '\+refs/tags/\*:refs/tags/winux/\*'
git fetch winux
```

A clone that merges a second upstream adds it the same way (`git remote add foundation
https://github.com/IvanPavlak/Foundation.git`). The first merge of an upstream whose history the
branch does not share needs a bridge, which `Merge-Upstreams` prints:
`git merge -s ours --allow-unrelated-histories -m "Bridge foundation as an upstream" foundation/master`.