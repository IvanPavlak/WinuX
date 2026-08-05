#Requires -Modules Pester

BeforeAll {
	$script:OriginalConfiguration = $global:Configuration
	$script:OriginalMachineType = $global:MachineType

	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Kill-All.ps1"
	# Kill-All resolves its step map through the real Resolve-KillAllSteps, so
	# the config/override behavior asserted below exercises the actual resolver.
	# Resolve-KillAllSteps delegates the resolution loop to the shared Resolve-Steps;
	# dot-source it too so the loop runs in this scope where the log mocks apply.
	. "$ModuleRoot\Helper\Functions\Resolve-Steps.ps1"
	. "$FunctionsPath\Resolve-KillAllSteps.ps1"

	# Stub all dependent functions with matching parameter signatures
	function Remove-VirtualDesktops { param() }
	function DockerWizard { param([switch]$Stop) }
	function Terminate-AllBrowserProcesses { param([string[]]$Exclude) }
	function Terminate-AllProcessesWithVisibleWindows { param([string[]]$Exclude) }
	function Terminate-AllProcessesByName { param([string[]]$Exclude) }
	function Terminate-WindowsTerminalTabs { param([switch]$IncludeCurrent) }
	function Reload-PowerShellProfile { param() }
	# Kill-All finishes by putting the terminal back where it belongs, which is wanted in real use
	# and emphatically not while the suite runs. Unstubbed, both of these resolved to the real
	# Window/Workflow functions: Center-Terminal hands Center-Windows the live WindowsTerminal
	# process (physically moving and resizing the developer's own terminal), and Focus-TerminalTab
	# calls AppActivate on it (stealing focus). Every default Kill-All call below reached both.
	function Center-Terminal { param() }
	function Focus-TerminalTab { param([string]$TargetTitle, [switch]$Quiet) }
	function Save-WorkspaceState {
		param($Workspace, $ExistingWindowHandles, $ExistingTerminalTabs, $DesktopOffset, [switch]$Alongside, [switch]$AdoptUnclaimed, [switch]$Append, $Entry, $StatePath)
	}
}

AfterAll {
	$global:Configuration = $script:OriginalConfiguration
	$global:MachineType = $script:OriginalMachineType
}

Describe "Kill-All" {
	BeforeEach {
		# Fresh baseline with no KillAll section - built-in defaults apply unless a
		# test opts a step out/in. Originals are restored in AfterAll.
		$global:Configuration = @{}
		$global:MachineType = "Test"

		Mock Write-Host { }
		Mock Write-LogWarning { }
		Mock Remove-VirtualDesktops { }
		Mock DockerWizard { }
		Mock Terminate-AllBrowserProcesses { }
		Mock Terminate-AllProcessesWithVisibleWindows { }
		Mock Terminate-AllProcessesByName { }
		Mock Terminate-WindowsTerminalTabs { }
		Mock Reload-PowerShellProfile { }
		Mock Center-Terminal { }
		Mock Focus-TerminalTab { }
		Mock Save-WorkspaceState { }
	}

	Context "Open-workspace tracker" {
		It "Should clear it, since nothing a workspace opened survives a full run" {
			# Left populated, Close-Workspace would keep offering workspaces that are long gone and
			# then report every one of their windows as already closed.
			Kill-All

			Should -Invoke Save-WorkspaceState -Times 1 -Exactly -ParameterFilter { @($Entry).Count -eq 0 }
		}

		It "Should clear it before the terminal tabs are terminated" {
			# -IncludeCurrent ends the process, so anything left until after that never runs.
			$script:order = @()
			Mock Save-WorkspaceState { $script:order += 'tracker' }
			Mock Terminate-WindowsTerminalTabs { $script:order += 'tabs' }

			Kill-All -IncludeCurrent

			$script:order | Should -Be @('tracker', 'tabs')
		}

		It "Should keep it when the visible-window sweep is skipped" {
			# Those windows are still on screen and still closable, so discarding the only record of
			# who owns them would be a capability loss, not a tidy-up.
			Kill-All -Skip VisibleWindows

			Should -Invoke Save-WorkspaceState -Times 0
		}

		It "Should keep it when the browser sweep is skipped" {
			Kill-All -Skip Browsers

			Should -Invoke Save-WorkspaceState -Times 0
		}

		It "Should keep it when the named-process sweep is skipped" {
			Kill-All -Skip NamedProcesses

			Should -Invoke Save-WorkspaceState -Times 0
		}

		It "Should keep it when config disables one of those steps" {
			$global:Configuration.KillAll = @{ Steps = @{ VisibleWindows = $false } }

			Kill-All

			Should -Invoke Save-WorkspaceState -Times 0
		}

		It "Should still clear it when an unrelated step is skipped" {
			Kill-All -Skip Docker

			Should -Invoke Save-WorkspaceState -Times 1 -Exactly
		}
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
			# Asserted rather than merely mocked away: restoring the terminal is the visible end
			# of a real Kill-All, and neither call had any coverage at all until now.
			Should -Invoke Center-Terminal -Times 1 -Exactly
			Should -Invoke Focus-TerminalTab -Times 1 -Exactly
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

		It "Should reload the profile even when config disables the step" {
			$global:Configuration.KillAll = @{ Steps = @{ ReloadProfile = $false } }

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

		It "Should not restore a terminal it just closed" {
			Kill-All -IncludeCurrent

			Should -Invoke Center-Terminal -Times 0
			Should -Invoke Focus-TerminalTab -Times 0
		}

		It "Should not restore a terminal it just closed even when Include forces the steps" {
			Kill-All -IncludeCurrent -Include CenterTerminal, FocusTerminal

			Should -Invoke Center-Terminal -Times 0
			Should -Invoke Focus-TerminalTab -Times 0
		}
	}

	Context "When KillAll config disables steps" {
		It "Should skip only the Docker step when Steps.Docker is false" {
			$global:Configuration.KillAll = @{ Steps = @{ Docker = $false } }

			Kill-All

			Should -Invoke DockerWizard -Times 0
			Should -Invoke Remove-VirtualDesktops -Times 1 -Exactly
			Should -Invoke Terminate-AllBrowserProcesses -Times 1 -Exactly
			Should -Invoke Terminate-AllProcessesWithVisibleWindows -Times 1 -Exactly
			Should -Invoke Terminate-AllProcessesByName -Times 1 -Exactly
			Should -Invoke Terminate-WindowsTerminalTabs -Times 1 -Exactly
			Should -Invoke Center-Terminal -Times 1 -Exactly
			Should -Invoke Focus-TerminalTab -Times 1 -Exactly
		}

		It "Should skip terminal tab termination when Steps.TerminalTabs is false" {
			$global:Configuration.KillAll = @{ Steps = @{ TerminalTabs = $false } }

			Kill-All

			Should -Invoke Terminate-WindowsTerminalTabs -Times 0
		}

		It "Should skip centering but still focus when only Steps.CenterTerminal is false" {
			$global:Configuration.KillAll = @{ Steps = @{ CenterTerminal = $false } }

			Kill-All

			Should -Invoke Center-Terminal -Times 0
			Should -Invoke Focus-TerminalTab -Times 1 -Exactly
		}

		It "Should skip focusing but still center when only Steps.FocusTerminal is false" {
			$global:Configuration.KillAll = @{ Steps = @{ FocusTerminal = $false } }

			Kill-All

			Should -Invoke Center-Terminal -Times 1 -Exactly
			Should -Invoke Focus-TerminalTab -Times 0
		}

		It "Should reload the profile without the switch when Steps.ReloadProfile is true" {
			$global:Configuration.KillAll = @{ Steps = @{ ReloadProfile = $true } }

			Kill-All

			Should -Invoke Reload-PowerShellProfile -Times 1 -Exactly
		}
	}

	Context "When steps use machine-type hashtables" {
		It "Should skip the step when the machine type maps to false" {
			$global:MachineType = "Test"
			$global:Configuration.KillAll = @{ Steps = @{ Docker = @{ Default = $true; Test = $false } } }

			Kill-All

			Should -Invoke DockerWizard -Times 0
		}

		It "Should fall back to Default when the machine type is not mapped" {
			$global:MachineType = "Laptop"
			$global:Configuration.KillAll = @{ Steps = @{ Docker = @{ Default = $true; Test = $false } } }

			Kill-All

			Should -Invoke DockerWizard -Times 1 -Exactly
		}

		It "Should use the built-in default when neither the machine type nor Default is mapped" {
			$global:MachineType = "Laptop"
			$global:Configuration.KillAll = @{ Steps = @{ Docker = @{ Test = $false } } }

			Kill-All

			Should -Invoke DockerWizard -Times 1 -Exactly
		}
	}

	Context "When Skip and Include override config" {
		It "Should skip a config-enabled step with -Skip" {
			Kill-All -Skip Docker

			Should -Invoke DockerWizard -Times 0
			Should -Invoke Terminate-AllBrowserProcesses -Times 1 -Exactly
		}

		It "Should skip multiple steps with -Skip" {
			Kill-All -Skip Docker, Browsers

			Should -Invoke DockerWizard -Times 0
			Should -Invoke Terminate-AllBrowserProcesses -Times 0
			Should -Invoke Terminate-AllProcessesWithVisibleWindows -Times 1 -Exactly
		}

		It "Should run a config-disabled step with -Include" {
			$global:Configuration.KillAll = @{ Steps = @{ Docker = $false } }

			Kill-All -Include Docker

			Should -Invoke DockerWizard -Times 1 -Exactly -ParameterFilter { $Stop }
		}

		It "Should let -Skip win and warn when a step is in both -Skip and -Include" {
			Kill-All -Skip Docker -Include Docker

			Should -Invoke DockerWizard -Times 0
			Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -match "Docker" }
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
