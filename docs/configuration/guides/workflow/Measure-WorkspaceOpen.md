# Measure-WorkspaceOpen

Opens one workspace many times under alternating configuration variants - tearing down, settling, opening and collecting the benchmark row every time - and compares the variants by median, so a layout flag is judged by a controlled experiment instead of by two opens and a feeling.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

`Measure-WorkspaceOpen` does not need anything configured for itself. It reads the keys below to build its variants and restores every one of them when it ends; the values it puts in effect during a run live only in the session's `$global:Configuration`, never in a file.

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`WorkspaceActions`](../../configuration-reference.md#workspace-actions) | hashtable of workspace name to action array | hashtable, 5 keys | The workspace to measure must have an entry. A workspace ending in `Terminate-WindowsTerminalTabs -OnlyCurrent` / `-IncludeCurrent` is refused, because that action exits the calling shell. |
| [`FancyZonesApplyMethod`](../../configuration-reference.md#layout-numbers--zone-mappings) | `"File"` or `"Hotkeys"` | `"File"` | One of the three flags varied by default. The configured value is the `Baseline`; the one-factor-at-a-time set flips it. |
| [`WorkspaceLayoutPipelining`](../../configuration-reference.md#layout-numbers--zone-mappings) | bool | `$true` | Same. |
| [`WorkspaceLayoutPrepareEarly`](../../configuration-reference.md#layout-numbers--zone-mappings) | bool | `$true` | Same. |
| [`WorkspaceBenchmark`](../../configuration-reference.md#workspace-benchmark) | hashtable | `@{ Enabled = $false; Display = "Table"; Last = 10 }` | Forced to `Enabled = $true; Display = "None"` for the duration of the experiment so every open records a row and none prints a table; the original value is restored afterwards. |

## Decisions

1. Which question is the experiment answering?
    - Options: All three flags at once (`Measure-WorkspaceOpen WinuX`, one flipped per variant), one flag only (`-Setting FancyZonesApplyMethod`), every combination (`-FullFactorial`), or hand-picked configurations (`-Variant`).
    - Default: The three flags, one flipped at a time, against the current configuration.
2. How many opens can you spare?
    - Options: `-Runs` per variant, `-WarmUp` discarded opens first. A WinuX open is 10 to 30 s plus the teardown, so the default 21 opens is roughly 10 minutes.
    - Default: 5 runs, 1 warm-up.
3. How should the machine be reset between opens?
    - Options: The default `Kill-All -Skip Docker`, or any script block through `-Teardown`.
    - Default: `Kill-All -Skip Docker`.

## Where to Put Values

Nothing on this page needs a value in `Configuration.local.psd1`. When the experiment has decided, put the winning flag values there - the base `Configuration.psd1` stays upstream's.

## Steps Overview

1. Check the plan with `-DryRun`
2. Run the experiment from a terminal you can leave alone
3. Read the summary, retries first

## Step 1: Check the plan with `-DryRun`

```powershell
Measure-WorkspaceOpen WinuX -DryRun
```

Prints the variants, their order and the total number of opens. Nothing is opened, torn down or changed.

## Step 2: Run the experiment from a terminal you can leave alone

```powershell
Measure-WorkspaceOpen WinuX
```

Every open launches and lays out the whole workspace and every teardown closes it again, so do not type into the machine while it runs. Ctrl+C stops it; the configuration is restored either way.

## Step 3: Read the summary, retries first

The table has one row per variant. Read `Clean`, `Retries` and `NotApplied` before any seconds column: a variant that wins `MedianTotal` by needing a retry every third run has not won. `CleanMedianTotal` is the median over the runs that ended `Applied` on the first attempt. The phase medians (`MedianFancyZones` for `FancyZonesApplyMethod`, `MedianWait` and `MedianPositionSnap` for `WorkspaceLayoutPipelining`, `MedianLayout` and `MedianTotal` for `WorkspaceLayoutPrepareEarly`) show whether a flag moved the phase it controls or only the noise.

## Verification

Read-only checks. None of these change anything.

```powershell
Measure-WorkspaceOpen WinuX -DryRun
Import-Csv (Join-Path (Split-Path (Get-WorkspaceBenchmarkPath)) 'WorkspaceOpenMeasurements.csv') | Select-Object -Last 5
```

## Complete Example

```powershell
# Only File against Hotkeys, 8 measured opens each, interleaved
Measure-WorkspaceOpen WinuX -Setting FancyZonesApplyMethod -Runs 8

# Then keep the winner
# Configuration.local.psd1
@{
    FancyZonesApplyMethod = "File"
}
```

## Related

- [`Measure-WorkspaceOpen` in the Workflow module reference](../../../modules/workflow.md#measure-workspaceopen) - parameters, usage and behaviour
- [Workflow configuration guides](README.md) - every guide for this module
- [`Open-Workspace`](Open-Workspace.md) - the flow being measured and the `WorkspaceBenchmark` opt-in
- [`Get-WorkspaceBenchmark`](Get-WorkspaceBenchmark.md) - the per-open history the experiment is built on
- [Configuration reference](../../configuration-reference.md) - every key, section by section
