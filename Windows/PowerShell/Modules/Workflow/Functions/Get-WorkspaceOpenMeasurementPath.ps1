function Get-WorkspaceOpenMeasurementPath {
	<#
	.SYNOPSIS
		Resolves the path of the experiment result file - WorkspaceOpenMeasurements.csv beside the benchmark file.

	.DESCRIPTION
		Measure-WorkspaceOpen appends one row per open it runs to this file and
		Get-WorkspaceOpenMeasurement reads them back; both resolve the path here so the two can
		never disagree. The file lives in the same folder as WorkspaceBenchmark.csv
		(Get-WorkspaceBenchmarkPath): the Logging module's Logs folder, or the Workflow module's
		State folder when Logging is not loaded. Both are git-ignored - the rows are per-machine
		measurements with no meaning anywhere else.

		The file itself may not exist yet; nothing here creates it.

	.EXAMPLE
		Get-WorkspaceOpenMeasurementPath
		Import-Csv (Get-WorkspaceOpenMeasurementPath)
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param ()

	$benchmarkPath = Get-WorkspaceBenchmarkPath
	return Join-Path -Path (Split-Path -Path $benchmarkPath -Parent) -ChildPath 'WorkspaceOpenMeasurements.csv'
}
