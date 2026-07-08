function Initialize-LoggingState {
	<#
	.SYNOPSIS
		Initializes (or resets) the shared logging state used by every Write-Log* function.

	.DESCRIPTION
		Builds the $global:LoggingState hashtable that the logging engine reads on every call:
		the active verbosity level, the color palette, the file-logging toggle, and the resolved
		session/error log file paths inside the module's own Logs/ folder.

		Settings are read from $global:Configuration.Logging when present, falling back to the
		documented house defaults so the module works even before configuration is loaded
		(e.g. early in bootstrap). Called lazily by Write-Log on first use; call it directly with
		-Force only to re-read configuration or start a fresh session file mid-session.

	.PARAMETER Force
		Rebuilds the state even if it already exists (re-reads config, opens a new session file).

	.EXAMPLE
		Initialize-LoggingState
		Ensures logging state exists (no-op if already initialized).

	.EXAMPLE
		Initialize-LoggingState -Force
		Re-reads $Configuration.Logging and starts a new session log file.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $false)]
		[switch]$Force
	)

	if ($global:LoggingState -and -not $Force) {
		return $global:LoggingState
	}

	$cfg = $null
	if ($global:Configuration -and $global:Configuration.Logging) {
		$cfg = $global:Configuration.Logging
	}

	# Documented house palette - overridable per-key from config.
	$colors = @{
		Title   = "DarkCyan"
		Step    = "White"
		Success = "Green"
		Warning = "Yellow"
		Error   = "Red"
		Debug   = "DarkCyan"
	}
	if ($cfg -and $cfg.Colors) {
		foreach ($key in $cfg.Colors.Keys) {
			$colors[$key] = $cfg.Colors[$key]
		}
	}

	$level = "Normal"
	if ($cfg -and $cfg.DefaultLevel) {
		$level = $cfg.DefaultLevel
	}

	$fileLoggingEnabled = $true
	if ($cfg -and $cfg.FileLogging -and $null -ne $cfg.FileLogging.Enabled) {
		$fileLoggingEnabled = [bool]$cfg.FileLogging.Enabled
	}

	# Resolve the Logs directory: config override, else the module's own Logs/ folder
	# ($PSScriptRoot here is the module's Functions/ directory).
	$moduleRoot = Split-Path -Path $PSScriptRoot -Parent
	$logsDir = Join-Path $moduleRoot "Logs"
	if ($cfg -and $cfg.FileLogging -and $cfg.FileLogging.Directory) {
		$logsDir = $cfg.FileLogging.Directory
	}

	if ($fileLoggingEnabled -and -not (Test-Path $logsDir)) {
		try { New-Item -ItemType Directory -Path $logsDir -Force | Out-Null } catch { $fileLoggingEnabled = $false }
	}

	$errorFileName = "Errors.log"
	if ($cfg -and $cfg.FileLogging -and $cfg.FileLogging.ErrorFileName) {
		$errorFileName = $cfg.FileLogging.ErrorFileName
	}

	$sessionStamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
	$sessionFile = Join-Path $logsDir "Session_${sessionStamp}_$PID.log"
	$errorFile = Join-Path $logsDir $errorFileName

	$global:LoggingState = @{
		Level       = $level          # Quiet | Normal | Verbose
		Colors      = $colors
		FileLogging = $fileLoggingEnabled
		LogsDir     = $logsDir
		PinnedDir   = (Join-Path $logsDir "Pinned")
		SessionFile = $sessionFile
		ErrorFile   = $errorFile
		Config      = $cfg
	}

	return $global:LoggingState
}
