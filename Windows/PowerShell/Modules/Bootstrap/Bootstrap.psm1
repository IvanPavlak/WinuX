# Ensure the Logging module is available. The profile imports it before Bootstrap, but the
# cold-start path (Install-Bootstrap.ps1) imports this module by full path before the profile
# runs, so Bootstrap's functions would otherwise have no Write-Log* available. Import it from
# the sibling Logging directory when it isn't already loaded.
if (-not (Get-Module -Name Logging)) {
	$LoggingModulePath = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath "Logging"
	if (Test-Path $LoggingModulePath) {
		Import-Module -Name $LoggingModulePath -Force -Global -ErrorAction SilentlyContinue
	}
}

$ModulesPath = Join-Path -Path $PSScriptRoot -ChildPath "\Functions"

$Functions = Get-ChildItem -Path (Join-Path $ModulesPath "*.ps1")

foreach ($Function in $Functions) {
	. $Function.FullName
}

$Functions | ForEach-Object {
	$FunctionName = $_.BaseName
	Export-ModuleMember -Function $FunctionName
}
