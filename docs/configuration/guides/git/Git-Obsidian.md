# Git-Obsidian

Commits and pushes all pending changes in the Obsidian vault repository, providing a quick vault backup to GitHub without opening Obsidian.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Git-Obsidian
```

## When A Push Fails

The function commits first and pushes second, so a push that fails (no network, remote unreachable) leaves the vault committed locally with a clean working tree. It reports that as an error, never as `Obsidian updated!`, and the next `Git-Obsidian` finds the commit the remote is missing and pushes it:

```text
[Git-Obsidian]

Found [1] unpushed commit(s) from an earlier run. Pushing...

=> Obsidian updated!
```

`No changes to update!` is reported only when the working tree is clean **and** the branch has nothing its upstream lacks.

## Related

- [`Git-Obsidian` in the Git module reference](../../../modules/git.md#git-obsidian) - parameters, usage and behaviour
- [Git configuration guides](README.md) - every guide for this module
