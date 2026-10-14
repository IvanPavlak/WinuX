#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	. (Join-Path $ModuleRoot "System\Functions\Import-TerminalIcons.ps1")
	# Dot-sourced so they exist to Mock even in sessions whose imported modules predate them.
	. (Join-Path $ModuleRoot "System\Functions\Repair-TerminalIconsThemeCache.ps1")
	. (Join-Path $ModuleRoot "Helper\Functions\Restore-ShellPrompt.ps1")
}

Describe "Import-TerminalIcons" {
	BeforeEach {
		Mock Write-LogDebug { }
		Mock Write-LogSuccess { }
		Mock Write-LogError { }
		Mock Restore-ShellPrompt { $true }
		Mock Repair-TerminalIconsThemeCache { @() }
		# Only the Terminal-Icons calls are stubbed; Pester's own module calls pass through.
		Mock Get-Module { [PSCustomObject]@{ Name = "Terminal-Icons" } } -ParameterFilter { $ListAvailable -and $Name -eq "Terminal-Icons" }
		Mock Import-Module { } -ParameterFilter { $Name -eq "Terminal-Icons" }
		$script:quarantined = @(New-Item -ItemType File -Path (Join-Path $TestDrive "devblackops_light_color.xml.corrupt-20260101-000000") -Force)
	}

	It "returns `$false and imports nothing when Terminal-Icons is not installed" {
		Mock Get-Module { $null } -ParameterFilter { $ListAvailable -and $Name -eq "Terminal-Icons" }

		Import-TerminalIcons | Should -BeFalse

		Should -Invoke Import-Module -Times 0 -ParameterFilter { $Name -eq "Terminal-Icons" }
		Should -Invoke Repair-TerminalIconsThemeCache -Times 0
	}

	It "imports the module into the global scope and returns `$true" {
		Import-TerminalIcons | Should -BeTrue

		Should -Invoke Import-Module -Times 1 -Exactly -ParameterFilter { $Name -eq "Terminal-Icons" -and $Global }
		Should -Invoke Repair-TerminalIconsThemeCache -Times 0
		Should -Invoke Write-LogError -Times 0
	}

	It "repairs the theme cache and imports again when the first import throws" {
		$script:attempt = 0
		Mock Import-Module {
			$script:attempt++
			if ($script:attempt -eq 1) { throw "Name attribute for dictionary key is incorrectly specified. Line 212, position 2." }
		} -ParameterFilter { $Name -eq "Terminal-Icons" }
		Mock Repair-TerminalIconsThemeCache { $script:quarantined }

		Import-TerminalIcons | Should -BeTrue

		Should -Invoke Import-Module -Times 2 -Exactly -ParameterFilter { $Name -eq "Terminal-Icons" }
		Should -Invoke Repair-TerminalIconsThemeCache -Times 1 -Exactly
		Should -Invoke Write-LogSuccess -Times 1 -Exactly
		Should -Invoke Write-LogError -Times 0
	}

	It "does not import again when the repair found nothing to move aside, and logs the error" {
		Mock Import-Module { throw "The module to process 'Terminal-Icons.psm1' was not processed" } -ParameterFilter { $Name -eq "Terminal-Icons" }

		Import-TerminalIcons | Should -BeFalse

		Should -Invoke Import-Module -Times 1 -Exactly -ParameterFilter { $Name -eq "Terminal-Icons" }
		Should -Invoke Repair-TerminalIconsThemeCache -Times 1 -Exactly
		Should -Invoke Write-LogError -Times 1 -Exactly -ParameterFilter { $null -ne $Exception }
		Should -Invoke Write-LogSuccess -Times 0
	}

	It "logs the error and returns `$false when the import still fails after the repair" {
		Mock Import-Module { throw "still broken" } -ParameterFilter { $Name -eq "Terminal-Icons" }
		Mock Repair-TerminalIconsThemeCache { $script:quarantined }

		Import-TerminalIcons | Should -BeFalse

		Should -Invoke Import-Module -Times 2 -Exactly -ParameterFilter { $Name -eq "Terminal-Icons" }
		Should -Invoke Write-LogError -Times 1 -Exactly -ParameterFilter { $Message -match "still fails" }
	}

	Context "-RedrawPrompt" {
		It "does not redraw the prompt when the import went quietly" {
			$null = Import-TerminalIcons -RedrawPrompt

			Should -Invoke Restore-ShellPrompt -Times 0
		}

		It "redraws the prompt once something was printed" {
			Mock Import-Module { throw "broken" } -ParameterFilter { $Name -eq "Terminal-Icons" }

			$null = Import-TerminalIcons -RedrawPrompt

			Should -Invoke Restore-ShellPrompt -Times 1 -Exactly
		}

		It "never redraws without the switch" {
			Mock Import-Module { throw "broken" } -ParameterFilter { $Name -eq "Terminal-Icons" }

			$null = Import-TerminalIcons

			Should -Invoke Restore-ShellPrompt -Times 0
		}
	}
}
