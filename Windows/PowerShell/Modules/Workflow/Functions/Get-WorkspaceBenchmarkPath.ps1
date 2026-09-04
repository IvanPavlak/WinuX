function Get-WorkspaceBenchmarkPath {
	<#
	.SYNOPSIS
		Resolves the path of the workspace benchmark file - WorkspaceBenchmark.csv next to the session logs.

	.DESCRIPTION
		Write-WorkspaceBenchmark appends one row per workspace open to this file and
		Get-WorkspaceBenchmark reads it back; both resolve the path here so the two can never
		disagree. The file lives in the Logging module's Logs folder (Get-LogPath -Directory), which
		follows the Logging.FileLogging.Directory override when one is configured and is
		git-ignored - the rows are per-machine measurements with no meaning anywhere else. When the
		Logging module is not loaded the file falls back to the Workflow module's State folder,
		beside the open-workspace tracker, which is git-ignored for the same reason.

		The file itself may not exist yet; nothing here creates it.

	.EXAMPLE
		Get-WorkspaceBenchmarkPath
		Import-Csv (Get-WorkspaceBenchmarkPath)
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param ()

	$fileName = 'WorkspaceBenchmark.csv'

	if (Get-Command Get-LogPath -ErrorAction SilentlyContinue) {
		try {
			$logsDirectory = Get-LogPath -Directory
			if (-not [string]::IsNullOrWhiteSpace($logsDirectory)) {
				return Join-Path -Path $logsDirectory -ChildPath $fileName
			}
		}
		catch {
			# The Logging state could not be initialized - fall through to the State folder.
		}
	}

	$stateDirectory = Split-Path -Path (Get-WorkspaceStatePath) -Parent
	return Join-Path -Path $stateDirectory -ChildPath $fileName
}
