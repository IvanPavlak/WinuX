#Requires -Modules Pester

BeforeAll {
	$script:OriginalMachineSpecificPaths = $global:MachineSpecificPaths
	$script:OriginalConfiguration = $global:Configuration

	$BootstrapFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Bootstrap\Functions"
	. "$BootstrapFunctionsPath\Bootstrap.ps1"
	# Dot-source the machine-scope gate so PersonalSteps gating resolves even in sessions whose
	# imported Bootstrap module predates the Test-MachineTypeScope export.
	. "$BootstrapFunctionsPath\Test-MachineTypeScope.ps1"
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
		Mock Write-LogDebug { }
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
		Should -Invoke Start-MicrosoftActivationScripts -Times 1 -Exactly
		Should -Invoke Start-Win11Debloat -Times 1 -Exactly
		Should -Invoke Update-Repositories -Times 1 -Exactly -ParameterFilter { $All }
		Should -Invoke Set-SystemTheme -Times 1 -Exactly -ParameterFilter { $Auto -and $KeepTerminalOpen }
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

	It "runs resolvable PersonalSteps and warns on unresolvable ones" {
		$global:MachineType = 'Test'
		# Rename-Machine is a real exported command that plain Bootstrap (no -WithInitialSetup)
		# never calls, so it doubles as a clean probe that PersonalSteps invoked it exactly once.
		$global:Configuration.BootstrapConfig = @{ PersonalSteps = @('Rename-Machine', 'Install-MissingPersonalTool') }

		Bootstrap

		Should -Invoke Rename-Machine -Times 1 -Exactly
		Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -like "*Install-MissingPersonalTool*" }
	}

	It "treats an empty PersonalSteps list as a no-op" {
		$global:MachineType = 'Test'
		$global:Configuration.BootstrapConfig = @{ PersonalSteps = @() }

		Bootstrap

		Should -Invoke Write-LogWarning -Times 0 -ParameterFilter { $Message -like "*Personal step*" }
	}

	It "runs hashtable PersonalSteps whose Machine scope covers the machine type and skips the rest" {
		$global:MachineType = 'Test'
		$global:Configuration.ValidMachineTypes = @('PC', 'Laptop', 'Work', 'Test')
		# Rename-Machine / Start-Win11Debloat are real exported commands that plain Bootstrap
		# (no -WithInitialSetup) never calls, so they cleanly probe which entries actually ran.
		$global:Configuration.BootstrapConfig = @{
			PersonalSteps = @(
				@{ Function = 'Rename-Machine'; Machine = 'Test' },
				@{ Function = 'Start-Win11Debloat'; Machine = 'PC/Laptop' }
			)
		}

		Bootstrap

		Should -Invoke Rename-Machine -Times 1 -Exactly
		Should -Invoke Start-Win11Debloat -Times 0
		Should -Invoke Write-LogWarning -Times 0 -ParameterFilter { $Message -like "*Personal step*" }
	}

	It "reports invalid machine tokens in a personal step scope and does not run the step" {
		$global:MachineType = 'Test'
		$global:Configuration.ValidMachineTypes = @('PC', 'Laptop', 'Work', 'Test')
		$global:Configuration.BootstrapConfig = @{ PersonalSteps = @(@{ Function = 'Rename-Machine'; Machine = 'Tset' }) }

		Bootstrap

		Should -Invoke Rename-Machine -Times 0
		Should -Invoke Write-LogError -Times 1 -Exactly -ParameterFilter { $Message -like "*Tset*" }
	}

	It "warns on a personal step entry without a Function name" {
		$global:MachineType = 'Test'
		$global:Configuration.BootstrapConfig = @{ PersonalSteps = @(@{ Machine = 'All' }) }

		Bootstrap

		Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -like "*no Function name*" }
	}
}
