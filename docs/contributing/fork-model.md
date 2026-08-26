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
> have them overwritten by the next `git merge upstream/master`. Move them first - it is a one-time copy:
> take your added rows out of `WinGetApps.csv` into a new `WinGetApps.local.csv` (same header on line 1),
> write `-<id>` rows for any shipped app you had deleted, restore the committed file to upstream's version
> (`git checkout upstream/master -- Windows/PowerShell/Modules/Bootstrap/Data/`), and repeat for Scoop and
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

`merge=ours` means: when `git merge upstream/master` touches one of these files, Git keeps **your** copy
and ignores the incoming one. Your fork inherits this `.gitattributes` automatically (it is a normal
tracked file), so you never have to add it yourself.

**One-time setup per clone.** The `ours` driver must be _registered_ before Git will run it. The bootstrap
does this for you (`git config --global merge.ours.driver true`). If you set a clone up by hand, run that one
command yourself, once. Git will not auto-register a merge driver from a cloned repo - a deliberate
security boundary - so this can never be fully automatic; the bootstrap (or that one-liner) is as close as
it gets. Until it is registered, Git just does a normal merge for those files, so nothing breaks - you only
lose the "keep mine" behavior.

**Trade-off.** A `merge=ours` file never receives upstream changes; that is the intent for payloads that
are wholly yours. If WinuX later restructures one and you want the new shape, diff it against upstream and
port what you want by hand. That trade-off is exactly why the app lists moved off `merge=ours` and onto an
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
├── modules/application.md                # upstream reference - your fork never edits these
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
2. **Add the upstream remote** so you can pull project updates:

    ```powershell
    git remote add upstream https://github.com/IvanPavlak/WinuX.git
    ```

3. **Personalize** - run [`Initialize-Configuration`](../modules/bootstrap.md#initialize-configuration) (or the bootstrap
   one-liner), which writes your `Configuration.local.psd1`. It is gitignored by default, so it
   never travels to GitHub; if you run several machines, commit it in your fork instead - see
   "One machine vs. several" above.
4. **Add your apps** to `Windows/PowerShell/Modules/Bootstrap/Data/WinGetApps.local.csv` (and the Scoop /
   Chocolatey overlays if you use them), never to the committed CSVs - see
   [Keeping your own app lists](#keeping-your-own-app-lists-the-localcsv-overlay).
5. **Install** as usual - see [Installation](../getting-started/installation.md).

## Pulling upstream updates

```powershell
git fetch upstream
git merge upstream/master      # or: git rebase upstream/master
```

Because your personal settings live in the override (not the tracked base config), your apps live in the
`.local.csv` overlays (not the tracked lists), and your payload configs are protected by `merge=ours` (see
above - just make sure the driver is registered once), these updates apply cleanly: neither your
configuration nor your owned files are a source of conflicts. Custom-area code and docs live in fork-owned
paths upstream never touches, so they never conflict either. If you have edited _other_ tracked files
(engine, docs), resolve those as you normally would.

> [!NOTE]
> Keeping personal values out of tracked files is what makes this work. Avoid editing
> `Configuration.psd1` with machine-specific values or the `Data/*.csv` app lists with your own apps; put
> them in `Configuration.local.psd1` and the `*.local.csv` overlays instead.
