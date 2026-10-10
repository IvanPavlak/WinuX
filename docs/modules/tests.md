# Tests Module

The Tests module provides **Pester test execution** for WinuX. It validates AI, Application, Bootstrap, Configuration, Git, Helper, Logging, System, Window, and Workflow module logic, plus repository-infrastructure checks.

> [!NOTE]
> The repository maintains broad module-wide test coverage with same-name test files for function behavior checks, including complete same-name coverage for the System module.

## [Run-Tests](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Tests/Functions/Run-Tests.ps1)

- **Description:** Discovers all `.Tests.ps1` Pester tests in the PowerShell Modules Tests directory (every module's test folder plus the Infrastructure checks), and by default also the fork-owned Custom area (`Modules/Custom/<Module>/Tests`), then hands them to [Invoke-TestSuite](#invoke-testsuite) to run in parallel worker processes. Supports filtering by test name pattern, worker count (learned per machine when not given), echoing the full run log, returning the aggregate result object, skipping the Integration tier (`-Quick`), running only what the changes since a base can affect (`-Changed`, `-Since`), and recording the runtime impact map that backs `-Changed` (`-BuildImpactMap`). A bare `Run-Tests` is always the full suite, the gate before merging.
- **Parameters:** -TestName, -Path, -Workers, -Detailed, -PassThru, -Quick, -Changed, -Since, -BuildImpactMap
- **Usage:** `Run-Tests`, `Run-Tests -TestName "Open-Terminal"`, `Run-Tests -TestName "Open-Terminal", "Close-Workspace"`, `Run-Tests -Changed`, `Run-Tests -Changed -Quick`, `Run-Tests -Quick`, `Run-Tests -BuildImpactMap`, `Run-Tests -Detailed`, `$results = Run-Tests -PassThru`

Recursively discovers `*.Tests.ps1` files under the Tests directory and, when present, the `Modules/Custom` fork area (or only under a custom `-Path` when one is given), and invokes the harness. The terminal shows a spinner with a live test counter and then the verdict; the counter's total is counted from the test files before the run starts, so it is right for the files about to run rather than carried over from the previous run, and the per-test detail goes to the run log. With `-PassThru`, the aggregate result object is returned for scripting (e.g. CI/CD).

| Parameter         | Description |
| ----------------- | ----------- |
| `-TestName`       | Filter to run only tests whose file name matches a pattern; several patterns run the union of their matches, each file once. |
| `-Path`           | Custom path to test files. Defaults to the Tests directory. |
| `-Workers`        | Number of parallel worker processes. An explicit value always wins and is never learned from. Omitted, the harness picks it: the fastest count measured on this machine by earlier green full runs (see [Worker count](#worker-count)), and for a scoped run never more workers than its files can keep busy. |
| `-Detailed`       | Echo the whole run log, including every worker transcript, after the run. |
| `-PassThru`       | Return the aggregate result object instead of just printing the summary. |
| `-Quick`          | Skip every test tagged `Integration` (real git, real processes); a file whose tests are all tagged is not run at all. See [The Integration tier](#the-integration-tier). |
| `-Changed`        | Run only the test files the changes since `-Since` can affect, conservatively, after printing each selected file and why. Combines with `-TestName` and `-Path` as a union. See [Running only what a change affects](#running-only-what-a-change-affects). |
| `-Since`          | The ref `-Changed` compares against (its merge base with `HEAD`). Defaults to `master`. |
| `-BuildImpactMap` | Run the full suite while recording which functions each test file invokes, into `Results/impact-map.json`. About twice as slow as a normal run; cannot be combined with a filter, `-Changed` or `-Quick`. |

```powershell
# Run all discovered tests
Run-Tests

# Run only tests matching a name pattern
Run-Tests -TestName "Open-Terminal"

# Run every file matching any of several patterns
Run-Tests -TestName "Open-Terminal", "Close-Workspace"

# Print the full run log to the console afterwards
Run-Tests -Detailed

# Run everything in a single worker (useful when diagnosing cross-test interference)
Run-Tests -Workers 1

# Everyday loop: only what the branch's changes can affect, and why each file was picked
Run-Tests -Changed

# Faster still: the same selection without the Integration tier, unless the change is its subject
Run-Tests -Changed -Quick

# Refresh the runtime impact map -Changed uses as its backstop (about twice a normal run)
Run-Tests -BuildImpactMap

# Capture the result object for CI/CD gating
$results = Run-Tests -PassThru
if ($results.FailedCount -gt 0) {
    exit 1
}
```

## Invoke-TestSuite

[Invoke-TestSuite.ps1](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Tests/Invoke-TestSuite.ps1) is the harness both `Run-Tests` and the `Tests` CI workflow run. It sits at the module root rather than in `Functions/` because it is a script, not an exported function.

Pester (6.x included) has no native parallelism, so the harness provides it. Discovered test files are bucketed by expected duration and handed to N child `pwsh -NoProfile` processes. Each worker bootstraps its own session - `PSModulePath`, `$global:Configuration`, the nine engine modules plus `Custom` - and runs `Invoke-Pester` over its own bucket.

The Pester version is pinned repo-wide in `Modules/Tests/RequiredPesterVersion.txt` - the single source of truth the worker bootstrap (`Import-Module -RequiredVersion`), `Install-PowerShellModules`, and the `Tests` CI workflow all read. A machine without exactly that version fails loudly at worker bootstrap (exit code `2`) instead of silently running the suite on a version it was not written for; run `Install-PowerShellModules` to install the pin side-by-side with whatever else is present (the in-box 3.4.0 included). To bump the version, edit the pin file, re-run `Install-PowerShellModules` on each machine, and fix any new breaking changes in the same PR - the CI cache key rolls over automatically.

Two consequences matter day to day:

- **The calling session is never touched.** Tests that clobber `$global:Configuration` or `Remove-Module Logging -Force` now do so inside a throwaway process, so no profile reload is needed after a run. (`Reload-PowerShellProfile` still exists; it is simply no longer part of running tests.)
- **CI and local runs are the same code path.** The workflow no longer carries its own inline bootstrap that could drift from the local one.

Buckets are balanced by longest-processing-time-first, weighted by each file's measured duration from the previous run (`Results/timings.json`). A file with no measurement yet is seeded from its statically counted tests times the median known milliseconds per test, and a never-measured file tagged `Integration` gets a fixed 60-second seed, so a new heavy file is never stacked on top of other heavy files on its first run; on a cold checkout with no timings at all, file size stands in. A `-Quick` run and a `-BuildImpactMap` run do not update `timings.json`, because they measure the files only partly or under breakpoints. Two files whose tests touch state shared across processes - `Set-WorkspaceWindowLayout.Tests.ps1` (real User-scope `WORKSPACE_*` variables) and `Reset-KeyboardModifiers.Tests.ps1` (real keystroke injection) - are pinned into the same bucket so they can never run concurrently with each other.

The real-git data-safety scenarios are split over seven `Update-Repository.DataSafety.*.Tests.ps1` files (`LocalWork`, `Overlap`, `Stash`, `Failure`, `InProgress`, `Integration`, `Startup`), none longer than a worker's share of a full run, so no single file is the critical path of the whole suite.

### Worker count

An explicit `-Workers` always wins and is never recorded. `-CI` uses the static `min(CPU count, 12)` and neither reads nor writes any history. Otherwise the count is learned per machine from earlier full runs, stored in `Results/workers.json` (the last 60 runs, keyed by a fingerprint of the processor count and the suite's file count rounded to 50 - a different CPU, or a suite that grew or shrank by 50 files, restarts learning):

- With no history: `min(CPU count, 12)`.
- Explore: each neighbour of the best count - `round(best * 1.25)` first, then `round(best * 0.75)`, both inside `[2, CPU count]` - is tried once; a neighbour whose one run beat the best is tried a second time.
- Settle: the best count is the one with the lowest median wall clock over its last five runs, among the counts with at least two runs, so one outlier cannot move it.
- Re-check: every 20th recorded run tries one neighbour again, alternating, so a best count that drifts is noticed.
- Only full, green, representative runs teach: never a scoped run (`-TestName`, `-Path`, `-Changed`, `-Quick`, `-BuildImpactMap`), a run with a failing test or an infrastructure failure, an explicit `-Workers`, a CI run, or a run during which processes outside the test run used more than 15% of the machine's CPU (see [Run conditions](#run-conditions)).
- A scoped run never explores. It uses the learned best, capped so that no worker gets less than about 4 seconds of work - its own start-up costs about that much - and never more workers than files. A scoped run of a handful of small files therefore runs on one worker.

The run log's `Workers` line says which phase chose the count and why, and the `Worker history` line whether the run was recorded.

### Run conditions

The same suite can take more than twice as long from one run to the next, and the cause is the machine, not the suite. Every local run therefore samples the machine in the background every two seconds and writes one `Machine` line into the run log: average and peak CPU use, the lowest `% Processor Performance` (below 100 means the CPU ran under its rated speed), the least free memory, the share of the machine's CPU used by processes outside the test run (the foreign load), and the five processes outside the run that used the most CPU. A `Start-up` line gives each worker's start-up time - spawn to first test file - as min/avg/max; it is also in the per-worker table. A slow run can be explained from its log alone. CI runs do not sample (a fresh runner says nothing about your machine) but still report start-up. A counter that cannot be opened, for example on a Windows installation with localized counter names, is left out without failing the run.

### The Integration tier

Test files whose value is real I/O - real git, real processes - carry `-Tag 'Integration'` on their top-level `Describe`: the seven `Update-Repository.DataSafety.*` files, `Restore-RepositoryStash.Tests.ps1`, and the harness tests that drive real git or real processes (`Get-ChangedPaths.Tests.ps1`, `Import-NativeAssembly.Tests.ps1`). A file that is slow only because it is large stays untagged. `Run-Tests -Quick` does not dispatch a file whose tests are all tagged and passes `ExcludeTag = 'Integration'` to every worker for the rest; the live counter's denominator leaves the excluded tests out ([Get-ExpectedTestCount.ps1](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Tests/Get-ExpectedTestCount.ps1) reads literal `-Tag` values off the syntax tree). `-Quick` is a convenience, never the gate: a bare `Run-Tests` and `-CI` always run everything.

### Running only what a change affects

`Run-Tests -Changed` compares the working tree with the merge base of `HEAD` and `-Since` (default `master`), so it covers the branch's commits, staged and unstaged edits and untracked files ([Get-ChangedPaths.ps1](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Tests/Get-ChangedPaths.ps1)), and selects the union of ([Get-TestImpact.ps1](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Tests/Get-TestImpact.ps1)):

1. Changed test files.
2. Every test file that uses a changed fixture (any non-test file under a test folder, such as `Support/*.ps1` or `RepositoryDataSafetyFixtures.ps1`), transitively; a fixture no test references runs everything.
3. For each changed function file: its own tests (`<Name>*.Tests.ps1`), every test file that references it, and the same for every transitive caller - a function file that references the name. References are read off each file's tokens, comments excluded and string contents included, so a function called through a name written as a string (`& 'Open-Workspace'`, a workspace action) counts; a folder in a path (`...\Bootstrap\Functions\X.ps1`) does not. The parsed references are cached in `Results/dependency-map.json`, keyed by file hash.
4. Every test file the runtime impact map (`Results/impact-map.json`, built by `Run-Tests -BuildImpactMap`) says executed a changed function. A map built for another Pester version, or more than 50 commits ago, is ignored and the selection says so.
5. The Infrastructure tests, for any documentation change (`*.md`), a module manifest (which also selects that module's tests), or a function file that was added or removed.
6. The full suite for what analysis cannot see the consumers of: `Configuration.psd1` and `Configuration.local.psd1`, the profile, the harness and its helper scripts, `RequiredPesterVersion.txt`, any `*.psm1` loader, the Logging module (every test mocks it), `*.cs` sources, module `Data/` files, any other file in a module folder, anything under `AI/`, and **any changed path no rule recognizes**.

The selection is printed before anything runs - each file and why it was picked (`changed`, `tests X`, `references X`, `caller of X (via Y)`, `uses the fixture X`, `executed X at runtime`, `documentation changed`, or the full-suite reasons) - and repeated in full in the run log. An Integration file selected because its own subject changed runs whole even under `-Quick`.

`-Changed` is a convenience, never the gate. Every green full run stamps `Results/last-green.json` with a fingerprint of the tree it tested (HEAD plus every uncommitted change), and a `-Changed` or `-Quick` run ends with a reminder when the current tree has no green full run yet. Two audits measure how often the selector misses:

- **Locally**, each `-Changed` run records its selection in `Results/last-selection.json`; when a later full run fails in a file that selection did not include, the run log and the verdict report a selector miss.
- **In CI**, the `Tests` workflow passes `-Since` with the pull request's base (or the pushed range): the full suite still runs, and the harness also computes what `-Changed` would have selected, writes a `Selector` line into the run log, and reports every failing file outside that selection as a selector miss with a GitHub warning annotation on the file.

A miss means a rule in `Get-TestImpact` should be fixed; see [A Change Was Not Caught By Run-Tests -Changed](../reference/troubleshooting.md#a-change-was-not-caught-by-run-tests--changed).

### Worker start-up

A worker is a `pwsh -NoProfile` that imports the ten engine modules and Pester, so start-up is a fixed cost every worker pays and it grows with contention. Two things keep it down: the Window module loads `WindowNative.cs` as a cached, precompiled assembly instead of compiling it in every process (see the [Window module](window.md#native-assembly-cache)), and Window test files reset the module's state with the `Tests/Modules/Support/Reset-WindowModuleState.ps1` helper instead of re-importing the whole module.

Setting `WINUX_TEST_TEMP` to a folder points the workers' `TEMP`/`TMP` - and so Pester's `TestDrive`, where the real-git tests write thousands of small files - there; for example a Dev Drive, whose Defender performance mode defers scanning exactly this workload. Unset (the default), nothing changes. Creating such a volume, or any Defender setting, is your decision; the harness never does it. The run log's `Mode` line shows the temp root in use.

The live counter's denominator is the total for the files about to run, not the previous run's. Pester 6 discovers and runs each file interleaved, so no worker knows its own total before it is done, and a discovery-only pass costs about a quarter of the whole suite; instead [Get-ExpectedTestCount.ps1](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Tests/Get-ExpectedTestCount.ps1), beside the harness, reads the count off each file's syntax tree while the workers bootstrap - one per `It`, multiplied by the element count of any literal `-ForEach`/`-TestCases` on the `It` and on every enclosing `Describe`/`Context`. That is exact for every test whose case list is written into the file. A file whose case list is computed at discovery time - the Infrastructure files that enumerate modules and documentation pages - or that generates `It` blocks from a loop or a helper function cannot be counted that way and takes the previous run's count for that file from `timings.json`; the counter never shows more tests run than expected.

### Run artifacts

Everything a detailed serial run would have printed - every per-test line, and everything the code under test writes to the console - is captured per worker and merged into a single run log. `Results/` is gitignored, exactly like the Logging module's `Logs/`:

| File                                  | Contents                                                                                |
| ------------------------------------- | --------------------------------------------------------------------------------------- |
| `TestRun_<run>.log`                   | Summary (with the `Workers`, `Machine`, `Start-up` and `Worker history` lines), per-worker breakdown, selector misses, the `-Changed` selection, failures, slowest 20 files, then every worker transcript. |
| `pester-results-<run>-worker<N>.xml`  | One NUnit3 XML per worker. CI merges the glob into a single check run.                   |
| `timings.json`                        | Measured per-file duration and test count: bucketing for the next run, and the counter's fallback for a file whose count cannot be read off its source. |
| `workers.json`                        | The worker-count history the learner reads (see [Worker count](#worker-count)). |
| `dependency-map.json`                 | The cached static references `-Changed` reads, keyed by file hash. |
| `impact-map.json`                     | The runtime impact map `Run-Tests -BuildImpactMap` writes: per test file, the function files it invoked, with the commit and Pester version it was built at. |
| `last-selection.json`                 | What the last `-Changed` run selected, for the local selector audit. |
| `last-green.json`                     | The gate stamp: the tree fingerprint, HEAD and Pester version of the last green full run. |

Every one of these is optional: a missing or corrupt file only means nothing is known yet, and never fails a run.

`<run>` is `<timestamp>_<PID>`, the same shape the Logging module uses for its session logs. Naming every artifact after its run is what makes concurrent runs safe - a scoped `Run-Tests` in one terminal while a full sweep finishes in another used to have the second run wipe the first's in-flight files and then report results it never produced.

The ten most recent run logs are kept, the same way `Clear-OldLogs` keeps session logs; each run's XMLs are pruned with its log. Retention is enforced twice: at the start of every run by the harness itself, and once a day by the Logging module's idle-time `Invoke-LogMaintenance` sweep - so `Results/` stays bounded even on machines that stopped running the suite.

### Exit codes

`Run-Tests` reports the verdict itself; these matter when calling the harness directly (CI does):

| Code | Meaning                                                                                                                                                             |
| ---- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `0`  | Every test passed.                                                                                                                                                  |
| `1`  | Test failures.                                                                                                                                                      |
| `2`  | Infrastructure failure: a worker failed to bootstrap, Pester is missing, a worker died without writing its summary, a bucket ran fewer files than assigned, or `-CI` matched no test files. |

Code `2` exists so that a file which never ran cannot green the gate.

**See also:** [Configuration: Overview](../configuration/overview.md), [Getting Started: First Run](../getting-started/first-run.md)

## Test File Structure

Tests are organized by module under `Modules/Tests/`:

```
Modules/Tests/
├── Tests.psd1              # Module manifest
├── Tests.psm1              # Module loader
├── Invoke-TestSuite.ps1    # Parallel harness (script, not an exported function)
├── Get-*.ps1, Read-*.ps1,  # The harness's helpers, dot-sourced by it (plain scripts, because CI
│   Write-*.ps1, ...        #   runs the harness with no WinuX module loaded): test counting,
│                           #   weights, worker learner, run-condition sampler, -Changed selector
├── Results/                # Generated run artifacts (gitignored)
├── Functions/
│   └── Run-Tests.ps1       # Test runner function
└── Modules/
    ├── Application/         # Application module tests
    ├── Bootstrap/           # Bootstrap module tests
    ├── Configuration/       # Configuration module tests
    ├── Git/                 # Git module tests
    ├── Helper/              # Helper module tests
    ├── Infrastructure/      # Repository-wide coherence checks (Infrastructure-*.Tests.ps1:
    │                        #   docs links, manifest completeness, function reference pages,
    │                        #   configuration guides) - run all with -TestName "Infrastructure"
    ├── Logging/             # Logging module tests
    ├── System/              # System module tests
    ├── Window/              # Window module tests
    └── Workflow/            # Workflow module tests
```

Tests are grouped by the module they validate, not by the Tests module itself.

## Writing Tests

### Pester Test Pattern

Tests use the [Pester](https://pester.dev/) framework, pinned repo-wide via `Modules/Tests/RequiredPesterVersion.txt`:

```powershell
# MyFunction.Tests.ps1
Describe "MyFunction" {
    Context "When called with valid input" {
        It "Should return expected result" {
            $result = MyFunction -Input "test"
            $result | Should -Be "expected"
        }

        It "Should not throw" {
            { MyFunction -Input "test" } | Should -Not -Throw
        }
    }

    Context "When called with invalid input" {
        It "Should throw an error" {
            { MyFunction -Input $null } | Should -Throw
        }
    }
}
```

### What's Currently Tested

| Area          | Coverage Summary                                                                        |
| ------------- | --------------------------------------------------------------------------------------- |
| Application   | Launcher wrappers, browser/project open detection, installer workflows                  |
| Bootstrap     | Machine detection and configuration loading paths                                       |
| Configuration | Config schema checks and formatting helpers                                             |
| Git           | Branch/status/diff/pull flows and repository initialization/update automation           |
| Helper        | Path expansion, selection logic, retry behavior, and utility helpers                    |
| System        | Environment/theme/taskbar/WSL/process-management behavior (complete same-name coverage) |
| Window        | Layout resolution, FancyZones orchestration, cache/state helpers, positioning           |
| Workflow      | Workspace/project open/close orchestration and terminal/browser automation              |

## Debugging Tips

While not part of the Tests module, these are useful for debugging WinuX:

- **`Get-ActiveWindowInfo -Continuous`** - Monitor window process names and titles in real-time (Window module)
- **`Set-LogLevel Verbose { Set-WorkspaceWindowLayout }`** - Verbose output for layout application
- **`-Verbose`** flag on any function - PowerShell's built-in verbose logging

## Running Tests

### Quick Test

```powershell
# Run all tests
Run-Tests

# Run specific test
Run-Tests Validate-Layout
```

### Detailed Output

The terminal only ever shows a spinner, a live test counter and the verdict. To see the detail, either read the run log the verdict points at, or have it echoed:

```powershell
Run-Tests -Detailed
```

### Diagnosing a Failure

The run log holds the full per-test output for every worker, so a failure rarely needs a second run. When a test only fails as part of the suite, collapse the parallelism to rule out cross-test interference:

```powershell
Run-Tests -Workers 1
```

### CI/CD Integration

```powershell
$results = Run-Tests -PassThru
if ($results.FailedCount -gt 0) {
    exit 1
}
```

The `-PassThru` object carries `Result`, `TotalCount`, `PassedCount`, `FailedCount`, `SkippedCount`, `NotRunCount`, `Duration`, `Workers`, `Containers`, `Failures`, `ResultFiles`, `RunLog` and `ExitCode`. The `Tests` workflow does not use it - it calls the harness directly and gates on the exit code.
