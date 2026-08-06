#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Configure-WSL.ps1"
}

Describe "Configure-WSL" {
	BeforeEach {
		$script:Configuration = [PSCustomObject]@{
			DefaultWSLDistribution = "Ubuntu"
			DefaultWSLUsername     = ""
		}
		$script:installed = $true

		Mock Test-AdminPrivileges { }
		Mock Test-WSLEnabled { $true }
		Mock Test-WSLDistributionInstalled { $script:installed }
		Mock Enable-WindowsOptionalFeature { }
		Mock Initialize-WSLEnvironment { }
		Mock SymbolicLinkMaker { }
		Mock Configure-WSLSSH { }
		# Track (un)install state so the installed-check reflects what the function did.
		Mock wsl {
			if ($args -contains '--unregister') { $script:installed = $false }
			if ($args -contains '--install') { $script:installed = $true }
		}
		Mock Write-Host { }
	}

	It "skips install actions when WSL and distro are already present" {
		{ Configure-WSL } | Should -Not -Throw

		Should -Invoke Enable-WindowsOptionalFeature -Times 0
		Should -Invoke wsl -ParameterFilter { $args -contains '--install' } -Times 0
		Should -Invoke wsl -ParameterFilter { $args -contains '--unregister' } -Times 0
	}

	It "pins the configured distro as the WSL default" {
		{ Configure-WSL } | Should -Not -Throw

		Should -Invoke wsl -ParameterFilter { $args -contains '--set-default' -and $args -contains 'Ubuntu' } -Times 1 -Exactly
	}

	It "runs the interactive first-launch setup when no username is configured" {
		$script:installed = $false

		{ Configure-WSL } | Should -Not -Throw

		Should -Invoke wsl -ParameterFilter { $args -contains '--install' } -Times 1 -Exactly
		# Bare `wsl` launch for the interactive account wizard
		Should -Invoke wsl -ParameterFilter { $args.Count -eq 0 } -Times 1 -Exactly
		Should -Invoke wsl -ParameterFilter { $args -contains 'useradd' } -Times 0
	}

	It "creates the configured user non-interactively and sets it as default" {
		$script:installed = $false
		$script:Configuration.DefaultWSLUsername = "ivan"

		{ Configure-WSL } | Should -Not -Throw

		Should -Invoke wsl -ParameterFilter { $args -contains 'useradd' -and $args -contains 'ivan' } -Times 1 -Exactly
		Should -Invoke wsl -ParameterFilter { $args -contains 'passwd' } -Times 1 -Exactly
		Should -Invoke wsl -ParameterFilter { $args -contains '--terminate' } -Times 1 -Exactly
		# No interactive first-launch wizard
		Should -Invoke wsl -ParameterFilter { $args.Count -eq 0 } -Times 0
	}

	It "lowercases a mixed-case configured username" {
		$script:installed = $false
		$script:Configuration.DefaultWSLUsername = "Ivan"

		{ Configure-WSL } | Should -Not -Throw

		Should -Invoke wsl -ParameterFilter { $args -contains 'useradd' -and $args -ccontains 'ivan' } -Times 1 -Exactly
	}

	It "-Force unregisters the installed distro and redoes the whole setup" {
		$script:Configuration.DefaultWSLUsername = "ivan"

		{ Configure-WSL -Force } | Should -Not -Throw

		Should -Invoke wsl -ParameterFilter { $args -contains '--unregister' } -Times 1 -Exactly
		Should -Invoke wsl -ParameterFilter { $args -contains '--install' } -Times 1 -Exactly
		Should -Invoke wsl -ParameterFilter { $args -contains 'useradd' } -Times 1 -Exactly
		Should -Invoke Initialize-WSLEnvironment -Times 1 -Exactly
		Should -Invoke SymbolicLinkMaker -Times 1 -Exactly -ParameterFilter { $Scope -eq 'WSL' }
		Should -Invoke Configure-WSLSSH -Times 1 -Exactly
	}

	It "does not chain the environment, symlink, and SSH steps without -Force" {
		$script:installed = $false

		{ Configure-WSL } | Should -Not -Throw

		Should -Invoke Initialize-WSLEnvironment -Times 0
		Should -Invoke SymbolicLinkMaker -Times 0
		Should -Invoke Configure-WSLSSH -Times 0
	}
}
