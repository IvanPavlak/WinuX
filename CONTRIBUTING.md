# Contributing to WinuX

Thank you for contributing! WinuX is an early-stage, deeply configurable Windows 11
distribution that turns a fresh install into a fully configured environment from a single
command. Contributions of all kinds are welcome - code, documentation, tests, bug reports,
and ideas. By participating you agree to our [Code of Conduct](CODE_OF_CONDUCT.md).

> **Security:** WinuX runs as **Administrator** and is installed via `irm | iex`. If you
> believe you have found a security vulnerability, do **not** open a public issue - follow
> [SECURITY.md](SECURITY.md) instead.

---

## Core principle - configure everything via `Configuration.psd1`

This is the single most important rule in the project:

> **Configure everything through `Configuration.psd1`. Never hardcode machine-specific
> values inside functions.**

`Configuration.psd1` is the single source of truth for the whole system - software lists,
dotfile symlinks, repositories, browser groups, workspaces, window layouts, theming, and
per-machine paths all live there. Functions read from it; they must not embed paths,
hostnames, usernames, or emails.

- **Use placeholders for every path**, never literal paths. `{Dev}`, `{User}`,
  `{MachineType}`, `{RepoRoot}`, and `{AppData}` are expanded at runtime.
    - ✅ `"{User}\Documents\Obsidian"`
    - ❌ `"C:\Users\You\Documents\Obsidian"`
- **New behavior a user might want to toggle, name, or relocate belongs in
  `Configuration.psd1`**, exposed as a hashtable entry - not as a constant baked into a
  function.

A PR that hardcodes a path, hostname, username, or email in a function will be asked to move
that value into `Configuration.psd1`. (Your own Git identity is collected at first run and
written to your local config - it is never committed.)

---

## Contribution quality bar (please read)

WinuX favors **few, well-considered, tested changes** over volume. To keep quality high:

- **Open an issue or [Discussion](../../discussions) first** for anything non-trivial, so the
  approach can be agreed before you write code.
- **Keep changes minimal and focused** - one logical change per PR. Reuse existing helpers
  (DRY); do not duplicate logic that already exists.
- **Tests are required** for behavior changes (see below); the `Pester Tests` check must be
  green before a PR can merge.
- **Documentation and manifests must stay complete** (see "Documentation is part of the
  change").
- **Explain your reasoning** in the PR description.

> Pull requests that are unexplained, untested, or appear to be raw AI output submitted
> without a sensible, reviewed approach will be closed. This is not about discouraging AI
> tools - use them - it is about every change being understood, minimal, and tested by a
> human who stands behind it.

---

## Development environment setup

WinuX targets **Windows 11** and **PowerShell 7+**.

| Requirement   | Notes                                                                                   |
| ------------- | --------------------------------------------------------------------------------------- |
| Windows 11    | Primary supported OS.                                                                   |
| PowerShell 7+ | `winget install Microsoft.PowerShell`. PowerShell 5.1 is only used to bootstrap into 7. |
| Git           | `winget install Git.Git`.                                                               |
| Pester 5+     | Test framework. `Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser`.         |
| Administrator | Needed to exercise symlink/bootstrap code paths (not needed just to run tests).         |

1. **Fork** the repository on GitHub, then **clone your fork**:
    ```powershell
    git clone https://github.com/<your-username>/WinuX.git
    cd WinuX
    ```
2. **Add the upstream remote** to keep your fork in sync:
    ```powershell
    git remote add upstream https://github.com/IvanPavlak/WinuX.git
    git fetch upstream
    ```

> ⚠️ **Do not run the full installer against your daily-driver machine while developing.**
> The bootstrap one-liner (`irm | iex`) is destructive: it installs software, creates
> symlinks, and reconfigures the OS. Test risky changes in a VM or a disposable `Test`
> machine type.

---

## Running the tests

Tests use [Pester](https://pester.dev/) and live under
`Windows/PowerShell/Modules/Tests/Modules/<Module>/`. Run them with the project's single
test command:

```powershell
Run-Tests                                  # whole suite
Run-Tests -TestName "Resize-Windows"       # scoped (matches *<pattern>*.Tests.ps1)
Run-Tests -TestName "Resize-Windows" -Detailed   # per-test diagnostics
```

**All tests must pass before you open a PR.** If you changed several areas, run `Run-Tests`
once per changed area and confirm each is green.

### How to add tests

Every new exported function should ship with tests.

1. Create `Windows/PowerShell/Modules/Tests/Modules/<Module>/<FunctionName>.Tests.ps1`.
2. Follow the existing Pester 5 structure used by neighbouring test files.
3. **Test behavior, side effects, branching, and edge cases** - not output/log strings.
4. Mock external/destructive calls (filesystem writes, `winget`, symlink creation, network)
   so tests are hermetic and safe to run repeatedly.

---

## Coding conventions

- **Naming:** functions use `Verb-Noun`.
- **Comment-based help:** every exported function includes `.SYNOPSIS`, `.DESCRIPTION`,
  `.PARAMETER`, and at least one `.EXAMPLE`.
- **No nested functions.** Extract helpers into their own top-level `.ps1` file in the owning
  module's `Functions/` directory; keep caller functions thin.
- **Module layout:** each module is a `.psd1` manifest + `.psm1` loader + `Functions/`
  directory. When you add, rename, or remove an exported function, update that module's
  `FunctionsToExport` accordingly. Fork-only functions are the exception - they live in the
  Custom area (see "Develop in your fork's Custom area first" below); their names go in the
  fork-owned `Custom.psd1` manifest rather than an engine module's.

---

## Documentation is part of the change

The docsify docs under `docs/` are the **single source of truth**. Any change that adds,
renames, removes, or alters the **behavior, parameters, or signature** of an exported
function MUST update the docs in the same PR:

- `docs/modules/<Module>.md` - one man-style entry per function.
- The module `.psd1` `FunctionsToExport`.
- `docs/docs_overview.md` (and `docs/_sidebar.md` only when adding/removing a page).

Then run and confirm no drift:

```powershell
List-Functions -ListDiscrepancies   # must report none
```

Use **genericized placeholders** in docs (`MyProject`, `MyRepo`, `Machine`) - no real
personal identifiers. The root `README.md` is a minimal pointer; do **not** add per-function
content to it.

Preview the docs locally:

```powershell
npx docsify-cli serve docs
```

---

## Develop in your fork's Custom area first

Anything you build that WinuX does not (yet) ship should start in the **Custom area** of your
fork: `Windows/PowerShell/Modules/Custom/<Module>/Functions/` for code (adding its name to
`Custom.psd1`'s `FunctionsToExport`, which is what makes it autoload),
`Windows/PowerShell/Modules/Custom/<Module>/Tests/` for its Pester tests, and
`docs/custom/<module>.md` for its documentation (same man-style entry format as the module
pages). Upstream never writes those paths, so your work survives every
`git merge upstream/master` untouched - while still facing the same quality bar: `Run-Tests`
discovers Custom tests, and `List-Functions -ListDiscrepancies` checks Custom functions against
their `docs/custom/` entries.

When a function is stable, tested, and documented, **graduate it** with a focused PR: `git mv`
the function into `Modules/<Module>/Functions/`, move its tests and doc entry to their upstream
locations, add it to the module's `FunctionsToExport`, and promote any config keys it reads into
the base `Configuration.psd1` with generic values. The step-by-step checklist lives in
`Windows/PowerShell/Modules/Custom/README.md`; the concept is explained in the
[Fork Model](docs/contributing/fork-model.md).

---

## Commit messages

Match the existing history:

- **Imperative mood, sentence case**, e.g. `Add Center-Terminal and use it in Kill-All`.
- **No trailing period**, **no** Conventional-Commits prefixes (`feat:`, `fix:`), **no**
  scope tags.
- One logical change per commit; keep the subject focused.

---

## Branch & pull-request workflow

1. **Sync** your fork with upstream `master`:
    ```powershell
    git checkout master
    git pull upstream master
    ```
2. **Branch** off `master`: `git checkout -b add-monitor-layout`.
3. **Make focused commits** following the message style above.
4. **Run the tests** (`Run-Tests`) and update docs + `FunctionsToExport` as required. Run
   `List-Functions -ListDiscrepancies` if you touched functions.
5. **Push** to your fork and **open a PR** against `IvanPavlak/WinuX:master`. The PR template
   loads automatically - please fill it in completely.
6. **Reference issues** the PR closes (e.g. `Closes #123`). For bugs and features, please
   file an issue first using the [issue forms](.github/ISSUE_TEMPLATE/).

### Review & merge

> **The maintainer reviews and authorizes every contributor merge.** All pull requests are
> reviewed by [@IvanPavlak](https://github.com/IvanPavlak); merges to `master` require a
> green `Pester Tests` check and maintainer review. Please be patient - this is a personal
> project maintained in spare time. Expect review comments and iteration.

---

## Recognition

Code **and** non-code contributions (docs, ideas, bug reports, testing) all count and are
genuinely appreciated. Financial supporters are credited in the README "Supporters" section.
Thank you for helping make WinuX better. 🙏
