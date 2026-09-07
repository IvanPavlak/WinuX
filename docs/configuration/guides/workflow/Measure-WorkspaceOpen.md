# Measure-WorkspaceOpen

Opens one workspace many times under alternating configuration variants - tearing down, settling, opening and collecting the benchmark row every time - and compares the variants by median, so a layout flag is judged by a controlled experiment instead of by two opens and a feeling.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

`Measure-WorkspaceOpen` does not need anything configured for itself. It reads the keys below to build its variants and restores every one of them when it ends; the values it puts in effect during a run live only in the session's `$global:Configuration`, never in a file.

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`WorkspaceActions`](../../configuration-reference.md#workspace-actions) | hashtable of workspace name to action array | hashtable, 5 keys | The workspace to measure must have an entry; `Example`, which the base ships, is the default, so nothing needs defining first. A workspace ending in `Terminate-WindowsTerminalTabs -OnlyCurrent` / `-IncludeCurrent` is refused, because that action exits the calling shell; one whose `Open-Project` action has no project is refused unless the project is given on the command line. |
| [`FancyZonesApplyMethod`](../../configuration-reference.md#layout-numbers--zone-mappings) | `"File"` or `"Hotkeys"` | `"File"` | One of the three flags varied by default. The configured value is the `Baseline`; the one-factor-at-a-time set flips it. |
| [`WorkspaceLayoutPipelining`](../../configuration-reference.md#layout-numbers--zone-mappings) | bool | `$true` | Same. |
| [`WorkspaceLayoutPrepareEarly`](../../configuration-reference.md#layout-numbers--zone-mappings) | bool | `$true` | Same. |
| [`WorkspaceBenchmark`](../../configuration-reference.md#workspace-benchmark) | hashtable | `@{ Enabled = $false; Display = "Table"; Last = 10 }` | Forced to `Enabled = $true; Display = "None"; Source = "Measure-WorkspaceOpen <session>"` for the duration of the experiment so every open records a row, none prints a table, and the rows are tagged as the experiment's (`Get-WorkspaceBenchmark` leaves them out of the history unless asked); the original value is restored afterwards. |

## Decisions

1. Which workspace is opened?
    - Options: The shipped `Example` workspace, which every WinuX install has (its `WorkspaceActions` entry and layout files ship with the base), or any workspace of your own. A workspace whose `Open-Project` action has no project of its own shows a selection menu on every open, which would stall the experiment; give the project positionally, as for `Open-Workspace`: `Measure-WorkspaceOpen FuturamaSoft Asseto`. Anything further on the command line (`run`, for instance) is forwarded to `Open-Workspace` unchanged.
    - Default: `Example`. Use your own workspace once you know it well - a workspace you open every day is the one whose seconds matter.
2. Which question is the experiment answering?
    - Options: All three flags at once (one flipped per variant), one flag only (`-Setting FancyZonesApplyMethod`), every combination (`-FullFactorial`), or hand-picked configurations (`-Variant`).
    - Default: The three flags, one flipped at a time, against the current configuration.
3. How many opens can you spare?
    - Options: `-Runs` per variant, `-WarmUp` discarded opens first, and `-MaxMinutes` as a hard budget - once it is spent no further open starts and what ran is summarized. A WinuX open is 10 to 30 s plus the teardown, so the default 21 opens is roughly 10 minutes.
    - Default: 5 runs, 1 warm-up, no budget.
4. How should the machine be reset between opens?
    - Options: The default `Kill-All -Skip Docker`, or any script block through `-Teardown`.
    - Default: `Kill-All -Skip Docker`.

## Where to Put Values

Nothing on this page needs a value in `Configuration.local.psd1`. When the experiment has decided, put the winning flag values there - the base `Configuration.psd1` stays upstream's.

## Steps Overview

1. Check the plan with `-DryRun`
2. Run the experiment from a terminal you can leave alone
3. Read the summary, retries first
4. Come back to the table later

## Step 1: Check the plan with `-DryRun`

```powershell
Measure-WorkspaceOpen -DryRun
Measure-WorkspaceOpen WinuX -DryRun
Measure-WorkspaceOpen FuturamaSoft Asseto -DryRun
```

Prints the variants, their order and the total number of opens. Nothing is opened, torn down or changed. The first line is the shipped `Example` workspace; the other two are your own, the last one with the project its `Open-Project` action needs.

## Step 2: Run the experiment from a terminal you can leave alone

```powershell
Measure-WorkspaceOpen
Measure-WorkspaceOpen WinuX
Measure-WorkspaceOpen FuturamaSoft Asseto -MaxMinutes 20
```

Every open launches and lays out the whole workspace and every teardown closes it again, so do not type into the machine while it runs. Ctrl+C stops it; the configuration is restored either way. `-MaxMinutes` is the polite version of Ctrl+C: no further open starts once the budget is spent, and the opens that ran are summarized.

## Step 3: Read the summary, retries first

The table has one row per variant. Read `Clean`, `Retries` and `NotApplied` before any seconds column: a variant that wins `MedianTotal` by needing a retry every third run has not won. `CleanMedianTotal` is the median over the runs that ended `Applied` on the first attempt. `Effect` is the variant's clean median minus the baseline's in seconds (negative is faster), `Spread` is how far apart the variant's own clean runs were, and `Verdict` says `Noise` when the effect is smaller than that scatter - the closing line counts how many variants are within the noise of the baseline. The phase medians (`MedianFancyZones` for `FancyZonesApplyMethod`, `MedianWait` and `MedianPositionSnap` for `WorkspaceLayoutPipelining`, `MedianLayout` and `MedianTotal` for `WorkspaceLayoutPrepareEarly`) show whether a flag moved the phase it controls or only the noise.

## Step 4: Come back to the table later

```powershell
Get-WorkspaceOpenMeasurement -Formatted
Get-WorkspaceOpenMeasurement -ListSessions -Formatted
Get-WorkspaceOpenMeasurement -Session 20260907-135804 -Formatted
```

Every open was written to `WorkspaceOpenMeasurements.csv` (`Get-WorkspaceOpenMeasurementPath`), so the table can be rebuilt after the terminal is gone: the most recent session by default, any session by the id the run printed. The benchmark rows the opens appended to `WorkspaceBenchmark.csv` are tagged with the session, and `Get-WorkspaceBenchmark` leaves them out of the everyday history unless asked (`-IncludeMeasured`, or `-Source` for one session).

## Verification

Read-only checks. None of these change anything.

```powershell
Measure-WorkspaceOpen -DryRun
Get-WorkspaceOpenMeasurement -ListSessions -Formatted
Read-WorkspaceOpenMeasurement | Select-Object -Last 5
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
- [`Get-WorkspaceOpenMeasurement`](Get-WorkspaceOpenMeasurement.md) - the table again, any time after the run
- [Configuration reference](../../configuration-reference.md) - every key, section by section
