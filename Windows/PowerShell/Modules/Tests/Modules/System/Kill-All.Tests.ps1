#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Kill-All.ps1"

	# Stub all dependent functions with matching parameter signatures
	function Remove-VirtualDesktops { param() }
	function DockerWizard { param([switch]$Stop) }
	function Terminate-AllBrowserProcesses { param([string[]]$Exclude) }
	function Terminate-AllProcessesWithVisibleWindows { param([string[]]$Exclude) }
	function Terminate-AllProcessesByName { param([string[]]$Exclude) }
	function Terminate-WindowsTerminalTabs { param([switch]$IncludeCurrent) }
	function Reload-PowerShellProfile { param() }
}

Describe "Kill-All" {
	BeforeEach {
		Mock Write-Host { }
		Mock Remove-VirtualDesktops { }
		Mock DockerWizard { }
		Mock Terminate-AllBrowserProcesses { }
		Mock Terminate-AllProcessesWithVisibleWindows { }
		Mock Terminate-AllProcessesByName { }
		Mock Terminate-WindowsTerminalTabs { }
		Mock Reload-PowerShellProfile { }
	}

	Context "When called with no parameters" {
		It "Should call all termination functions in order" {
			Kill-All

			Should -Invoke Remove-VirtualDesktops -Times 1 -Exactly
			Should -Invoke DockerWizard -Times 1 -Exactly -ParameterFilter { $Stop }
			Should -Invoke Terminate-AllBrowserProcesses -Times 1 -Exactly
			Should -Invoke Terminate-AllProcessesWithVisibleWindows -Times 1 -Exactly
			Should -Invoke Terminate-AllProcessesByName -Times 1 -Exactly
			Should -Invoke Terminate-WindowsTerminalTabs -Times 1 -Exactly
		}

		It "Should not reload profile by default" {
			Kill-All

			Should -Invoke Reload-PowerShellProfile -Times 0
		}
	}

	Context "When ReloadPowerShellProfile is specified" {
		It "Should reload the profile after termination" {
			Kill-All -ReloadPowerShellProfile

			Should -Invoke Reload-PowerShellProfile -Times 1 -Exactly
		}
	}

	Context "When Exclude patterns are provided" {
		It "Should pass exclude patterns to termination functions" {
			Kill-All -Exclude "*YouTube*"

			Should -Invoke Terminate-AllBrowserProcesses -ParameterFilter { $Exclude -contains "*YouTube*" }
			Should -Invoke Terminate-AllProcessesWithVisibleWindows -ParameterFilter { $Exclude -contains "*YouTube*" }
			Should -Invoke Terminate-AllProcessesByName -ParameterFilter { $Exclude -contains "*YouTube*" }
		}
	}

	Context "When IncludeCurrent is specified" {
		It "Should pass IncludeCurrent to terminal tab termination" {
			Kill-All -IncludeCurrent

			Should -Invoke Terminate-WindowsTerminalTabs -ParameterFilter { $IncludeCurrent -eq $true }
		}
	}

	Context "When virtual desktop cleanup fails" {
		It "Should not emit or report the nested cleanup failure" {
			Mock Remove-VirtualDesktops { $false }

			$result = Kill-All

			$result | Should -BeNullOrEmpty
			Should -Invoke Write-Host -Times 0 -ParameterFilter { $Object -match "Virtual desktop cleanup failed" }
			Should -Invoke Terminate-AllBrowserProcesses -Times 1 -Exactly
			Should -Invoke Terminate-AllProcessesWithVisibleWindows -Times 1 -Exactly
			Should -Invoke Terminate-AllProcessesByName -Times 1 -Exactly
		}
	}
}
