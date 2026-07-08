# Logging Module

The Logging module is the **single source of truth for repository output**. It provides the
color-coded `Write-Log*` terminal functions (replacing ad-hoc `Write-Host`), a global verbosity
control (`Set-LogLevel`), and structured, retention-bounded file logging written to the module's own
`Logs/` folder (gitignored).

Console rendering follows the house style exactly - pass the message text only; the engine adds the
leading newline and the per-level decoration (`[ ]` brackets for titles, the `=> ` prefix for success
and error):

| Function           | Color    | Rendered                                                     |
| ------------------ | -------- | ------------------------------------------------------------ |
| `Write-LogTitle`   | DarkCyan | `` `n[Message]``                                             |
| `Write-LogStep`    | White    | `` `nMessage``                                               |
| `Write-LogSuccess` | Green    | `` `n=> Message``                                            |
| `Write-LogWarning` | Yellow   | `` `n Message`` (leading space, no `=>`)                     |
| `Write-LogError`   | Red      | `` `n=> Message`` (also recorded verbosely to the error log) |
| `Write-LogDebug`   | DarkCyan | `` `n [Caller] Message`` (verbose-gated)                     |

Verbosity is controlled globally with `Set-LogLevel` (cross-module reliable; a global
`$VerbosePreference = 'Continue'` is also honored). File logging records every level regardless of
console verbosity, so the on-disk record is always complete.

## [Clear-OldLogs](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Logging/Functions/Clear-OldLogs.ps1)

- **Description:** Enforces log retention so the `Logs/` folder stays small but complete. Prunes session logs (`Session_*.log`) by age, then count, then total size (oldest removed first), and trims the error log past its size cap. Logs in `Logs/Pinned` are never touched. Called automatically by `Stop-Logging`; limits default from `Configuration.Logging.FileLogging.Retention`.
- **Parameters:** `[-MaxAgeDays]` `[-MaxSessionFiles]` `[-MaxTotalSizeMB]` `[-MaxErrorFileSizeMB]`
- **Usage:** `Clear-OldLogs`, `Clear-OldLogs -MaxSessionFiles 5`

## [Get-LogPath](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Logging/Functions/Get-LogPath.ps1)

- **Description:** Returns the path of the current structured session log, the shared error log, or the `Logs/` directory. Useful for opening or tailing logs after a run.
- **Parameters:** `[-ErrorLog]` `[-Directory]`
- **Usage:** `Get-Content (Get-LogPath) -Tail 40`, `Get-LogPath -ErrorLog`

## [Initialize-LoggingState](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Logging/Functions/Initialize-LoggingState.ps1)

- **Description:** Initializes (or, with `-Force`, resets) the shared `$global:LoggingState` that the engine reads on every call: active verbosity level, color palette, file-logging toggle, and resolved session/error log paths. Reads `Configuration.Logging` when present, falling back to documented defaults. Called lazily by `Write-Log` on first use.
- **Parameters:** `[-Force]`
- **Usage:** `Initialize-LoggingState`, `Initialize-LoggingState -Force`

## [Protect-Log](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Logging/Functions/Protect-Log.ps1)

- **Description:** Pins a log into the `Logs/Pinned` subfolder so retention never deletes it. Use this to keep a log during ongoing development or while investigating an issue. The original stays in place (an active session keeps recording to it); the pinned copy is the protected snapshot. Defaults to the current session log.
- **Parameters:** `[-Path]` `[-ErrorLog]`
- **Usage:** `Protect-Log`, `Protect-Log -ErrorLog`

## [Set-LogLevel](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Logging/Functions/Set-LogLevel.ps1)

- **Description:** Sets console verbosity for the logging engine - `Quiet` (Warning/Error only), `Normal` (default; Debug hidden), or `Verbose` (everything, including `Write-LogDebug`). This is the cross-module verbosity control: set it once and every function's debug output honors it, with no parameter threading. With a `-Command` scriptblock it applies only for that command (and everything it calls), then restores the previous level. File logging always records every level.
- **Parameters:** `-Level` `[-Command]`
- **Usage:** `Set-LogLevel Verbose`, `Set-LogLevel Verbose { Open-Workspace }`, `Set-LogLevel Normal`

## [Start-Logging](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Logging/Functions/Start-Logging.ps1)

- **Description:** Begins PowerShell transcript logging to a timestamped `BootstrapLog_<yyyy-MM-dd_HH-mm-ss>.log` file on the Desktop (location preserved for fresh-machine parity), sets the global `$logPath`/`$startTime`, and opens a structured logging session so `Write-Log*` output is mirrored to the `Logs/` folder. Used during bootstrap and setup for an audit trail.
- **Usage:** `Start-Logging`

**See also:** [Stop-Logging](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Logging/Functions/Stop-Logging.ps1)

## [Stop-Logging](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Logging/Functions/Stop-Logging.ps1)

- **Description:** Ends the transcript started by `Start-Logging`, prints the Desktop log location and a formatted total duration, then enforces structured-log retention via `Clear-OldLogs`.
- **Usage:** `Stop-Logging`

**See also:** [Start-Logging](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Logging/Functions/Start-Logging.ps1)

## [Test-LogVerbose](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Logging/Functions/Test-LogVerbose.ps1)

- **Description:** Returns `$true` when verbose logging is active (`Set-LogLevel Verbose`, a scoped verbose command, or a global `$VerbosePreference = 'Continue'`). Used to guard debug-only _work_ - not just output - e.g. `if (Test-LogVerbose) { $x = Get-Expensive; Write-LogDebug "...$x" }`. A bare `Write-LogDebug` already applies the same check, so only use this to also skip the surrounding computation when not verbose.
- **Usage:** `if (Test-LogVerbose) { Write-LogDebug "diag" }`

## [Write-Log](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Logging/Functions/Write-Log.ps1)

- **Description:** Core logging engine that every `Write-Log*` wrapper calls. Renders a styled, leveled message to the console (house style per level) and mirrors it to the structured session log; errors are additionally appended verbosely to the error log. Prefer the wrappers in normal code; call `Write-Log` directly only when the level must be chosen dynamically. Pass the message text only - the engine adds the leading newline and level decoration.
- **Parameters:** `-Message` `[-Level]` `[-Style]` `[-NoNewLine]` `[-NoLeadingNewline]` `[-Exception]` `[-BlankLineAfter]`
- **Usage:** `Write-Log -Level Success -Message "Workspace opened!"`

## [Write-LogDebug](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Logging/Functions/Write-LogDebug.ps1)

- **Description:** Writes a verbose-gated diagnostic message (DarkCyan by default). Prints to the console only when verbose logging is active (`Set-LogLevel Verbose`); suppressed lines are still written to the file log at full detail. Use `-Style` to render the diagnostic in another level's color.
- **Parameters:** `-Message` `[-Style]` `[-NoLeadingNewline]` `[-BlankLineAfter]`
- **Usage:** `Write-LogDebug "Captured $n handle(s)"`, `Write-LogDebug "Using layout => [$file]" -Style Success`

## [Write-LogError](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Logging/Functions/Write-LogError.ps1)

- **Description:** Writes an error in the house `=> ` style (Red), mirrors it to the session log, and appends a verbose entry (message + exception + stack trace, when `-Exception` is supplied) to the shared error log so failures can always be inspected later. Pass the message text only.
- **Parameters:** `-Message` `[-Exception]` `[-NoLeadingNewline]` `[-BlankLineAfter]`
- **Usage:** `Write-LogError "No solution file found!"`, `catch { Write-LogError "Build failed: $($_.Exception.Message)" -Exception $_ }`

## [Write-LogList](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Logging/Functions/Write-LogList.ps1)

- **Description:** Writes a bulleted list of items (`  • <item>`, White) directly beneath a preceding summary line, with no leading blank line so the list sits under it. Empty/whitespace items are skipped. Shared renderer for the "summary + bulleted detail" output used by centered/moved windows, opened browser subgroups, etc.
- **Parameters:** `[-Items]`
- **Usage:** `Write-LogSuccess "Centered 2 window(s)!"; Write-LogList @("Windows Terminal", "Firefox")`

## [Write-LogStep](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Logging/Functions/Write-LogStep.ps1)

- **Description:** Writes a plain step/progress statement (White), replacing the `Write-Host -ForegroundColor White` idiom. Leading-space indentation in the message is preserved so nested sub-steps keep their alignment.
- **Parameters:** `-Message` `[-NoNewLine]` `[-NoLeadingNewline]` `[-BlankLineAfter]`
- **Usage:** `Write-LogStep "Opening training file..."`

## [Write-LogSuccess](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Logging/Functions/Write-LogSuccess.ps1)

- **Description:** Writes a success message in the house `=> ` style (Green), replacing the `Write-Host -ForegroundColor Green "`n=> ..."`idiom. Pass the message text only - the leading newline and`=> ` prefix are added by the engine.
- **Parameters:** `-Message` `[-NoLeadingNewline]` `[-BlankLineAfter]`
- **Usage:** `Write-LogSuccess "Workspace opened successfully!"`

## [Write-LogTitle](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Logging/Functions/Write-LogTitle.ps1)

- **Description:** Writes a section header in the house `[Title]` style (DarkCyan), replacing the `Write-Host -ForegroundColor DarkCyan "`n[Title]"` idiom. Pass the bare title text - the brackets and leading newline are added by the engine.
- **Parameters:** `-Message` `[-NoLeadingNewline]` `[-BlankLineAfter]`
- **Usage:** `Write-LogTitle "Kill All"`

## [Write-LogWarning](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Logging/Functions/Write-LogWarning.ps1)

- **Description:** Writes a warning (Yellow), rendered as `` `n Message`` - a leading-space indent with **no** `=>` prefix (unlike success and error). Pass the message text only.
- **Parameters:** `-Message` `[-NoLeadingNewline]` `[-BlankLineAfter]`
- **Usage:** `Write-LogWarning "No layout configuration found for workspace => [GroupName]"`
