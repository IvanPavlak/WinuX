# Tests Module

The Tests module provides **Pester test execution** for WinuX. It validates Application, Bootstrap, Configuration, Git, Helper, Logging, System, Window, and Workflow module logic, plus repository-infrastructure checks.

> [!NOTE]
> The repository maintains broad module-wide test coverage with same-name test files for function behavior checks, including complete same-name coverage for the System module.

## [Run-Tests](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Tests/Functions/Run-Tests.ps1)

- **Description:** Discovers and runs all `.Tests.ps1` Pester tests in the PowerShell Modules Tests directory (every module's test folder plus the Infrastructure checks). Supports filtering by test name pattern, detailed output, and returning the Pester result object. Works with both Pester 3.x/4.x (legacy parameters) and 5.x (configuration object).
- **Parameters:** -TestName, -Path, -Detailed, -PassThru
- **Usage:** `Run-Tests`, `Run-Tests -TestName "Open-Terminal"`, `Run-Tests -Detailed`, `$results = Run-Tests -PassThru`

Recursively discovers `*.Tests.ps1` files under the Tests directory (or a custom `-Path`), lists the files to be run, and invokes Pester. Detects the installed Pester version and errors with guidance to run `Install-PowerShellModules` if Pester is missing. After running, it reloads the PowerShell profile and prints a pass/fail summary. With `-PassThru`, the raw Pester result object is returned for scripting (e.g. CI/CD).

| Parameter   | Description                                                           |
| ----------- | --------------------------------------------------------------------- |
| `-TestName` | Filter to run only tests whose file name matches the given pattern.   |
| `-Path`     | Custom path to test files. Defaults to the Tests directory.           |
| `-Detailed` | Show detailed Pester output instead of the normal summary.            |
| `-PassThru` | Return the Pester result object instead of just printing the summary. |

```powershell
# Run all discovered tests
Run-Tests

# Run only tests matching a name pattern
Run-Tests -TestName "Open-Terminal"

# Run with detailed Pester output
Run-Tests -Detailed

# Capture the result object for CI/CD gating
$results = Run-Tests -PassThru
if ($results.FailedCount -gt 0) {
    exit 1
}
```

**See also:** [Configuration: Overview](../configuration/overview.md), [Getting Started: First Run](../getting-started/first-run.md)

## Test File Structure

Tests are organized by module under `Modules/Tests/`:

```
Modules/Tests/
├── Tests.psd1              # Module manifest
├── Tests.psm1              # Module loader
├── Functions/
│   └── Run-Tests.ps1       # Test runner function
└── Modules/
    ├── Application/         # Application module tests
    ├── Bootstrap/           # Bootstrap module tests
    ├── Configuration/       # Configuration module tests
    ├── Git/                 # Git module tests
    ├── Helper/              # Helper module tests
    ├── Infrastructure/      # Repository-wide checks (e.g. documentation links)
    ├── Logging/             # Logging module tests
    ├── System/              # System module tests
    ├── Window/              # Window module tests
    └── Workflow/            # Workflow module tests
```

Tests are grouped by the module they validate, not by the Tests module itself.

## Writing Tests

### Pester Test Pattern

Tests use the [Pester](https://pester.dev/) framework (v5+):

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

```powershell
Run-Tests -Detailed
```

### CI/CD Integration

```powershell
$results = Run-Tests -PassThru
if ($results.FailedCount -gt 0) {
    exit 1
}
```
