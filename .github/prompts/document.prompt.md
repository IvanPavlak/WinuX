---
description: "Generate or update Docsify documentation from PowerShell function comment-based help. Extracts .SYNOPSIS, .DESCRIPTION, .PARAMETER, .EXAMPLE and formats per documentation conventions."
argument-hint: "Function name or module path (e.g., 'Open-Browser' or 'Modules/Application')"
agent: "agent"
---

# Document Generation

Generate or update documentation from PowerShell code. Follow the conventions in [DocumentationStyle.md](../../AI/Instructions/DocumentationStyle.md).

## For a single function

1. Read the function source file and extract comment-based help (`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`)
2. Generate a documentation section matching the module page format:
    - H3 heading with function name
    - Brief description from `.SYNOPSIS`
    - Syntax block with parameter signatures
    - Parameters table: `Parameter | Type | Required | Description`
    - Examples from `.EXAMPLE` blocks
3. Show where to insert it in the existing module page (`docs/modules/<module>.md`)
4. Update `docs/docs_overview.md` function table if the function is new

## For an entire module

1. Read all function files in `Windows/PowerShell/Modules/<Module>/Functions/`
2. Read the module manifest `.psd1` for `FunctionsToExport`
3. Generate the complete module documentation page following the module page template
4. Update `docs_overview.md` with any new or changed functions
5. Update `_sidebar.md` if the module is new

## Quality checks

- Every exported function must appear in both the module page AND `docs_overview.md`
- Parameter types and descriptions must match the actual code
- Examples must be syntactically valid PowerShell
- Cross-references to related functions should use relative links
