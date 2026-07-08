function Install-DotnetEf {
	<#
	.SYNOPSIS
		Installs or updates the EF Core CLI tool (`dotnet-ef`).

	.DESCRIPTION
		Installs the `dotnet ef` global tool at the version specified by the `DotnetEFVersion`
		key in Configuration.psd1. Requires the .NET SDK to be installed; skips silently if not found.

		With `-Update`, installs the latest available version instead of the pinned version.

		Called automatically by Bootstrap.

	.PARAMETER Update
		Installs the latest available version of dotnet-ef instead of the pinned version.

	.EXAMPLE
		Install-DotnetEf
		Installs the pinned dotnet-ef version from Configuration.psd1.

	.EXAMPLE
		Install-DotnetEf -Update
		Installs the latest available dotnet-ef version.
	#>
	[CmdletBinding()]
	param(
		[Parameter()]
		[switch]$Update
	)

	Write-LogTitle "Configuring Dotnet EF"

	if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
		Write-LogWarning ".NET SDK is not installed. Skipping Dotnet EF installation!"
		return
	}

	$version = $global:Configuration.DotnetEFVersion

	if ($Update) {
		Write-LogTitle "Updating Dotnet EF to latest version" -BlankLineAfter

		try {
			dotnet tool update --global dotnet-ef

			Write-LogSuccess "Dotnet EF updated successfully!"
		}
		catch {
			Write-LogError "Error updating: $_"
		}
		return
	}

	if (Get-Command dotnet-ef -ErrorAction SilentlyContinue) {
		Write-Host ""
		dotnet ef --version
		Write-LogWarning "Dotnet EF is already installed!"
		return
	}

	if ([string]::IsNullOrWhiteSpace($version)) {
		Write-LogTitle "Installing latest version of Dotnet EF" -BlankLineAfter

		try {
			dotnet tool install --global dotnet-ef

			Write-LogSuccess "Dotnet EF installed successfully!"
		}
		catch {
			Write-LogError "Error installing Dotnet EF: $_"
		}
		return
	}

	Write-LogTitle "Installing Dotnet EF version $version" -BlankLineAfter

	try {
		dotnet tool install --global dotnet-ef --version $version

		Write-LogSuccess "Dotnet EF version $version installed successfully!"
	}
	catch {
		Write-LogError "Error installing Dotnet EF: $_"
	}
}
