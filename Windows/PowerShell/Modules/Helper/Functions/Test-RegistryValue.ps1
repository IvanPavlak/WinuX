function Test-RegistryValue {
	<#
	.SYNOPSIS
		Verify a registry value matches expected content.

	.DESCRIPTION
		Reads registry entry at specified path and compares against expected value.
		Returns $true if match, $false if not found or mismatch.

	.PARAMETER Path
		Registry path (e.g., 'HKCU:\Software\...').

	.PARAMETER Name
		Registry value name.

	.PARAMETER ExpectedValue
		Expected value to compare against.

	.EXAMPLE
		if (Test-RegistryValue -Path 'HKCU:\Control Panel\Desktop' -Name 'Wallpaper' -ExpectedValue 'C:\my.jpg') { Write-Host "Wallpaper set" }
	#>
	param(
		[Parameter(Mandatory)]
		[string]$Path,
		[Parameter(Mandatory)]
		[string]$Name,
		[Parameter(Mandatory)]
		[string]$ExpectedValue
	)

	try {
		$value = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
		return $value.$Name -eq $ExpectedValue
	}
	catch {
		return $false
	}
}
