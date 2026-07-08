function Get-DotnetVersionFromTFM {
	<#
	.SYNOPSIS
		Parse .NET version from Target Framework Moniker (TFM).

	.DESCRIPTION
		Extracts version info from TFM strings like 'net8.0', 'netcoreapp3.1', 'net48'.
		Returns PSCustomObject with Major, Minor, Version, IsModern, IsFramework properties.

	.PARAMETER TFM
		The target framework moniker string (e.g., 'net8.0', 'netcoreapp3.1').

	.EXAMPLE
		$info = Get-DotnetVersionFromTFM -TFM "net8.0"
		Write-Host "Version: $($info.Version), IsModern: $($info.IsModern)"
	#>
	param(
		[Parameter(Mandatory = $true)]
		[string]$TFM
	)

	if ($TFM -match '^net(\d+)\.(\d+)') {
		$major = [int]$matches[1]
		$minor = [int]$matches[2]
		return [PSCustomObject]@{
			Major       = $major
			Minor       = $minor
			Version     = "$major.$minor"
			IsModern    = $true
			IsFramework = $false
		}
	}
	elseif ($TFM -match '^netcoreapp(\d+)\.(\d+)') {
		$major = [int]$matches[1]
		$minor = [int]$matches[2]
		return [PSCustomObject]@{
			Major       = $major
			Minor       = $minor
			Version     = "$major.$minor"
			IsModern    = $true
			IsFramework = $false
		}
	}
	elseif ($TFM -match '^net(\d)(\d+)$') {
		return [PSCustomObject]@{
			Major       = 0
			Minor       = 0
			Version     = "Framework"
			IsModern    = $false
			IsFramework = $true
		}
	}
	elseif ($TFM -match '^netstandard') {
		return [PSCustomObject]@{
			Major       = 0
			Minor       = 0
			Version     = "Standard"
			IsModern    = $false
			IsFramework = $false
		}
	}

	return $null
}
