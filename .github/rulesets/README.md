# Branch protection ruleset

`protect-master.json` documents the branch ruleset for `master` as code. It encodes:

- **Bypass:** the **Repository admin** role (`actor_id: 5`) bypasses the ruleset - so the
  maintainer keeps **direct push to `master`**, exactly as today.
- **For everyone else** (no bypass):
    - A pull request is required to merge.
    - The **`Pester Tests`** status check must pass and the branch must be up to date.
    - **Code Owners review** is required (see `../CODEOWNERS`) - the maintainer approves every
      external merge.
    - Conversations must be resolved.
    - Force-pushes and branch deletion are blocked; linear history is required.

## Applying it

In the GitHub UI: **Settings → Rules → Rulesets → New branch ruleset**, then mirror the
fields above. Or via the CLI:

```bash
gh api -X POST repos/IvanPavlak/WinuX/rulesets --input .github/rulesets/protect-master.json
```

> Verify `bypass_actors[0].actor_id` resolves to the **Admin** repository role on your repo
> before relying on it (GitHub's built-in role IDs are stable, but confirm in the UI that
> "Repository admin" appears on the bypass list after import).
