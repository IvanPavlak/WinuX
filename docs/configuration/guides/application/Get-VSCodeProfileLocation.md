# Get-VSCodeProfileLocation

Returns the folder of a VS Code profile - the user data folder for `Default`, `profiles\<location>` for any other - and with `-Register` registers a profile VS Code does not know yet.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`VSCodeProfiles.UserData`](../../configuration-reference.md#vs-code-profiles) | string | `{AppData}\Code\User` | The user data folder used when `-UserData` is not given. |

## Decisions

1. Is VS Code installed somewhere other than the standard user data folder?
    - Options: Point `UserData` at the portable or Insiders user data folder; leave it out for a standard install.
    - Default: `{AppData}\Code\User`.
    - More detail: [`VSCodeProfiles.UserData`](../../configuration-reference.md#vs-code-profiles)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `VSCodeProfiles.UserData` (only for a non-standard install)
2. Reload and read the location back

## Step 1: Set `VSCodeProfiles.UserData`

```powershell
VSCodeProfiles = @{
    UserData = "{User}\Tools\VSCode\data\user-data\User"
}
```

## Step 2: Reload and read the location back

```powershell
Reload-PowerShellProfile
Get-VSCodeProfileLocation Default
```

## Verification

Read-only checks. None of these change anything.

```powershell
Get-VSCodeProfileLocation Default
Get-VSCodeProfileLocation Writing
```

`-Register` is not read-only: it writes VS Code's profile list, and refuses while VS Code runs.

## Complete Example

```powershell
# Configuration.local.psd1
@{
    VSCodeProfiles = @{
        UserData = "{AppData}\Code\User"
    }
}
```

## Related

- [`Get-VSCodeProfileLocation` in the Application module reference](../../../modules/application.md#get-vscodeprofilelocation)
- [`Deploy-VSCodeProfiles`](Deploy-VSCodeProfiles.md) - registers profiles through this function
- [Application configuration guides](README.md)
- [WinuXConfigurator](../../winux-configurator.md)
