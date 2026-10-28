# Resolve-RepositoryDefaultBranch

Resolves the name of a repository's default branch: the configured name when one is set, otherwise what the remote reports (`origin/HEAD`), otherwise nothing, so the default-branch step is skipped.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`RepositoryUpdate.DefaultBranch`](../../configuration-reference.md#repository-update) | string | empty string | One default branch name for every repository. Empty means each repository's own default, as its remote reports it. |

## Decisions

1. Do all your repositories share one default branch name?
    - Options: Leave it empty and every repository uses the default its remote reports (`refs/remotes/origin/HEAD`, which `git clone` writes), so `master`, `main` and `develop` repositories can sit side by side. Set a name such as `"master"` only when every configured repository uses it; a repository with no local branch of that name is then skipped.
    - Default: Empty - each repository's own default.
    - More detail: [`RepositoryUpdate`](../../configuration-reference.md#repository-update)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

`RepositoryUpdate` is a hashtable, so writing only `DefaultBranch` in your local file keeps every other key of the section as the base ships it.

## Steps Overview

1. Set `RepositoryUpdate.DefaultBranch`
2. Reload and confirm the merge landed

## Step 1: Set `RepositoryUpdate.DefaultBranch`

One default branch name for every repository, or empty for each repository's own.

```powershell
RepositoryUpdate = @{
    DefaultBranch = "master"
}
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.RepositoryUpdate.DefaultBranch
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.RepositoryUpdate.DefaultBranch

# The default branch every configured repository resolves to
Resolve-RepositoryTargets -All | ForEach-Object {
    [pscustomobject]@{ Name = $_.Name; DefaultBranch = Resolve-RepositoryDefaultBranch -LocalPath $_.LocalPath }
}
```

A repository that resolves to nothing has no `origin/HEAD`. `Update-Repository` records it on the next update that includes the default branch (`git remote set-head origin --auto`); to do it now, run that command inside the repository, or set `RepositoryUpdate.DefaultBranch`.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    RepositoryUpdate = @{
        DefaultBranch = "master"
    }
}
```

## Related

- [`Resolve-RepositoryDefaultBranch` in the Git module reference](../../../modules/git.md#resolve-repositorydefaultbranch) - parameters, usage and behaviour
- [Git configuration guides](README.md) - every guide for this module
- [`Update-RepositoryDefaultBranch`](Update-RepositoryDefaultBranch.md) - fast-forwards the branch this function names
- [`Update-Repositories`](Update-Repositories.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
