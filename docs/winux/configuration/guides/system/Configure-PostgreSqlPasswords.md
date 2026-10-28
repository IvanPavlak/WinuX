# Configure-PostgreSqlPasswords

Changes the `postgres` user password across every installed PostgreSQL version found on the machine.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).
>
> The two passwords are read from the file as plain strings and passed to `psql` as they are - nothing resolves environment variables or credential stores. `Configuration.local.psd1` is gitignored, so they never reach the repository, but use this only for local development databases, never for a real or production password. The passwords also appear in the manual-instructions file written to the Desktop when an installation fails.

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`PostgreSqlPasswords`](../../configuration-reference.md#more-sections-quick-reference) | hashtable `@{ DefaultOrCurrent; New }` | `@{}` (empty) | The current password `Configure-PostgreSqlPasswords` authenticates with (`DefaultOrCurrent`) and the one it sets on the `postgres` user (`New`), used with `-Auto` or when the function is called without passwords. Ships empty, so the function warns and does nothing. |

## Decisions

1. Should `Configure-PostgreSqlPasswords` be able to run without passwords on the command line?
    - Options: Set `DefaultOrCurrent` (the password the installer set, often `postgres`) and `New` (the local development password to switch to). Leave the key empty and pass `-DefaultOrCurrentPassword` / `-NewPassword` on each call instead.
    - Default: Empty - a call without passwords reports that nothing is configured and returns.
    - More detail: [`PostgreSqlPasswords`](../../configuration-reference.md#more-sections-quick-reference)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `PostgreSqlPasswords`
2. Reload and confirm the merge landed

## Step 1: Set `PostgreSqlPasswords`

The current and the new password of the `postgres` user. Both keys are required; with either missing the function reports that both passwords are needed and returns.

```powershell
PostgreSqlPasswords = @{
    DefaultOrCurrent = "postgres"
    New              = "MyLocalDevPassword"
}
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.PostgreSqlPasswords
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.PostgreSqlPasswords
$global:Configuration.PostgreSqlPasswords.Keys
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    PostgreSqlPasswords = @{
        DefaultOrCurrent = "postgres"
        New              = "MyLocalDevPassword"
    }
}
```

## Related

- [`Configure-PostgreSqlPasswords` in the System module reference](../../../modules/system.md#configure-postgresqlpasswords) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
- [Add Symbolic Link](add-symbolic-link.md) - link shapes, placeholders and the WSL cases
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
