#Requires -Modules Pester

BeforeAll {
	$script:OriginalMachineSpecificPaths = $global:MachineSpecificPaths
	$script:OriginalConfiguration = $global:Configuration

	$ModuleRoot = (Get-RepositoryPath).Modules
	$BootstrapFunctionsPath = Join-Path $ModuleRoot "Bootstrap\Functions"
	. "$BootstrapFunctionsPath\Bootstrap.ps1"
	# Dot-source the personal-steps runner so it exists to Mock even in sessions whose imported
	# Bootstrap module predates the Invoke-PersonalSteps export.
	. "$BootstrapFunctionsPath\Invoke-PersonalSteps.ps1"
	# Bootstrap gates its steps through Resolve-BootstrapSteps (which delegates to the
	# shared Resolve-Steps).
	. "$ModuleRoot\Helper\Functions\Resolve-Steps.ps1"
	. "$BootstrapFunctionsPath\Resolve-BootstrapSteps.ps1"
	# Bootstrap gates the package-manager steps through Resolve-PackageManagers; dot-source it so it
	# exists to Mock even in sessions whose imported Bootstrap module predates the export.
	. "$BootstrapFunctionsPath\Resolve-PackageManagers.ps1"
}

AfterAll {
	$global:MachineSpecificPaths = $script:OriginalMachineSpecificPaths
	$global:Configuration = $script:OriginalConfiguration
	$global:startTime = $null
}

Describe "Bootstrap" {
	BeforeEach {
		$global:MachineSpecificPaths = @{ Projects = @{ Self = @{ Root = 'C:\Repo\WinuX' } } }
		$global:Configuration = @{
			DefaultLocale            = 'en-US'
			DefaultDisplayLanguage   = 'en-US'
			DefaultKeyboardLayoutSet = 'US'
			DefaultNerdFont          = 'JetBrainsMono'
		}
		$global:startTime = $null

		Mock Write-Host { }
		Mock Write-LogTitle { }
		Mock Write-LogSuccess { }
		Mock Write-LogWarning { }
		Mock Write-LogError { }
		Mock Invoke-PersonalSteps { }
		Mock Test-AdminPrivileges { }
		Mock Start-Logging { $global:startTime = Get-Date }
		Mock Stop-Logging { }
		Mock Load-PathConfiguration { @{ Ok = $true } }
		Mock Initialize-Configuration { }
		Mock Rename-Machine { }
		Mock Start-MicrosoftActivationScripts { }
		Mock Start-Win11Debloat { }
		Mock Update-Repositories { }
		Mock Set-CustomExecutionPolicy { }
		Mock Enable-DeveloperMode { }
		Mock Set-PowerPlan { }
		Mock Set-PowerButtonActions { }
		Mock Set-SystemTheme { param([switch]$Auto, [switch]$KeepTerminalOpen) }
		Mock Set-Locale { }
		Mock Set-DisplayLanguage { }
		Mock Set-KeyboardLayouts { }
		Mock Display-SystemLanguageSettings { }
		Mock Configure-NerdFont { }
		Mock Install-PowerShellModules { }
		Mock Set-SpecialFolders { }
		Mock Restart-Explorer { }
		Mock Configure-WSL { }
		# All three in play by default, so the step-toggle tests below exercise the toggles alone.
		Mock Resolve-PackageManagers { @('WinGet', 'Scoop', 'Chocolatey') }
		Mock Install-WinGetPackageManager { }
		Mock Install-WinGetApps { }
		Mock Install-ScoopPackageManager { }
		Mock Install-ScoopApps { }
		Mock Install-ChocolateyPackageManager { }
		Mock Install-ChocolateyApps { }
		Mock Upgrade-All { }
		Mock Install-DotnetEF { }
		Mock Set-EnvironmentVariables { }
		Mock Create-CondaEnvironments { }
		Mock Configure-NuGetConfig { }
		Mock Configure-Taskbar { }
		Mock Initialize-WSLEnvironment { }
		Mock SymbolicLinkMaker { }
		Mock Configure-WSLSSH { }
		Mock Set-ItemProperty { }
		Mock Restart-Machine { }
	}

	It "runs initial-setup steps and uses Update-Repositories -All by default (no RepositoryUpdateScope override)" {
		$global:MachineType = 'Laptop'

		Bootstrap -WithInitialSetup

		Should -Invoke Rename-Machine -Times 1 -Exactly
		Should -Invoke Update-Repositories -Times 1 -Exactly -ParameterFilter { $All }
		Should -Invoke Set-SystemTheme -Times 1 -Exactly -ParameterFilter { $Auto -and $KeepTerminalOpen }
	}

	It "keeps MAS and Win11Debloat off by default even with -WithInitialSetup (opt-in steps)" {
		$global:MachineType = 'Laptop'

		Bootstrap -WithInitialSetup

		Should -Invoke Start-MicrosoftActivationScripts -Times 0
		Should -Invoke Start-Win11Debloat -Times 0
	}

	It "runs MAS and Win11Debloat when BootstrapConfig.Steps enables them" {
		$global:MachineType = 'Laptop'
		$global:Configuration.BootstrapConfig = @{ Steps = @{ MicrosoftActivationScripts = $true; Win11Debloat = $true } }

		Bootstrap -WithInitialSetup

		Should -Invoke Start-MicrosoftActivationScripts -Times 1 -Exactly
		Should -Invoke Start-Win11Debloat -Times 1 -Exactly
	}

	It "keeps the other opt-in steps off by default (DeveloperMode, NuGetConfig, LockedStartLayout)" {
		$global:MachineType = 'Laptop'

		Bootstrap

		Should -Invoke Enable-DeveloperMode -Times 0
		Should -Invoke Configure-NuGetConfig -Times 0
		Should -Invoke Set-ItemProperty -Times 0 -ParameterFilter { $Name -eq 'LockedStartLayout' }
	}

	It "runs the opt-in steps when BootstrapConfig.Steps enables them" {
		$global:MachineType = 'Laptop'
		$global:Configuration.BootstrapConfig = @{ Steps = @{ DeveloperMode = $true; NuGetConfig = $true; LockedStartLayout = $true } }

		Bootstrap

		Should -Invoke Enable-DeveloperMode -Times 1 -Exactly
		Should -Invoke Configure-NuGetConfig -Times 1 -Exactly
		Should -Invoke Set-ItemProperty -Times 1 -Exactly -ParameterFilter { $Name -eq 'LockedStartLayout' }
	}

	It "skips a default-on step when -Skip forces it off" {
		$global:MachineType = 'Laptop'

		Bootstrap -Skip PowerPlan

		Should -Invoke Set-PowerPlan -Times 0
		Should -Invoke Set-PowerButtonActions -Times 1 -Exactly
	}

	It "skips a config-disabled step (plain boolean in Steps)" {
		$global:MachineType = 'Laptop'
		# WinGetApps defaults ON, so switching it off here proves the config was actually read.
		# UpgradeAll would not: it defaults OFF, so the assertion would hold either way.
		$global:Configuration.BootstrapConfig = @{ Steps = @{ WinGetApps = $false } }

		Bootstrap

		Should -Invoke Install-WinGetApps -Times 0
		Should -Invoke Install-ScoopApps -Times 1 -Exactly
	}

	It "installs only the package managers that are in play" {
		$global:MachineType = 'Laptop'
		Mock Resolve-PackageManagers { @('WinGet') }

		Bootstrap

		Should -Invoke Install-WinGetPackageManager -Times 1 -Exactly
		Should -Invoke Install-WinGetApps -Times 1 -Exactly
		Should -Invoke Install-ScoopPackageManager -Times 0
		Should -Invoke Install-ScoopApps -Times 0
		Should -Invoke Install-ChocolateyPackageManager -Times 0
		Should -Invoke Install-ChocolateyApps -Times 0
	}

	It "does not install a package manager an enabled step asks for when it is not in play" {
		$global:MachineType = 'Laptop'
		$global:Configuration.BootstrapConfig = @{ Steps = @{ ScoopApps = $true } }
		Mock Resolve-PackageManagers { @('WinGet') }

		Bootstrap

		Should -Invoke Install-ScoopPackageManager -Times 0
		Should -Invoke Install-ScoopApps -Times 0
	}

	It "installs no package manager when none is in play" {
		$global:MachineType = 'Laptop'
		Mock Resolve-PackageManagers { @() }

		Bootstrap

		Should -Invoke Install-WinGetPackageManager -Times 0
		Should -Invoke Install-ScoopPackageManager -Times 0
		Should -Invoke Install-ChocolateyPackageManager -Times 0
		# Nothing installed means nothing to upgrade either.
		Should -Invoke Upgrade-All -Times 0
	}

	It "hands the resolved managers to Upgrade-All instead of letting it resolve again" {
		$global:MachineType = 'Laptop'
		# UpgradeAll is opt-in, so it has to be switched on for the step to run at all.
		$global:Configuration.BootstrapConfig = @{ Steps = @{ UpgradeAll = $true } }
		Mock Resolve-PackageManagers { @('WinGet', 'Scoop') }

		Bootstrap

		Should -Invoke Upgrade-All -Times 1 -Exactly -ParameterFilter {
			$PackageManager.Count -eq 2 -and $PackageManager -contains 'WinGet' -and $PackageManager -contains 'Scoop'
		}
	}

	It "uses Update-Repositories -Private when RepositoryUpdateScope maps the machine type to Private" {
		$global:MachineType = 'Test'
		$global:Configuration.BootstrapConfig = @{ RepositoryUpdateScope = @{ Default = 'All'; Test = 'Private' } }

		Bootstrap

		Should -Invoke Rename-Machine -Times 0
		Should -Invoke Update-Repositories -Times 1 -Exactly -ParameterFilter { $Private }
		Should -Invoke Set-SystemTheme -Times 1 -Exactly -ParameterFilter { $Auto -and $KeepTerminalOpen }
	}

	It "skips WSL steps when BootstrapConfig.WSLSetup disables them for the machine type" {
		$global:MachineType = 'Test'
		$global:Configuration.BootstrapConfig = @{ WSLSetup = @{ Default = $true; Test = $false } }

		Bootstrap

		Should -Invoke Configure-WSL -Times 0
		Should -Invoke Initialize-WSLEnvironment -Times 0
		Should -Invoke Configure-WSLSSH -Times 0
		Should -Invoke SymbolicLinkMaker -Times 1 -Exactly
		Should -Invoke Update-Repositories -Times 1 -Exactly -ParameterFilter { $All }
	}

	It "runs WSL steps when WSLSetup does not cover the machine type and has no Default" {
		$global:MachineType = 'Laptop'
		$global:Configuration.BootstrapConfig = @{ WSLSetup = @{ Test = $false } }

		Bootstrap

		Should -Invoke Configure-WSL -Times 1 -Exactly
		Should -Invoke Initialize-WSLEnvironment -Times 1 -Exactly
		Should -Invoke Configure-WSLSSH -Times 1 -Exactly
	}

	It "runs the fork-defined personal steps via Invoke-PersonalSteps" {
		$global:MachineType = 'Test'

		Bootstrap

		Should -Invoke Invoke-PersonalSteps -Times 1 -Exactly
	}
}
