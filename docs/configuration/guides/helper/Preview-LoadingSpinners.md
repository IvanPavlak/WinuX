# Preview-LoadingSpinners

Displays every loading spinner style defined in `Configuration.LoadingSpinners`, animating them all simultaneously for 10 seconds so you can pick a preferred loading animation.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`LoadingSpinners`](../../configuration-reference.md#loading-spinners) | hashtable of spinner name to `@{ Frames; Interval }` | hashtable, 19 keys | The spinner animations `Loading-Spinner` can draw. `Preview-LoadingSpinners` renders every one of them. |

## Decisions

1. Do you want to add your own spinner?
    - Options: Name to `@{ Frames = @(...); Interval = <ms> }`. Supplying the key replaces all 19 shipped spinners, so copy the base map first if you only want to add one.
    - Default: The shipped 19.
    - More detail: [`LoadingSpinners`](../../configuration-reference.md#loading-spinners)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `LoadingSpinners`
2. Reload and confirm the merge landed

## Step 1: Set `LoadingSpinners`

The spinner animations `Loading-Spinner` can draw. `Preview-LoadingSpinners` renders every one of them.

```powershell
LoadingSpinners = @{
    Dots  = @{ Frames = @(".  ", ".. ", "..."); Interval = 200 }
    MyOwn = @{ Frames = @("<", "^", ">", "v"); Interval = 120 }
}
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.LoadingSpinners
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.LoadingSpinners
Preview-LoadingSpinners
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    LoadingSpinners = @{
        Dots  = @{ Frames = @(".  ", ".. ", "..."); Interval = 200 }
        MyOwn = @{ Frames = @("<", "^", ">", "v"); Interval = 120 }
    }
}
```

## Related

- [`Preview-LoadingSpinners` in the Helper module reference](../../../modules/helper.md#preview-loadingspinners) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module
- [`Loading-Spinner`](Loading-Spinner.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
