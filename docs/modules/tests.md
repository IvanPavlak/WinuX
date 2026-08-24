# Tests Module

The Tests module provides **Pester test execution** for WinuX. It validates Application, Bootstrap, Configuration, Git, Helper, Logging, System, Window, and Workflow module logic, plus repository-infrastructure checks.

> [!NOTE]
> The repository maintains broad module-wide test coverage with same-name test files for function behavior checks, including complete same-name coverage for the System module.

## [Run-Tests](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Tests/Functions/Run-Tests.ps1)

- **Description:** Discovers all `.Tests.ps1` Pester tests in the PowerShell Modules Tests directory (every module's test folder plus the Infrastructure checks), and by default also the fork-owned Custom area (`Modules/Custom/<Module>/Tests`), then hands them to [Invoke-TestSuite](#invoke-testsuite) to run in parallel worker processes. Supports filtering by test name pattern, worker count, echoing the full run log, and returning the aggregate result object.
- **Parameters:** -TestName, -Path, -Workers, -Detailed, -PassThru
- **Usage:** `Run-Tests`, `Run-Tests -TestName "Open-Terminal"`, `Run-Tests -Detailed`, `$results = Run-Tests -PassThru`

Recursively discovers `*.Tests.ps1` files under the Tests directory and, when present, the `Modules/Custom` fork area (or only under a custom `-Path` when one is given), and invokes the harness. The terminal shows a spinner with a live test counter and then the verdict; the per-test detail goes to the run log. With `-PassThru`, the aggregate result object is returned for scripting (e.g. CI/CD).

| Parameter   | Description                                                                       |
| ----------- | --------------------------------------------------------------------------------- |
| `-TestName` | Filter to run only tests whose file name matches the given pattern.               |
| `-Path`     | Custom path to test files. Defaults to the Tests directory.                       |
| `-Workers`  | Number of parallel worker processes. Defaults to `min(CPU count, 8, file count)`. |
| `-Detailed` | Echo the whole run log, including every worker transcript, after the run.         |
| `-PassThru` | Return the aggregate result object instead of just printing the summary.           |

```powershell
# Run all discovered tests
Run-Tests

# Run only tests matching a name pattern
Run-Tests -TestName "Open-Terminal"

# Print the full run log to the console afterwards
Run-Tests -Detailed

# Run everything in a single worker (useful when diagnosing cross-test interference)
Run-Tests -Workers 1

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

Buckets are balanced by longest-processing-time-first, weighted by each file's measured duration from the previous run (`Results/timings.json`); on a cold checkout, file size stands in. Two files whose tests touch state shared across processes - `Set-WorkspaceWindowLayout.Tests.ps1` (real User-scope `WORKSPACE_*` variables) and `Reset-KeyboardModifiers.Tests.ps1` (real keystroke injection) - are pinned into the same bucket so they can never run concurrently with each other.

### Run artifacts

Everything a detailed serial run would have printed - every per-test line, and everything the code under test writes to the console - is captured per worker and merged into a single run log. `Results/` is gitignored, exactly like the Logging module's `Logs/`:

| File                                  | Contents                                                                                |
| ------------------------------------- | --------------------------------------------------------------------------------------- |
| `TestRun_<run>.log`                   | Summary, per-worker breakdown, failures, slowest 20 files, then every worker transcript. |
| `pester-results-<run>-worker<N>.xml`  | One NUnit3 XML per worker. CI merges the glob into a single check run.                   |
| `timings.json`                        | Measured per-file duration and test count, used to bucket the next run.                 |

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
