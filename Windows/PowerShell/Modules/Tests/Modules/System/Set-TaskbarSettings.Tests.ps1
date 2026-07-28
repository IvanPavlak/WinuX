#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Set-TaskbarSettings.ps1"
}

Describe "Set-TaskbarSettings" {
	BeforeEach {
		$script:Configuration = [PSCustomObject]@{
			TaskbarSettings = $null
		}
		Mock Write-Host { }
		Mock Write-LogTitle { }
		Mock Write-LogStep { }
		Mock Write-LogSuccess { }
		Mock Write-LogWarning { }
		Mock Write-LogError { }
		Mock Restart-Explorer { }

		# Explorer's StuckRects3 blob as a real machine reports it: 48 bytes, auto-hide off
		# (byte 8 = 0x02). Tests that need it on flip that byte before invoking.
		$script:StuckRects = [byte[]](@(0x30, 0x00, 0x00, 0x00, 0xFE, 0xFF, 0xFF, 0xFF, 0x02) + @(0) * 39)
	}

	Context "Configuration guards" {
		It "returns without side effects when TaskbarSettings is missing from configuration" {
			Mock Set-ItemProperty { }

			{ Set-TaskbarSettings } | Should -Not -Throw

			Should -Invoke Write-LogTitle -Times 1
			Should -Invoke Write-LogWarning -Times 1
			Should -Invoke Set-ItemProperty -Times 0
			Should -Invoke Restart-Explorer -Times 0
		}

		It "returns without side effects when TaskbarSettings is empty" {
			$script:Configuration = [PSCustomObject]@{ TaskbarSettings = @{} }
			Mock Set-ItemProperty { }

			{ Set-TaskbarSettings } | Should -Not -Throw

			Should -Invoke Write-LogWarning -Times 1
			Should -Invoke Set-ItemProperty -Times 0
			Should -Invoke Restart-Explorer -Times 0
		}

		It "returns without side effects when TaskbarSettings is not a hashtable" {
			$script:Configuration = [PSCustomObject]@{ TaskbarSettings = "Centre" }
			Mock Set-ItemProperty { }

			{ Set-TaskbarSettings } | Should -Not -Throw

			Should -Invoke Write-LogWarning -Times 1
			Should -Invoke Set-ItemProperty -Times 0
		}

		It "warns and applies nothing when only unknown keys are configured" {
			$script:Configuration = [PSCustomObject]@{ TaskbarSettings = @{ NotARealControl = $true } }
			Mock Set-ItemProperty { }

			{ Set-TaskbarSettings } | Should -Not -Throw

			# One warning for the unknown key, one for having nothing valid left
			Should -Invoke Write-LogWarning -Times 2
			Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -like "*NotARealControl*" }
			Should -Invoke Set-ItemProperty -Times 0
			Should -Invoke Restart-Explorer -Times 0
		}
	}

	Context "Value validation" {
		It "skips a toggle configured with a non-boolean value" {
			$script:Configuration = [PSCustomObject]@{ TaskbarSettings = @{ TaskView = "Off" } }
			Mock Set-ItemProperty { }

			{ Set-TaskbarSettings } | Should -Not -Throw

			Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -like "*TaskView*expects*" }
			Should -Invoke Set-ItemProperty -Times 0
			Should -Invoke Restart-Explorer -Times 0
		}

		It "skips a dropdown configured with an unknown token and lists the valid ones" {
			$script:Configuration = [PSCustomObject]@{ TaskbarSettings = @{ Search = "Nonsense" } }
			Mock Set-ItemProperty { }

			{ Set-TaskbarSettings } | Should -Not -Throw

			Should -Invoke Write-LogWarning -Times 1 -ParameterFilter {
				$Message -like "*Search*Nonsense*" -and $Message -like "*SearchIconAndLabel*"
			}
			Should -Invoke Set-ItemProperty -Times 0
		}

		It "skips a dropdown configured with a boolean" {
			$script:Configuration = [PSCustomObject]@{ TaskbarSettings = @{ TaskbarAlignment = $true } }
			Mock Set-ItemProperty { }

			{ Set-TaskbarSettings } | Should -Not -Throw

			Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -like "*TaskbarAlignment*" }
			Should -Invoke Set-ItemProperty -Times 0
		}

		It "resolves a dropdown token case insensitively and reports the canonical spelling" {
			$script:Configuration = [PSCustomObject]@{ TaskbarSettings = @{ Search = "searchbox" } }
			Mock Get-ItemPropertyValue { 0 }
			Mock Test-Path { $true }
			Mock Set-ItemProperty { }

			{ Set-TaskbarSettings } | Should -Not -Throw

			Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter { $Name -eq "SearchboxTaskbarMode" -and $Value -eq 2 }
			Should -Invoke Write-LogStep -Times 1 -ParameterFilter { $Message -like "*Search*SearchBox*" }
		}

		It "accepts the American spelling Center for TaskbarAlignment" {
			$script:Configuration = [PSCustomObject]@{ TaskbarSettings = @{ TaskbarAlignment = "Center" } }
			Mock Get-ItemPropertyValue { 0 }
			Mock Test-Path { $true }
			Mock Set-ItemProperty { }

			{ Set-TaskbarSettings } | Should -Not -Throw

			Should -Invoke Write-LogWarning -Times 0
			Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter { $Name -eq "TaskbarAl" -and $Value -eq 1 }
		}
	}

	Context "Idempotency" {
		It "skips applying when every configured control already matches" {
			$script:Configuration = [PSCustomObject]@{
				TaskbarSettings = @{
					TaskView = $false
					Search   = "Hide"
				}
			}
			Mock Get-ItemPropertyValue { 0 }
			Mock Set-ItemProperty { }

			{ Set-TaskbarSettings } | Should -Not -Throw

			Should -Invoke Set-ItemProperty -Times 0
			Should -Invoke Restart-Explorer -Times 0
			Should -Invoke Write-LogWarning -Times 1
			Should -Invoke Write-LogSuccess -Times 0
		}

		It "reports already-matching controls as yellow skipped rows while applying the rest" {
			$script:Configuration = [PSCustomObject]@{
				TaskbarSettings = @{
					TaskView                = $false
					ShowBadgesOnTaskbarApps = $true
				}
			}
			Mock Get-ItemPropertyValue { 0 }
			Mock Test-Path { $true }
			Mock Set-ItemProperty { }

			{ Set-TaskbarSettings } | Should -Not -Throw

			# TaskView already off => yellow skipped row, no write
			Should -Invoke Write-LogStep -Times 1 -ParameterFilter { $Style -eq "Warning" -and $Message -like "*TaskView*skipped*" }
			# Badges currently off but configured on => green row + registry write
			Should -Invoke Write-LogStep -Times 1 -ParameterFilter { $Style -eq "Success" -and $Message -like "*ShowBadgesOnTaskbarApps*" }
			Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter { $Name -eq "TaskbarBadges" -and $Value -eq 1 }
		}

		It "treats a missing registry value as a mismatch and writes it explicitly" {
			$script:Configuration = [PSCustomObject]@{ TaskbarSettings = @{ SelectFarCornerToShowDesktop = $true } }
			Mock Get-ItemPropertyValue { throw "Property TaskbarSd does not exist" }
			Mock Test-Path { $true }
			Mock Set-ItemProperty { }

			{ Set-TaskbarSettings } | Should -Not -Throw

			Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter { $Name -eq "TaskbarSd" -and $Value -eq 1 }
			Should -Invoke Restart-Explorer -Times 1
		}
	}

	Context "Registry writes" {
		It "writes toggles as DWord values and restarts Explorer once for the whole batch" {
			$script:Configuration = [PSCustomObject]@{
				TaskbarSettings = @{
					TaskView                  = $true
					ShowFlashingOnTaskbarApps = $true
					PenMenu                   = $true
				}
			}
			Mock Get-ItemPropertyValue { 0 }
			Mock Test-Path { $true }
			Mock Set-ItemProperty { }

			{ Set-TaskbarSettings } | Should -Not -Throw

			Should -Invoke Set-ItemProperty -Times 3
			Should -Invoke Set-ItemProperty -Times 3 -ParameterFilter { $Type -eq "DWord" }
			Should -Invoke Restart-Explorer -Times 1
			Should -Invoke Write-LogSuccess -Times 1
		}

		It "writes a disabled toggle as its OffValue and renders it as a red row" {
			$script:Configuration = [PSCustomObject]@{ TaskbarSettings = @{ Resume = $false } }
			Mock Get-ItemPropertyValue { 1 }
			Mock Test-Path { $true }
			Mock Set-ItemProperty { }

			{ Set-TaskbarSettings } | Should -Not -Throw

			Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter { $Name -eq "IsResumeAllowed" -and $Value -eq 0 }
			Should -Invoke Write-LogStep -Times 1 -ParameterFilter { $Style -eq "Error" -and $Message -like "*Resume*off*" }
		}

		It "renders a dropdown row in the plain Step style with the selected token" {
			$script:Configuration = [PSCustomObject]@{ TaskbarSettings = @{ TouchKeyboard = "WhenNoKeyboardAttached" } }
			Mock Get-ItemPropertyValue { 0 }
			Mock Test-Path { $true }
			Mock Set-ItemProperty { }

			{ Set-TaskbarSettings } | Should -Not -Throw

			Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter { $Name -eq "TipbandDesiredVisibility" -and $Value -eq 2 }
			Should -Invoke Write-LogStep -Times 1 -ParameterFilter { $Style -eq "Step" -and $Message -like "*TouchKeyboard*WhenNoKeyboardAttached*" }
		}

		It "maps the same token to different values per control" {
			# WhenTaskbarIsFull is 1 for the combine dropdowns but 2 for the button-size dropdown
			$script:Configuration = [PSCustomObject]@{
				TaskbarSettings = @{
					CombineTaskbarButtonsAndHideLabels = "WhenTaskbarIsFull"
					ShowSmallerTaskbarButtons          = "WhenTaskbarIsFull"
				}
			}
			Mock Get-ItemPropertyValue { 0 }
			Mock Test-Path { $true }
			Mock Set-ItemProperty { }

			{ Set-TaskbarSettings } | Should -Not -Throw

			Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter { $Name -eq "TaskbarGlomLevel" -and $Value -eq 1 }
			Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter { $Name -eq "IconSizePreference" -and $Value -eq 2 }
		}

		It "writes each control to its own registry key path" {
			$script:Configuration = [PSCustomObject]@{
				TaskbarSettings = @{
					Search   = "SearchBox"
					PenMenu  = $true
					TaskView = $true
				}
			}
			Mock Get-ItemPropertyValue { 0 }
			Mock Test-Path { $true }
			Mock Set-ItemProperty { }

			{ Set-TaskbarSettings } | Should -Not -Throw

			Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter { $Path -like "*CurrentVersion\Search" -and $Name -eq "SearchboxTaskbarMode" }
			Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter { $Path -like "*CurrentVersion\PenWorkspace" -and $Name -eq "PenWorkspaceButtonDesiredVisibility" }
			Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter { $Path -like "*Explorer\Advanced" -and $Name -eq "ShowTaskViewButton" }
		}

		It "creates the registry key path when it does not exist" {
			$script:Configuration = [PSCustomObject]@{ TaskbarSettings = @{ PenMenu = $true } }
			Mock Get-ItemPropertyValue { throw "Key does not exist" }
			Mock Test-Path { $false }
			Mock New-Item { }
			Mock Set-ItemProperty { }

			{ Set-TaskbarSettings } | Should -Not -Throw

			Should -Invoke New-Item -Times 1 -ParameterFilter { $Path -like "*PenWorkspace" }
			Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter { $Name -eq "PenWorkspaceButtonDesiredVisibility" -and $Value -eq 1 }
		}

		It "continues applying remaining controls when one write fails" {
			$script:Configuration = [PSCustomObject]@{
				TaskbarSettings = @{
					TaskView                = $true
					ShowBadgesOnTaskbarApps = $true
				}
			}
			Mock Get-ItemPropertyValue { 0 }
			Mock Test-Path { $true }
			Mock Set-ItemProperty {
				if ($Name -eq "ShowTaskViewButton") { throw "Access denied" }
			}

			{ Set-TaskbarSettings } | Should -Not -Throw

			Should -Invoke Write-LogError -Times 1 -ParameterFilter { $Message -like "*TaskView*" }
			Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter { $Name -eq "TaskbarBadges" -and $Value -eq 1 }
			Should -Invoke Restart-Explorer -Times 1
			Should -Invoke Write-LogSuccess -Times 1
		}

		It "does not restart Explorer or report success when every write fails" {
			$script:Configuration = [PSCustomObject]@{ TaskbarSettings = @{ TaskView = $true } }
			Mock Get-ItemPropertyValue { 0 }
			Mock Test-Path { $true }
			Mock Set-ItemProperty { throw "Access denied" }

			{ Set-TaskbarSettings } | Should -Not -Throw

			Should -Invoke Write-LogError -Times 1
			Should -Invoke Write-LogWarning -Times 1
			Should -Invoke Restart-Explorer -Times 0
			Should -Invoke Write-LogSuccess -Times 0
		}
	}

	Context "Automatically hide the taskbar" {
		It "sets the auto-hide bit in the StuckRects3 blob and restarts Explorer" {
			$script:Configuration = [PSCustomObject]@{ TaskbarSettings = @{ AutomaticallyHideTheTaskbar = $true } }
			Mock Get-ItemPropertyValue { $script:StuckRects }
			Mock Set-ItemProperty { }

			{ Set-TaskbarSettings } | Should -Not -Throw

			Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
				$Name -eq "Settings" -and $Type -eq "Binary" -and $Value[8] -eq 0x03
			}
			# The restart is what makes it stick: it stops the running Explorer persisting its
			# own in-memory state over the value just written
			Should -Invoke Restart-Explorer -Times 1
			Should -Invoke Write-LogStep -Times 1 -ParameterFilter { $Style -eq "Success" -and $Message -like "*AutomaticallyHideTheTaskbar*on*" }
			Should -Invoke Write-LogSuccess -Times 1
		}

		It "clears the auto-hide bit and renders it as a red row" {
			$script:StuckRects[8] = 0x03
			$script:Configuration = [PSCustomObject]@{ TaskbarSettings = @{ AutomaticallyHideTheTaskbar = $false } }
			Mock Get-ItemPropertyValue { $script:StuckRects }
			Mock Set-ItemProperty { }

			{ Set-TaskbarSettings } | Should -Not -Throw

			Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter { $Name -eq "Settings" -and $Value[8] -eq 0x02 }
			Should -Invoke Write-LogStep -Times 1 -ParameterFilter { $Style -eq "Error" -and $Message -like "*AutomaticallyHideTheTaskbar*off*" }
		}

		It "preserves every other byte of the blob Explorer owns" {
			$script:Configuration = [PSCustomObject]@{ TaskbarSettings = @{ AutomaticallyHideTheTaskbar = $true } }
			Mock Get-ItemPropertyValue { $script:StuckRects }
			Mock Set-ItemProperty { }

			{ Set-TaskbarSettings } | Should -Not -Throw

			Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
				$Value.Length -eq 48 -and $Value[0] -eq 0x30 -and $Value[4] -eq 0xFE -and $Value[7] -eq 0xFF
			}
		}

		It "leaves unrelated bits of the flag byte alone" {
			# A build that carries other flags in byte 8 must keep them
			$script:StuckRects[8] = 0x7A
			$script:Configuration = [PSCustomObject]@{ TaskbarSettings = @{ AutomaticallyHideTheTaskbar = $true } }
			Mock Get-ItemPropertyValue { $script:StuckRects }
			Mock Set-ItemProperty { }

			{ Set-TaskbarSettings } | Should -Not -Throw

			Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter { $Value[8] -eq 0x7B }
		}

		It "reports auto-hide as a yellow skipped row when the bit already matches" {
			$script:StuckRects[8] = 0x03
			$script:Configuration = [PSCustomObject]@{
				TaskbarSettings = @{
					AutomaticallyHideTheTaskbar = $true
					TaskView                    = $true
				}
			}
			Mock Get-ItemPropertyValue { if ($Name -eq "Settings") { $script:StuckRects } else { 0 } }
			Mock Test-Path { $true }
			Mock Set-ItemProperty { }

			{ Set-TaskbarSettings } | Should -Not -Throw

			Should -Invoke Write-LogStep -Times 1 -ParameterFilter { $Style -eq "Warning" -and $Message -like "*AutomaticallyHideTheTaskbar*skipped*" }
			Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter { $Name -eq "ShowTaskViewButton" }
			Should -Invoke Set-ItemProperty -Times 0 -ParameterFilter { $Name -eq "Settings" }
		}

		It "restarts Explorer exactly once when auto-hide changes alongside a DWord control" {
			$script:Configuration = [PSCustomObject]@{
				TaskbarSettings = @{
					AutomaticallyHideTheTaskbar = $true
					TaskView                    = $true
				}
			}
			Mock Get-ItemPropertyValue { if ($Name -eq "Settings") { $script:StuckRects } else { 0 } }
			Mock Test-Path { $true }
			Mock Set-ItemProperty { }

			{ Set-TaskbarSettings } | Should -Not -Throw

			Should -Invoke Set-ItemProperty -Times 2
			Should -Invoke Restart-Explorer -Times 1
		}

		It "skips auto-hide configured with a non-boolean value" {
			$script:Configuration = [PSCustomObject]@{ TaskbarSettings = @{ AutomaticallyHideTheTaskbar = "Yes" } }
			Mock Set-ItemProperty { }

			{ Set-TaskbarSettings } | Should -Not -Throw

			Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -like "*AutomaticallyHideTheTaskbar*expects*" }
			Should -Invoke Set-ItemProperty -Times 0
		}

		It "skips auto-hide rather than fabricating a blob when StuckRects3 cannot be read" {
			$script:Configuration = [PSCustomObject]@{ TaskbarSettings = @{ AutomaticallyHideTheTaskbar = $true } }
			Mock Get-ItemPropertyValue { throw "Cannot find property Settings" }
			Mock Set-ItemProperty { }

			{ Set-TaskbarSettings } | Should -Not -Throw

			Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -like "*AutomaticallyHideTheTaskbar*could not read*StuckRects3*" }
			Should -Invoke Set-ItemProperty -Times 0
			Should -Invoke Restart-Explorer -Times 0
		}
	}
}
