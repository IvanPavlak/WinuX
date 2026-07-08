@{
	ModuleVersion     = "1.0"
	Author            = "Ivan Pavlak"
	Description       = "Unified logging for the repository: standardized, color-coded terminal output plus structured, retention-bounded file logs."
	RootModule        = "Logging.psm1"
	FunctionsToExport = @(
		'Clear-OldLogs',
		'Get-LogPath',
		'Initialize-LoggingState',
		'Protect-Log',
		'Set-LogLevel',
		'Start-Logging',
		'Stop-Logging',
		'Test-LogVerbose',
		'Write-Log',
		'Write-LogDebug',
		'Write-LogError',
		'Write-LogList',
		'Write-LogStep',
		'Write-LogSuccess',
		'Write-LogTitle',
		'Write-LogWarning'
	)
}
