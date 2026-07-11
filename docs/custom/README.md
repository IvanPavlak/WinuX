# Custom Area Docs

This folder documents **fork-owned** functions - code that lives in your fork's
`Windows/PowerShell/Modules/Custom/` area and is not (yet) part of WinuX. Upstream ships only
this landing page; your fork owns its content (it is protected by `merge=ours`, so upstream
pulls never overwrite it).

## How it works

- One page per module family, mirror-named after the engine page: functions under
  `Modules/Custom/Application/Functions/` are documented in `custom/application.md`, next to
  the upstream `modules/application.md`.
- Entries use the exact same man-style format as the module pages, so graduating a function
  into WinuX is a cut-and-paste of its section (switch the heading link to the WinuX source
  URL).
- `List-Functions -ListDiscrepancies` parses these pages too: an undocumented Custom function
  is reported as a discrepancy, exactly like an engine function.

## Entry template

Copy this skeleton into `custom/<module>.md` (create the file if it is the module family's
first custom function; keep entries alphabetical within the page):

```markdown
## [FunctionName](https://github.com/<you>/<your-fork>/blob/master/Windows/PowerShell/Modules/Custom/<Module>/Functions/FunctionName.ps1)

- **Description:** What it does, when it does nothing, and where its configuration lives.
- **Parameters:** -ParamA, -ParamB (omit this bullet when there are none)
- **Usage:** `FunctionName`, `FunctionName -ParamA Value`

Optional extended prose, parameter table, and examples - same conventions as the module pages.
```

## Your custom pages

List your pages here so they are reachable from the docs site (this file is yours after
forking):

- (none yet)

## Graduating

When a function is stable, tested, and documented, promote it into WinuX with a focused PR -
the step-by-step checklist lives in
[`Windows/PowerShell/Modules/Custom/README.md`](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Custom/README.md).
