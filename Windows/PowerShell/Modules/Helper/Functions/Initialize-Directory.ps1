function Initialize-Directory {
	<#
	.SYNOPSIS
		Create a directory if it doesn't exist.

	.DESCRIPTION
		Checks if path exists; creates it with all parent directories if missing.
		Displays green success message when directory is created.

	.PARAMETER Path
		Directory path to create or verify.

	.EXAMPLE
		Initialize-Directory -Path "C:\Temp\MyApp\Data"
	#>
	param([string]$Path)

	if (-not (Test-Path $Path)) {
		New-Item -ItemType Directory -Path $Path -Force | Out-Null
		Write-LogSuccess "Created directory => [$Path]"
	}
}
