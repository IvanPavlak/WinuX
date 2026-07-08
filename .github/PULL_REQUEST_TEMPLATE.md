<!--
Thanks for contributing to WinuX! Please read CONTRIBUTING.md first.
Non-trivial changes should start as an issue or Discussion so the approach can be agreed.
The maintainer reviews and authorizes all merges, so a complete PR speeds up review.
-->

## Description

<!-- What does this PR do, and why? Explain your reasoning. -->

## Related issue

<!-- Link the issue this PR addresses. Use "Closes #123" to auto-close it.
     Non-trivial changes should reference an agreed issue. -->

Closes #

## Type of change

- [ ] Bug fix (non-breaking change that fixes an issue)
- [ ] New feature / function (non-breaking change that adds functionality)
- [ ] Breaking change (existing behavior, parameters, or signature changes)
- [ ] Documentation only
- [ ] Tests only
- [ ] Refactor / chore (no behavior change)

## Quality bar

- [ ] The change is **minimal and focused** (one logical change; reuses existing helpers, no duplication / DRY).
- [ ] I **understand and have tested** this change myself (not unreviewed AI output).
- [ ] No machine-specific values (paths, hostnames, usernames, emails) are hardcoded in functions.
- [ ] Any new user-facing setting is driven by `Configuration.psd1` using placeholder paths (`{Dev}`, `{User}`, `{MachineType}`, `{RepoRoot}`, `{AppData}`).

## Tests

<!-- Paste the exact Run-Tests command(s) you ran and the result. -->

```powershell
Run-Tests -TestName "..."
```

- [ ] I added/updated tests under `Windows/PowerShell/Modules/Tests/Modules/<Module>/`.
- [ ] All relevant tests pass locally (`Run-Tests`) and the `Pester Tests` check is green.
- [ ] Tests cover behavior/side effects/branching, not just output text.
- [ ] N/A - no testable behavior changed (docs/chore only).

## Documentation & manifests

- [ ] I updated `docs/modules/<Module>.md` for any added/renamed/removed/changed function.
- [ ] I updated the module `.psd1` `FunctionsToExport`.
- [ ] I updated `docs/docs_overview.md` (and `docs/_sidebar.md` if a page was added/removed).
- [ ] `List-Functions -ListDiscrepancies` reports no discrepancies and manifest completeness holds.
- [ ] N/A - no exported function changed.

## Tested on

- Windows version: <!-- e.g. Windows 11 24H2 -->
- PowerShell version: <!-- $PSVersionTable.PSVersion -->
- Machine type(s): <!-- Test / Machine / custom -->

## Checklist

- [ ] My commit messages follow the project style (imperative, sentence case, no trailing period, no Conventional-Commits prefix).
- [ ] My branch is up to date with `master`.
- [ ] I read and agree to the [Code of Conduct](../CODE_OF_CONDUCT.md).
- [ ] This PR contains no secrets or personal data (tokens, real paths/hostnames/emails).

## Additional notes / screenshots

<!-- Before/after screenshots for theming or window-layout changes are very helpful. -->
