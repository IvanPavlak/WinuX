function Install-PowerShellModules {
	<#
	.SYNOPSIS
		Installs required PowerShell modules from PSGallery.

	.DESCRIPTION
		Ensures the NuGet provider and PSGallery trusted repository are configured, then
		installs the following modules if not already present:
		- Terminal-Icons    - file type icons in the terminal
		- PSReadLine        - enhanced command-line editing and history
		- z                 - directory jump shortcut (frecency-based)
		- VirtualDesktop    - Windows virtual desktop COM API wrapper (pinned to 1.5.11)
		- ps2exe            - PowerShell-to-EXE compiler
		- Pester            - PowerShell testing framework (pinned to the repo's required
		                      version, skipped if that exact version is present)

		VirtualDesktop is pinned because the module wraps undocumented COM interfaces that
		break between Windows builds. Only tested/verified versions are used - the tested
		combination is tracked in Modules\Bootstrap\Data\WinGetApps.csv (TESTED VERSIONS block).

		Called automatically by Bootstrap.

	.EXAMPLE
		Install-PowerShellModules
		Installs all required modules that are not already present.
	#>
	Write-LogTitle "Installing PowerShell Modules" -BlankLineAfter

	try {
		Write-LogStep " Installing NuGet provider..."
		if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
			Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ForceBootstrap -ErrorAction Stop | Out-Null
		}

		$psGallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
		if ($psGallery -and $psGallery.InstallationPolicy -ne 'Trusted') {
			Write-LogStep " Setting PSGallery as trusted repository..."
			Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
		}

		# Pin VirtualDesktop to known-working version for Window module reliability
		# See: Modules\Bootstrap\Data\WinGetApps.csv - TESTED VERSIONS block
		$pinnedModules = @{
			"VirtualDesktop" = "1.5.11"
		}

		$modulesToInstall = @(
			"Terminal-Icons",
			"PSReadLine",
			"z",
			"VirtualDesktop",
			"ps2exe"
		)

		$installedAny = $false
		foreach ($moduleName in $modulesToInstall) {
			$pinnedVersion = $pinnedModules[$moduleName]
			$existingModule = Get-Module -ListAvailable -Name $moduleName | Sort-Object Version -Descending | Select-Object -First 1

			if ($existingModule) {
				if ($pinnedVersion -and $existingModule.Version -ne [Version]$pinnedVersion) {
					Write-LogStep " [$moduleName] installing pinned version $pinnedVersion (current: v$($existingModule.Version))..."
					Install-Module -Name $moduleName -Repository PSGallery -Scope CurrentUser -Force -AllowClobber -RequiredVersion $pinnedVersion
					$installedAny = $true
				}
				else {
					Write-LogWarning " [$moduleName] already installed! (v$($existingModule.Version))"
				}
			}
			else {
				$versionMsg = if ($pinnedVersion) { " v$pinnedVersion" } else { "" }
				Write-LogStep " Installing $moduleName$versionMsg..."
				$installParams = @{
					Name         = $moduleName
					Repository   = 'PSGallery'
					Scope        = 'CurrentUser'
					Force        = $true
					AllowClobber = $true
				}
				if ($pinnedVersion) { $installParams['RequiredVersion'] = $pinnedVersion }
				Install-Module @installParams
				$installedAny = $true
			}
		}

		# Handle Pester separately due to side-by-side installation requirements
		# Windows 10/Server 2016+ ships with Pester 3.4.0 which cannot be updated normally
		# Must use -SkipPublisherCheck due to different certificate between Microsoft and community versions
		#
		# Pester is pinned repo-wide: the harness imports exactly this version (side-by-side with
		# the un-removable in-box 3.4.0 and anything else already installed). Single source of
		# truth is Tests\RequiredPesterVersion.txt - bump it there, then re-run this function on
		# every machine.
		$requiredPesterVersion = [Version](Get-Content -LiteralPath (Join-Path (Get-RepositoryPath).Modules "Tests\RequiredPesterVersion.txt")).Trim()
		$pesterInstalled = Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -eq $requiredPesterVersion }
		if ($pesterInstalled) {
			Write-LogWarning " [Pester] pinned version already installed! (v$requiredPesterVersion)"
		}
		else {
			Write-LogStep " Installing Pester v$requiredPesterVersion (side-by-side)..."
			Install-Module -Name Pester -RequiredVersion $requiredPesterVersion -Force -SkipPublisherCheck -Scope CurrentUser
			$installedAny = $true
		}

		if ($installedAny) {
			Write-LogSuccess "PowerShell module(s) successfully installed!"
		}
	}
	catch {
		Write-LogError "Error installing modules: $($_.Exception.Message)"
		throw
	}
}
