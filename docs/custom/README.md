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
- **Every page declares what its entries are** (see below). This area is sovereign, so it holds
  more than functions, and the heading shape alone cannot tell them apart.
- `List-Functions -ListDiscrepancies` parses the pages that declare themselves a function
  reference: an undocumented Custom function is reported as a discrepancy, exactly like an
  engine function.

## Declaring what a page documents

Put one marker at the top of every page in this folder. It is an HTML comment, so it renders as
nothing in docsify and on GitHub:

| Marker                                        | The page's `## [Name](url)` entries are                    |
| --------------------------------------------- | ---------------------------------------------------------- |
| `<!-- reference: functions windows/Custom -->` | functions exported by `Modules/Custom/Custom.psd1`          |
| `<!-- reference: skills -->`                   | Agent Skills (`AI/Skills/...`), not PowerShell functions    |
| `<!-- reference: guide -->`                    | prose - nothing here is checked against a manifest          |
| `<!-- reference: none -->`                     | the same, stated explicitly                                 |

A page with no marker **fails the Infrastructure function-reference test**, and so does a
malformed one - a misspelled kind, a `functions` marker with no `<engine>/<area>` namespace, or
any other kind carrying one. That is deliberate: silence used to be the state in which a page
claimed a contract by accident, so silence must now be the state that fails, and "this page
claims nothing" has to be written down rather than inferred from an absence.

Why declare it in the page rather than derive it from the folder layout? Because ownership then
travels with the file. A page keeps its terms when it graduates into WinuX, and an engine only
ever claims the namespaces it owns - so a fork tracking more than one upstream engine can take a
page from either without the two engines' rules colliding over this one directory. `README.md`
is the landing page, is never parsed for entries, and needs no marker.

## Entry template

Copy this skeleton into `custom/<module>.md` (create the file if it is the module family's
first custom function; keep entries alphabetical within the page):

```markdown
<!-- reference: functions windows/Custom -->

# <Module> (Custom Area)

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
