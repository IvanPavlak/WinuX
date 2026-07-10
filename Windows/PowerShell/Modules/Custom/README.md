# The Custom Area

This directory is the **fork-owned** half of the module tree. Everything you build that is not
(yet) part of WinuX lives here, laid out as a mirror of `Modules/`, so upstream pulls never
conflict with your work and graduating a function into WinuX is a mechanical move.

Upstream ships only `Custom.psd1`, `Custom.psm1`, and this README. Your fork creates the payload
directories; upstream never writes them.

## Layout

```
Modules/
├── Application/                     # engine module - upstream-owned, never edit in a fork
└── Custom/                          # fork area
    ├── Custom.psd1                  # aggregator manifest (upstream-owned; fork fills FunctionsToExport)
    ├── Custom.psm1                  # aggregator loader   (upstream-owned)
    ├── Application/                 # MIRROR PAYLOAD - extends the Application module family
    │   ├── Functions/
    │   │   └── Open-MyApp.ps1       # one function per file, filename = function name
    │   └── Tests/
    │       └── Open-MyApp.Tests.ps1 # picked up by Run-Tests automatically
    └── MyModule/                    # WHOLE fork-owned module - has its own manifest + loader
        ├── MyModule.psd1
        ├── MyModule.psm1
        └── Functions/
```

## How loading works

- **Mirror payloads** (`Custom/<Module>/Functions/*.ps1`) are dot-sourced and exported by the
  `Custom` module, which autoloads on first use like any module - so each payload function must
  also be listed in `Custom.psd1`'s `FunctionsToExport` (see Rules). They belong to the `Custom`
  module at runtime; the mirror directory name records which engine module they graduate into.
- **Whole modules** (`Custom/<MyModule>/` with a matching `.psd1` + `.psm1`) are ignored by the
  aggregator. `Load-PathConfiguration` registers `Modules\Custom` as an additional module root,
  so they autoload from their own explicit `FunctionsToExport` exactly like engine modules.
- **Engine wins on collision:** a payload file whose name matches an existing engine function
  file of its mirror module is skipped with a warning. The Custom area adds behavior; it never
  overrides it.

## Rules

- One function per file; the file name must equal the function name (`Verb-Noun`).
- Register the function in `Custom.psd1`'s `FunctionsToExport` (one line per function). This is
  what makes it autoload, exactly like an engine module's manifest; a file that is not listed is
  dot-sourced but never exported.
- No hardcoded personal values - config keys go in `Configuration.local.psd1`, exactly like the
  engine reads `Configuration.psd1` (see the Fork Model docs).
- Tests live in `Custom/<Module>/Tests/<FunctionName>.Tests.ps1` and run with `Run-Tests`.
- Document every function in `docs/custom/<module>.md`, using the same man-style entry format as
  `docs/modules/<module>.md`. `List-Functions -ListDiscrepancies` checks Custom functions too.

## Graduating into WinuX

When a function is stable, tested, and documented, promote it with a focused PR:

1. `git mv Windows/PowerShell/Modules/Custom/<Module>/Functions/<Fn>.ps1 Windows/PowerShell/Modules/<Module>/Functions/`
2. `git mv Windows/PowerShell/Modules/Custom/<Module>/Tests/<Fn>.Tests.ps1 Windows/PowerShell/Modules/Tests/Modules/<Module>/`
3. Move its export line: remove `'<Fn>'` from `Custom.psd1`'s `FunctionsToExport` and add it to the
   target module's `.psd1` `FunctionsToExport`.
4. Move its doc entry from `docs/custom/<module>.md` into `docs/modules/<module>.md`
   (alphabetically), switching the heading link to the WinuX source URL.
5. Promote any config keys it reads from `Configuration.local.psd1` into the base
   `Configuration.psd1` with generic placeholder values.
6. Run `Run-Tests` and `List-Functions -ListDiscrepancies`; both must be clean.

A whole module graduates the same way: `git mv Modules/Custom/<MyModule> Modules/<MyModule>`,
then move its tests and docs page (add the page to `docs/_sidebar.md` and `docs_overview.md`).
