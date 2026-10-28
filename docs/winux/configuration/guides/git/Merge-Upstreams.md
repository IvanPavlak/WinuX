# Merge-Upstreams

Merges one upstream into the current branch, taking only what that upstream owns, and stops before the commit.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

What it reads is not `Configuration.psd1`: the upstreams' manifests (`Windows/PowerShell/Upstream.conf`, `Unix/config/upstream.conf`) and the fork's optional `Git/upstreams.local.conf` (`root-owner`, `take`), described on the [Fork Model](../../../contributing/fork-model.md) page.

## Usage

```powershell
Merge-Upstreams winux
Merge-Upstreams foundation -DryRun
```

## Related

- [`Merge-Upstreams` in the Git module reference](../../../modules/git.md#merge-upstreams) - parameters, usage and behaviour
- [Git configuration guides](README.md) - every guide for this module
