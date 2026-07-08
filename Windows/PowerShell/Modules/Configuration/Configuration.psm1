$script:ConfigurationPath = Join-Path $PSScriptRoot "..\..\Configuration.psd1"
$script:LayoutsPath = Join-Path $PSScriptRoot "..\Window\Layouts"

$ModulesPath = Join-Path -Path $PSScriptRoot -ChildPath "\Functions"
$Functions = Get-ChildItem -Path (Join-Path $ModulesPath "*.ps1")
foreach ($Function in $Functions) {
	. $Function.FullName
}
$Functions | ForEach-Object {
	$FunctionName = $_.BaseName
	Export-ModuleMember -Function $FunctionName
}
