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

## Keeping your own app lists and payloads (the `merge=ours` protection)

`Configuration.local.psd1` covers your **settings**. A few other tracked files are also yours but have no
"base + override" split - your curated package lists and your payload configs. WinuX ships example/blank
versions; your fork edits them in place. So that an upstream pull never overwrites your versions, WinuX's
`.gitattributes` marks them with the **`ours` merge driver**:

```
Windows/PowerShell/Modules/Bootstrap/Data/WinGetApps.csv       merge=ours
Windows/PowerShell/Modules/Bootstrap/Data/ScoopApps.csv        merge=ours
Windows/PowerShell/Modules/Bootstrap/Data/ChocolateyApps.csv   merge=ours
Git/.gitconfig                                                 merge=ours
NuGet/nuget.config                                             merge=ours
Firefox/user.js                                                merge=ours
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

**Trade-off.** A `merge=ours` file never receives upstream changes; that is the intent for lists and
payloads that are wholly yours. If WinuX later restructures one and you want the new shape, diff it against
upstream and port what you want by hand.

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
4. **Install** as usual - see [Installation](../getting-started/installation.md).

## Pulling upstream updates

```powershell
git fetch upstream
git merge upstream/master      # or: git rebase upstream/master
```

Because your personal settings live in the override (not the tracked base config), and your app lists +
payload configs are protected by `merge=ours` (see above - just make sure the driver is registered once),
these updates apply cleanly: neither your configuration nor your owned files are a source of conflicts. If
you have edited _other_ tracked files (engine, docs), resolve those as you normally would.

> [!NOTE]
> Keeping personal values out of tracked files is what makes this work. Avoid editing
> `Configuration.psd1` with machine-specific values; put them in `Configuration.local.psd1` instead.
