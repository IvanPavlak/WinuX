#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Initialize-WorkspaceWindowLayoutRerun.ps1"
	# The rerun-state mirror, dot-sourced so the BeforeEach below can mock it. These two are the
	# only calls in the whole function that reach outside the process, and each User-scope write
	# they make broadcasts WM_SETTINGCHANGE to every top-level window and blocks on the slowest
	# to answer - which cost this file ~95 of its ~98 seconds. Nothing here asserts on the
	# mirror (every rerun-marker assertion below reads Process scope, which stays real), and the
	# mirror's own behavior is covered by Get-WorkspaceRerunMirror.Tests.ps1 and
	# Set-WorkspaceRerunMirror.Tests.ps1.
	. "$FunctionsPath\Get-WorkspaceRerunMirror.ps1"
	. "$FunctionsPath\Set-WorkspaceRerunMirror.ps1"
	# The real layout-set resolver, not a mock: which folder and file suffix a workspace resolves
	# to is part of the behavior under test here. Its display measurement comes along so the
	# small-display path stays driven by the Get-MonitorInfo mock.
	. "$FunctionsPath\Test-SmallPrimaryDisplay.ps1"
	. "$FunctionsPath\Get-LayoutMachineType.ps1"
	. "$FunctionsPath\Get-CurrentLayout.ps1"
	. "$FunctionsPath\Save-CurrentLayout.ps1"
	. "$FunctionsPath\Set-WorkspaceWindowLayout.ps1"
	# Mocked below, dot-sourced so Pester builds the mocks from the CURRENT parameter blocks
	# (-OnDesktopReady, -DesktopNumbers, -ZoneReset, -CandidateWindowHandles, ...) whatever
	# module version the session has loaded.
	. "$FunctionsPath\Wait-ForWorkspaceWindows.ps1"
	. "$FunctionsPath\Set-WindowLayouts.ps1"
	. "$FunctionsPath\Resize-PositionedWindows.ps1"
	. "$FunctionsPath\Snap-AllWindows.ps1"

	function Remove-PositionedWindowHandles { }
	function Verify-WindowPlacement { $true }
	# Stub so Mock can attach without loading the whole Window module; the real
	# validator has its own suite (Test-FancyZonesConfiguration.Tests.ps1).
	function Test-FancyZonesConfiguration { [PSCustomObject]@{ Valid = $true; Errors = @(); Warnings = @() } }

	# VirtualDesktop cmdlets come from an optional external module absent on CI runners.
	# Stub the ones these tests mock so Mock can attach (no-op where the real module exists).
	if (-not (Get-Command Get-DesktopList -ErrorAction SilentlyContinue)) {
		function Get-DesktopList { [CmdletBinding()] param() }
		function Switch-Desktop { [CmdletBinding()] param($Desktop) }
	}
}

Describe "Set-WorkspaceWindowLayout" {
	BeforeEach {
		Mock Write-Host { }
		Mock Loading-Spinner { }
		Mock Get-MonitorInfo { @() }
		Mock DetermineMachineType { 'PC' }
		Mock Test-Path { $false }
		Mock Import-PowerShellDataFile { @{} }
		Mock Apply-FancyZones { }
		Mock Get-WindowHandle { @() }
		Mock Ensure-WindowsFormsLoaded { }
		Mock Add-Type { }
		Mock Set-WindowLayouts { }
		Mock Get-CurrentLayout { $null }
		Mock Save-CurrentLayout { }
		Mock Wait-ForWorkspaceWindows { @() }
		Mock Resize-PositionedWindows { @{ FailedWindows = @() } }
		Mock Confirm-WorkspaceWindowPositions { @{ Success = $true } }
		Mock Initialize-WorkspaceWindowLayoutRerun { $true }
		Mock Start-FancyZones { $true }
		Mock ReRun-LastCommand { }
		# See the dot-source note above: the out-of-process mirror only, never the Process-scope
		# markers the assertions below read.
		Mock Get-WorkspaceRerunMirror { $null }
		Mock Set-WorkspaceRerunMirror { }
		Mock Resize-Windows { }
		Mock Move-WindowToVirtualDesktop { $true }
		Mock Remove-VirtualDesktops { $true }
		Mock Ensure-VirtualDesktops { $true }
		Mock Snap-AllWindows { $true }
		Mock Remove-PositionedWindowHandles { }
		Mock Stop-Process { }
		Mock Visualize-Layouts { }
		Mock Switch-Desktop { }
		Mock Get-MonitorSpecs { @{} }
		Mock Set-Location { }
		Mock Get-Command { $null }
		Mock Start-Sleep { }
		Mock Test-FancyZonesConfiguration { [PSCustomObject]@{ Valid = $true; Errors = @(); Warnings = @() } }

		$script:MachineSpecificPaths = @{
			Projects = @{
				Self = @{
					Layouts = 'C:\Layouts'
				}
			}
		}

		$global:Configuration = @{
			SimpleLayoutWorkspaces = @()
		}

		# The function reads the layout-resolution keys through the unqualified $Configuration,
		# which resolves to the SCRIPT scope here - and an It block that sets it leaks the value
		# into every later test in this file. Reset it per test so layout-set overrides and
		# small-display settings stay hermetic.
		$script:Configuration = @{
			SimpleLayoutWorkspaces = @()
		}

		$env:WORKSPACE_RERUN_COUNT = $null
		# Rerun state is mirrored at User scope ("value|timestamp", 10-min TTL) to survive
		# terminal respawns - clear BOTH scopes so tests stay hermetic and never leak real
		# User-scope environment values onto the machine running the suite.
		#
		# The User-scope clear is read-guarded. Writing a User-scope variable broadcasts
		# WM_SETTINGCHANGE to every top-level window and blocks on the slowest one (~700ms a
		# call here), while the matching read is a plain registry lookup (~2ms). Clearing a
		# variable that is already absent is a no-op, so the guard leaves the end state
		# identical and takes ~54s off the suite. Same read-before-clear shape the function
		# under test uses for its own mirror (Set-WorkspaceWindowLayout.ps1:151-153).
		foreach ($rerunVar in 'WORKSPACE_RERUN_COUNT', 'WORKSPACE_WINDOW_ONLY_RETRY', 'WORKSPACE_WINDOW_ONLY_RETRY_TITLE', 'WORKSPACE_WINDOW_ONLY_RETRY_PROCESS') {
			[Environment]::SetEnvironmentVariable($rerunVar, $null, 'Process')
			if (-not [string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($rerunVar, 'User'))) {
				[Environment]::SetEnvironmentVariable($rerunVar, $null, 'User')
			}
		}

		# The real Snap-AllWindows resets this at its start; the global mock does not, so a
		# failed result would otherwise leak between tests and drive the in-process retry
		# loop through all its attempts in unrelated tests.
		$script:LastSnapAllWindowsResult = [PSCustomObject]@{ SnappedCount = 0; FailedWindows = @() }
	}

	AfterAll {
		# Leave the machine clean: tests exercise the escalation path, which persists rerun
		# state at User scope. Read-guarded for the same reason as the BeforeEach clear above.
		foreach ($rerunVar in 'WORKSPACE_RERUN_COUNT', 'WORKSPACE_WINDOW_ONLY_RETRY', 'WORKSPACE_WINDOW_ONLY_RETRY_TITLE', 'WORKSPACE_WINDOW_ONLY_RETRY_PROCESS') {
			[Environment]::SetEnvironmentVariable($rerunVar, $null, 'Process')
			if (-not [string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($rerunVar, 'User'))) {
				[Environment]::SetEnvironmentVariable($rerunVar, $null, 'User')
			}
		}
	}

	It "aborts the open when FancyZones configuration errors affect this workspace's layouts" {
		Mock Test-Path { $true }
		Mock Import-PowerShellDataFile {
			@{
				Monitors = @{ Primary = @{ VirtualDesktopLayouts = @{ 1 = "One" } } }
				Layout   = @(@{ ProcessName = "Code"; Zone = "Left"; Monitor = "Primary"; DesktopNumber = 1 })
			}
		}
		Mock Test-FancyZonesConfiguration {
			[PSCustomObject]@{
				Valid    = $false
				Errors   = @([PSCustomObject]@{ Layout = "One"; Message = "Layout 'One': broken for test" })
				Warnings = @()
			}
		}
		Mock Write-LogError { }

		Set-WorkspaceWindowLayout -WorkspaceName "TestWorkspace"

		Should -Invoke Apply-FancyZones -Times 0
		Should -Invoke Write-LogError -ParameterFilter { $Message -match "aborting layout" }
	}

	It "continues the open when FancyZones configuration errors only touch unrelated layouts" {
		Mock Test-Path { $true }
		Mock Import-PowerShellDataFile {
			@{
				Monitors = @{ Primary = @{ VirtualDesktopLayouts = @{ 1 = "One" } } }
				Layout   = @(@{ ProcessName = "Code"; Zone = "Left"; Monitor = "Primary"; DesktopNumber = 1 })
			}
		}
		Mock Test-FancyZonesConfiguration {
			[PSCustomObject]@{
				Valid    = $false
				Errors   = @([PSCustomObject]@{ Layout = "SomeOtherLayout"; Message = "Layout 'SomeOtherLayout': broken for test" })
				Warnings = @()
			}
		}
		Mock Write-LogError { }

		Set-WorkspaceWindowLayout -WorkspaceName "TestWorkspace"

		Should -Invoke Write-LogError -Times 0 -ParameterFilter { $Message -match "aborting layout" }
	}

	It "uses Machine machine-specific workspace layout when primary monitor is small" {
		$script:Configuration = @{ SmallDisplayMachineType = 'Machine' }
		Mock Get-MonitorInfo {
			@([PSCustomObject]@{ IsPrimary = $true; Width = 1920; Height = 1080 })
		}
		Mock Test-Path {
			$Path -eq 'C:\Layouts\Machine\MyWorkspace_Machine.psd1'
		}

		Set-WorkspaceWindowLayout -WorkspaceName 'MyWorkspace'

		Should -Invoke DetermineMachineType -Times 1 -Exactly
		Should -Invoke Import-PowerShellDataFile -Times 1 -Exactly -ParameterFilter { $Path -eq 'C:\Layouts\Machine\MyWorkspace_Machine.psd1' }
	}

	It "reads layouts from the configured override layout set instead of the machine's own folder" {
		$script:Configuration = @{ LayoutMachineTypeOverrides = @{ PC = 'Temp' } }
		Mock Test-Path {
			$Path -eq 'C:\Layouts\Temp\MyWorkspace_Temp.psd1'
		}

		Set-WorkspaceWindowLayout -WorkspaceName 'MyWorkspace'

		# The override replaces the machine type in BOTH halves of the path - folder and suffix.
		Should -Invoke Import-PowerShellDataFile -Times 1 -Exactly -ParameterFilter { $Path -eq 'C:\Layouts\Temp\MyWorkspace_Temp.psd1' }
	}

	It "prefers the override layout set over the small-display layout set" {
		# Both candidate files "exist", so the assertion proves which one was chosen rather than
		# which one happened to be present.
		$script:Configuration = @{
			LayoutMachineTypeOverrides = @{ PC = 'Temp' }
			SmallDisplayMachineType    = 'Machine'
		}
		Mock Get-MonitorInfo {
			@([PSCustomObject]@{ IsPrimary = $true; Width = 1920; Height = 1080 })
		}
		Mock Test-Path { $true }

		Set-WorkspaceWindowLayout -WorkspaceName 'MyWorkspace'

		Should -Invoke Import-PowerShellDataFile -Times 1 -Exactly -ParameterFilter { $Path -eq 'C:\Layouts\Temp\MyWorkspace_Temp.psd1' }
	}

	It "ignores an empty override entry and uses the machine's own layout set" {
		$script:Configuration = @{ LayoutMachineTypeOverrides = @{ PC = '' } }
		Mock Test-Path { $true }

		Set-WorkspaceWindowLayout -WorkspaceName 'MyWorkspace'

		Should -Invoke Import-PowerShellDataFile -Times 1 -Exactly -ParameterFilter { $Path -eq 'C:\Layouts\PC\MyWorkspace_PC.psd1' }
	}

	It "returns before importing when explicit layout path does not exist" {
		Mock Test-Path { $false }

		Set-WorkspaceWindowLayout -LayoutPath 'C:\Missing\Layout.psd1'

		Should -Invoke Import-PowerShellDataFile -Times 0
	}

	It "skips desktop reset when current desktop count already matches required count" {
		Mock Test-Path { $true }
		Mock Import-PowerShellDataFile {
			@{
				Layout   = @(
					@{ ProcessName = 'Code'; WindowTitle = '*'; DesktopNumber = 1 }
				)
				Monitors = @{
					MonitorA = @{
						VirtualDesktopLayouts = @{
							1 = 'One'
							2 = 'Two'
						}
					}
				}
			}
		}
		Mock Get-DesktopList { @(0, 1) }
		Mock Wait-ForWorkspaceWindows { @() }
		Mock Verify-WindowPlacement { $true }

		Set-WorkspaceWindowLayout -WorkspaceName 'MyWorkspace'

		Should -Invoke Remove-VirtualDesktops -Times 0
		Should -Invoke Ensure-VirtualDesktops -Times 0 -ParameterFilter { $Count -eq 2 }
		Should -Invoke Apply-FancyZones -Times 1 -Exactly -ParameterFilter { $DesktopCount -eq 2 }
	}

	It "publishes a phase record for Get-WorkspaceLayoutTimings covering the pipeline it ran" {
		Mock Test-Path { $true }
		Mock Import-PowerShellDataFile {
			@{
				Layout   = @(
					@{ ProcessName = 'Code'; WindowTitle = '*'; DesktopNumber = 1 }
				)
				Monitors = @{
					MonitorA = @{ VirtualDesktopLayouts = @{ 1 = 'One' } }
				}
			}
		}
		Mock Get-DesktopList { @(0) }
		Mock Wait-ForWorkspaceWindows { @() }
		$script:LastWorkspaceLayoutTimings = $null

		Set-WorkspaceWindowLayout -WorkspaceName 'MyWorkspace'

		$timings = $script:LastWorkspaceLayoutTimings
		$timings | Should -Not -BeNullOrEmpty
		$timings.Workspace | Should -Be 'MyWorkspace'
		$timings.Outcome | Should -Be 'Applied'
		$timings.Attempts | Should -Be 1
		$timings.Alongside | Should -BeFalse
		$timings.TotalSeconds | Should -BeGreaterOrEqual 0
		foreach ($phase in 'Preamble', 'Desktops', 'FancyZones', 'Wait', 'Normalize', 'Position', 'Snap', 'Verify', 'Save') {
			@($timings.Phases.Keys) | Should -Contain $phase
		}
		# One clean pass: nothing was retried.
		@($timings.Phases.Keys) | Should -Not -Contain 'Retry'
	}

	It "publishes an Aborted record when the layout file is missing" {
		Mock Test-Path { $false }
		$script:LastWorkspaceLayoutTimings = $null

		Set-WorkspaceWindowLayout -WorkspaceName 'MyWorkspace'

		$script:LastWorkspaceLayoutTimings | Should -Not -BeNullOrEmpty
		$script:LastWorkspaceLayoutTimings.Outcome | Should -Be 'Aborted'
		$script:LastWorkspaceLayoutTimings.Attempts | Should -Be 0
	}

	It "in alongside mode adds required desktops and performs cleanup pass" {
		Mock Test-Path { $true }
		Mock Import-PowerShellDataFile {
			@{
				Layout   = @(
					@{ ProcessName = 'Code'; WindowTitle = '*'; DesktopNumber = 1 }
				)
				Monitors = @{
					MonitorA = @{
						VirtualDesktopLayouts = @{
							1 = 'One'
							2 = 'Two'
						}
					}
				}
			}
		}
		Mock Get-DesktopList { @(0) }
		Mock Wait-ForWorkspaceWindows { @() }
		Mock Verify-WindowPlacement { $true }

		Set-WorkspaceWindowLayout -WorkspaceName 'MyWorkspace' -Alongside -DesktopOffset 2

		Should -Invoke Remove-VirtualDesktops -Times 1 -Exactly
		Should -Invoke Ensure-VirtualDesktops -Times 1 -Exactly -ParameterFilter { $Count -eq 4 }
		Should -Invoke Apply-FancyZones -Times 1 -Exactly -ParameterFilter { $DesktopOffset -eq 2 -and $DesktopCount -eq 2 }
		Should -Invoke Snap-AllWindows -Times 1 -Exactly -ParameterFilter { $DesktopOffset -eq 0 -and $DesktopCount -eq 2 }
	}

	It "in alongside mode verifies only the entries this pass placed, excluding pre-existing windows" {
		# Alongside used to report unconditional success, which disabled the retry loop and let
		# Save-CurrentLayout persist a starved run as the truth - the next open then pinned
		# windows to those wrong zones. It verifies now, scoped to what this pass claimed.
		Mock Test-Path { $true }
		Mock Import-PowerShellDataFile {
			@{
				Layout   = @(
					@{ ProcessName = 'Browser'; DesktopNumber = 1; Zone = 'Left'; Monitor = 'MonitorA' }
					@{ ProcessName = 'Browser'; DesktopNumber = 1; Zone = 'Right'; Monitor = 'MonitorA' }
				)
				Monitors = @{
					MonitorA = @{ VirtualDesktopLayouts = @{ 1 = 'One' } }
				}
			}
		}
		Mock Get-DesktopList { @(0) }
		# Only the first entry found a window this open created - the second was starved.
		Mock Set-WindowLayouts {
			@(
				[PSCustomObject]@{
					Status      = 'Configured'
					Handle      = [IntPtr]0xB1001
					ExpectedX   = 0
					LayoutEntry = @{ ProcessName = 'chrome'; DesktopNumber = 1; Zone = 'Left'; Monitor = 'MonitorA' }
				}
				[PSCustomObject]@{ Status = 'Not Found' }
			)
		}
		Mock Write-LogWarning { }

		$existingHandles = New-Object 'System.Collections.Generic.HashSet[IntPtr]'
		[void]$existingHandles.Add([IntPtr]0xB1999)

		Set-WorkspaceWindowLayout -WorkspaceName 'MyWorkspace' -Alongside -PreCapturedExistingWindows $existingHandles

		Should -Invoke Confirm-WorkspaceWindowPositions -Times 1 -Exactly -ParameterFilter {
			$LayoutConfig.Count -eq 1 -and
			$LayoutConfig[0].Zone -eq 'Left' -and
			$ExcludeWindowHandles.Contains([IntPtr]0xB1999)
		}
		# The shortfall is reported instead of passing silently.
		Should -Invoke Write-LogWarning -ParameterFilter { $Message -match 'Layout short by 1 window' }
	}

	It "in alongside mode skips verification entirely when nothing was placed" {
		# Nothing to re-place, so a retry could only pay for FancyZones restarts that cannot
		# conjure windows - the shortfall warning is the report.
		Mock Test-Path { $true }
		Mock Import-PowerShellDataFile {
			@{
				Layout   = @(@{ ProcessName = 'Browser'; DesktopNumber = 1; Zone = 'Left'; Monitor = 'MonitorA' })
				Monitors = @{ MonitorA = @{ VirtualDesktopLayouts = @{ 1 = 'One' } } }
			}
		}
		Mock Get-DesktopList { @(0) }
		Mock Set-WindowLayouts { @([PSCustomObject]@{ Status = 'Not Found' }) }
		Mock Write-LogWarning { }

		Set-WorkspaceWindowLayout -WorkspaceName 'MyWorkspace' -Alongside

		Should -Invoke Confirm-WorkspaceWindowPositions -Times 0
	}

	It "in alongside mode skips existing windows during the early move callback" {
		$existingHandles = New-Object 'System.Collections.Generic.HashSet[IntPtr]'
		[void]$existingHandles.Add([IntPtr]101)

		Mock Test-Path { $true }
		Mock Import-PowerShellDataFile {
			@{
				Layout   = @(
					@{ ProcessName = 'Code'; WindowTitle = '*'; DesktopNumber = 1 }
				)
				Monitors = @{
					MonitorA = @{
						VirtualDesktopLayouts = @{
							1 = 'One'
						}
					}
				}
			}
		}
		Mock Get-DesktopList { @(0) }
		Mock Wait-ForWorkspaceWindows {
			param($LayoutConfig, $TimeoutSeconds, $OnWindowStable)

			& $OnWindowStable $LayoutConfig[0] ([PSCustomObject]@{
					Handle = [IntPtr]101
					Title  = 'Existing Code'
				})

			@{
				Success      = $true
				WindowStates = @{}
			}
		}

		Set-WorkspaceWindowLayout -WorkspaceName 'MyWorkspace' -Alongside -PreCapturedExistingWindows $existingHandles

		Should -Invoke Move-WindowToVirtualDesktop -Times 0 -Exactly
	}

	It "triggers auto-rerun on verification failure in non-alongside mode" {
		Mock Test-Path { $true }
		Mock Import-PowerShellDataFile {
			@{
				Layout   = @(
					@{ ProcessName = 'Code'; WindowTitle = '*'; DesktopNumber = 1 }
				)
				Monitors = @{
					MonitorA = @{
						VirtualDesktopLayouts = @{
							1 = 'One'
						}
					}
				}
			}
		}
		Mock Get-DesktopList { @(0) }
		Mock Set-WindowLayouts {
			@(
				[PSCustomObject]@{ Status = 'Configured' }
			)
		}
		Mock Confirm-WorkspaceWindowPositions {
			@{
				Success  = $false
				Total    = 1
				Failures = @(
					[PSCustomObject]@{
						Handle      = [IntPtr]99
						WindowTitle = 'Code'
						Expected    = '(0,0) 100x100'
						Actual      = '(10,10) 90x90'
					}
				)
			}
		}

		Set-WorkspaceWindowLayout -WorkspaceName 'MyWorkspace'

		# One initial pass + two in-process retries verify against the full config before
		# the terminal respawn is considered.
		Should -Invoke Confirm-WorkspaceWindowPositions -Times 3 -Exactly
		# Each in-process retry force-restarts FancyZones (2) and the escalation path
		# force-restarts it once more before the respawn (3 total).
		Should -Invoke Start-FancyZones -Times 3 -Exactly -ParameterFilter { $ForceRestart }
		Should -Invoke Initialize-WorkspaceWindowLayoutRerun -Times 1 -Exactly -ParameterFilter { $WindowOnlyRetry }
		Should -Invoke ReRun-LastCommand -Times 1 -Exactly
		# The mocked ReRun-LastCommand RETURNS (a real respawn ends the process via
		# [Environment]::Exit) - reaching code after it means the respawn did not happen,
		# so the one-shot retry markers must have been cleared.
		[Environment]::GetEnvironmentVariable('WORKSPACE_WINDOW_ONLY_RETRY', 'Process') | Should -BeNullOrEmpty
	}

	It "retries snap in-process, then escalates to auto-rerun when snap keeps failing" {
		Mock Test-Path { $true }
		Mock Import-PowerShellDataFile {
			@{
				Layout   = @(
					@{ ProcessName = 'Code'; WindowTitle = '*Code*'; DesktopNumber = 1 }
				)
				Monitors = @{
					MonitorA = @{
						VirtualDesktopLayouts = @{
							1 = 'One'
						}
					}
				}
			}
		}
		Mock Get-DesktopList { @(0) }
		Mock Set-WindowLayouts {
			@(
				[PSCustomObject]@{ Status = 'Configured' }
			)
		}
		Mock Snap-AllWindows {
			$script:LastSnapAllWindowsResult = [PSCustomObject]@{
				SnappedCount  = 0
				FailedWindows = @(
					[PSCustomObject]@{
						Handle      = [IntPtr]99
						WindowTitle = 'Code'
						ProcessName = 'Code'
						Expected    = '(0,0) 100x100'
						Actual      = '(10,10) 90x90'
						Error       = 'Snap failed after retries'
					}
				)
			}
		}

		Set-WorkspaceWindowLayout -WorkspaceName 'MyWorkspace'

		# Snap failures never reach verification, and the pipeline is retried in-process
		# (1 initial + 2 retries) before escalating.
		Should -Invoke Confirm-WorkspaceWindowPositions -Times 0
		Should -Invoke Snap-AllWindows -Times 3 -Exactly
		Should -Invoke Start-FancyZones -Times 3 -Exactly -ParameterFilter { $ForceRestart }
		Should -Invoke Initialize-WorkspaceWindowLayoutRerun -Times 1 -Exactly -ParameterFilter { $WindowOnlyRetry }
		Should -Invoke Resize-Windows -Times 1 -ParameterFilter { $WindowHandle -eq [IntPtr]99 }
		Should -Invoke ReRun-LastCommand -Times 1 -Exactly
		# Mocked ReRun-LastCommand returned instead of ending the process, so the one-shot
		# markers written for the respawn must have been cleared again (stale-mode guard).
		[Environment]::GetEnvironmentVariable('WORKSPACE_WINDOW_ONLY_RETRY', 'Process') | Should -BeNullOrEmpty
		[Environment]::GetEnvironmentVariable('WORKSPACE_WINDOW_ONLY_RETRY_TITLE', 'Process') | Should -BeNullOrEmpty
		[Environment]::GetEnvironmentVariable('WORKSPACE_WINDOW_ONLY_RETRY_PROCESS', 'Process') | Should -BeNullOrEmpty
	}

	It "does not auto-rerun on error in alongside mode" {
		Mock Test-Path { $true }
		Mock Import-PowerShellDataFile {
			@{
				Layout   = @(
					@{ ProcessName = 'Code'; WindowTitle = '*'; DesktopNumber = 1 }
				)
				Monitors = @{
					MonitorA = @{
						VirtualDesktopLayouts = @{
							1 = 'One'
						}
					}
				}
			}
		}
		Mock Get-DesktopList { @(0) }
		Mock Set-WindowLayouts { throw 'layout failure' }

		Set-WorkspaceWindowLayout -WorkspaceName 'MyWorkspace' -Alongside

		Should -Invoke Start-FancyZones -Times 0
		Should -Invoke Initialize-WorkspaceWindowLayoutRerun -Times 0
		Should -Invoke ReRun-LastCommand -Times 0
	}

	Context "Rerun state inherited from the registry by a respawned shell" {
		# Windows Terminal generates a new environment block for every session it starts, built
		# from the registry, so the shell a rerun respawns into never sees the plain process-scoped
		# values the escalating run wrote - its process copies ARE the User-scope mirror values,
		# stamp included ("1|<unix-timestamp>"). Read as plain, that stamp went into the [int]
		# cast of the rerun counter (which threw in the escalation path and once more in the catch
		# block) and made the window-only marker compare unequal to '1' on every respawn. These
		# tests give the process copies exactly that shape and let the (mocked) mirror decide.
		BeforeEach {
			Mock Test-Path { $true }
			Mock Import-PowerShellDataFile {
				@{
					Layout   = @(
						@{ ProcessName = 'Code'; WindowTitle = '*'; DesktopNumber = 1 }
					)
					Monitors = @{
						MonitorA = @{
							VirtualDesktopLayouts = @{
								1 = 'One'
							}
						}
					}
				}
			}
			Mock Get-DesktopList { @(0) }
			Mock Set-WindowLayouts {
				@(
					[PSCustomObject]@{ Status = 'Configured' }
				)
			}
			Mock Write-LogError { }
			# The same unverifiable window every time: one initial pass plus two in-process
			# retries, then the escalation that reads the counter.
			$script:FailedVerification = @{
				Success  = $false
				Total    = 1
				Failures = @(
					[PSCustomObject]@{
						Handle      = [IntPtr]99
						WindowTitle = 'Code'
						Expected    = '(0,0) 100x100'
						Actual      = '(10,10) 90x90'
					}
				)
			}
			$script:RegistryStamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
		}

		It "escalates from the mirrored rerun count when the process copy carries the registry stamp" {
			[Environment]::SetEnvironmentVariable('WORKSPACE_RERUN_COUNT', "1|$script:RegistryStamp", 'Process')
			Mock Get-WorkspaceRerunMirror { if ($Name -eq 'WORKSPACE_RERUN_COUNT') { '1' } }
			Mock Confirm-WorkspaceWindowPositions { $script:FailedVerification }

			Set-WorkspaceWindowLayout -WorkspaceName 'MyWorkspace'

			# One rerun is already spent, so this is attempt 2 of 2: it escalates once more and
			# hands the next shell the incremented count - through both copies, as always.
			Should -Invoke Write-LogError -Times 0
			Should -Invoke ReRun-LastCommand -Times 1 -Exactly
			[Environment]::GetEnvironmentVariable('WORKSPACE_RERUN_COUNT', 'Process') | Should -Be '2'
			Should -Invoke Set-WorkspaceRerunMirror -Times 1 -Exactly -ParameterFilter { $Name -eq 'WORKSPACE_RERUN_COUNT' -and $Value -eq '2' }
		}

		It "stops at the rerun cap read from the mirror when the process copy carries the registry stamp" {
			[Environment]::SetEnvironmentVariable('WORKSPACE_RERUN_COUNT', "2|$script:RegistryStamp", 'Process')
			Mock Get-WorkspaceRerunMirror { if ($Name -eq 'WORKSPACE_RERUN_COUNT') { '2' } }
			Mock Confirm-WorkspaceWindowPositions { $script:FailedVerification }

			Set-WorkspaceWindowLayout -WorkspaceName 'MyWorkspace'

			Should -Invoke ReRun-LastCommand -Times 0
			Should -Invoke Initialize-WorkspaceWindowLayoutRerun -Times 0
			# The cap clears the counter in both copies so the next manual open starts from zero.
			[Environment]::GetEnvironmentVariable('WORKSPACE_RERUN_COUNT', 'Process') | Should -BeNullOrEmpty
			Should -Invoke Set-WorkspaceRerunMirror -Times 1 -Exactly -ParameterFilter { $Name -eq 'WORKSPACE_RERUN_COUNT' -and [string]::IsNullOrEmpty($Value) }
		}

		It "starts counting from the mirror when the stamped process copy is stale and the mirror is gone" {
			# A long-lived host (windowingBehavior "useAnyExisting") hands every new tab the registry
			# snapshot taken when the host started. Once the mirror it copied has been consumed or has
			# aged out, that copy is history and must not reopen the count at 1 - the default mirror
			# mock (nothing valid persisted) is the whole truth here.
			[Environment]::SetEnvironmentVariable('WORKSPACE_RERUN_COUNT', "1|$($script:RegistryStamp - 3600)", 'Process')
			Mock Confirm-WorkspaceWindowPositions { $script:FailedVerification }

			Set-WorkspaceWindowLayout -WorkspaceName 'MyWorkspace'

			Should -Invoke Write-LogError -Times 0
			Should -Invoke ReRun-LastCommand -Times 1 -Exactly
			[Environment]::GetEnvironmentVariable('WORKSPACE_RERUN_COUNT', 'Process') | Should -Be '1'
		}

		It "still prefers a plain process copy the running shell wrote itself" {
			[Environment]::SetEnvironmentVariable('WORKSPACE_RERUN_COUNT', '1', 'Process')
			Mock Confirm-WorkspaceWindowPositions { $script:FailedVerification }

			Set-WorkspaceWindowLayout -WorkspaceName 'MyWorkspace'

			Should -Invoke ReRun-LastCommand -Times 1 -Exactly
			[Environment]::GetEnvironmentVariable('WORKSPACE_RERUN_COUNT', 'Process') | Should -Be '2'
		}

		It "honors the window-only retry marker from the mirror when the process copies carry the registry stamp" {
			[Environment]::SetEnvironmentVariable('WORKSPACE_WINDOW_ONLY_RETRY', "1|$script:RegistryStamp", 'Process')
			[Environment]::SetEnvironmentVariable('WORKSPACE_WINDOW_ONLY_RETRY_TITLE', "Code|$script:RegistryStamp", 'Process')
			Mock Get-WorkspaceRerunMirror {
				switch ($Name) {
					'WORKSPACE_WINDOW_ONLY_RETRY' { '1' }
					'WORKSPACE_WINDOW_ONLY_RETRY_TITLE' { 'Code' }
				}
			}

			Set-WorkspaceWindowLayout -WorkspaceName 'MyWorkspace'

			# The respawned run must force the zone re-apply - the grid it escalated over was wrong -
			# and consume the one-shot markers, stamped process copies included, so the next open in
			# this shell is a plain one.
			Should -Invoke Apply-FancyZones -Times 1 -Exactly -ParameterFilter { $Force }
			[Environment]::GetEnvironmentVariable('WORKSPACE_WINDOW_ONLY_RETRY', 'Process') | Should -BeNullOrEmpty
			[Environment]::GetEnvironmentVariable('WORKSPACE_WINDOW_ONLY_RETRY_TITLE', 'Process') | Should -BeNullOrEmpty
		}
	}

	It "forwards SnapDelayMs and snap desktop parameters in standard flow" {
		Mock Test-Path { $true }
		Mock Import-PowerShellDataFile {
			@{
				Layout   = @(
					@{ ProcessName = 'Code'; WindowTitle = '*'; DesktopNumber = 1 }
				)
				Monitors = @{
					MonitorA = @{
						VirtualDesktopLayouts = @{
							1 = 'One'
							2 = 'Two'
							3 = 'Three'
						}
					}
				}
			}
		}
		Mock Get-DesktopList { @(0, 1, 2) }

		Set-WorkspaceWindowLayout -WorkspaceName 'MyWorkspace' -DesktopOffset 5 -SnapDelayMs 25

		Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Milliseconds -eq 25 }
		# Offset 0 even with -DesktopOffset 5: the tracked desktop numbers Snap-AllWindows
		# reads already have the offset folded in (Set-WindowLayouts adds it before calling
		# Add-PositionedWindow), and Snap-AllWindows adds it again. Forwarding the real offset
		# double-applied it and sent the snap pass to a desktop no window was on.
		Should -Invoke Snap-AllWindows -Times 1 -Exactly -ParameterFilter { $DesktopOffset -eq 0 -and $DesktopCount -eq 3 }
	}

	It "reads CurrentLayout.txt and forwards a pinned handle map to Set-WindowLayouts, then records the layout on success" {
		Mock Test-Path { $true }
		Mock Import-PowerShellDataFile {
			@{
				Layout   = @(
					@{ ProcessName = 'Code'; WindowTitle = '*'; DesktopNumber = 1 }
				)
				Monitors = @{
					MonitorA = @{
						VirtualDesktopLayouts = @{
							1 = 'One'
						}
					}
				}
			}
		}
		Mock Get-DesktopList { @(0) }
		# Clean snap result so the standard success path is reached (the global mock leaves
		# $script:LastSnapAllWindowsResult untouched, which can leak a failed result from a
		# prior test; the real Snap-AllWindows always resets it at its start).
		Mock Snap-AllWindows { $script:LastSnapAllWindowsResult = [PSCustomObject]@{ SnappedCount = 1; FailedWindows = @() } }
		Mock Get-CurrentLayout {
			@{
				Windows = @(
					@{ Handle = 4242; ProcessId = 10; ProcessName = 'Code'; Desktop = 1; Monitor = 'Primary'; Zone = 'Left' }
				)
			}
		}

		Set-WorkspaceWindowLayout -WorkspaceName 'MyWorkspace'

		Should -Invoke Set-WindowLayouts -Times 1 -Exactly -ParameterFilter {
			$null -ne $PinnedHandleMap -and $PinnedHandleMap.ContainsKey('1|Primary|Left')
		}
		Should -Invoke Save-CurrentLayout -Times 1 -Exactly -ParameterFilter { $Workspace -eq 'MyWorkspace' }
	}

	It "does not write CurrentLayout.txt when verification fails (failure path)" {
		Mock Test-Path { $true }
		Mock Import-PowerShellDataFile {
			@{
				Layout   = @(
					@{ ProcessName = 'Code'; WindowTitle = '*'; DesktopNumber = 1 }
				)
				Monitors = @{
					MonitorA = @{
						VirtualDesktopLayouts = @{
							1 = 'One'
						}
					}
				}
			}
		}
		Mock Get-DesktopList { @(0) }
		Mock Set-WindowLayouts { @([PSCustomObject]@{ Status = 'Configured' }) }
		# Clean snap result so the flow reaches verification (rather than the snap-failure branch).
		Mock Snap-AllWindows { $script:LastSnapAllWindowsResult = [PSCustomObject]@{ SnappedCount = 1; FailedWindows = @() } }
		Mock Confirm-WorkspaceWindowPositions {
			@{
				Success  = $false
				Total    = 1
				Failures = @([PSCustomObject]@{ Handle = [IntPtr]99; WindowTitle = 'Code'; Expected = '(0,0) 100x100'; Actual = '(10,10) 90x90' })
			}
		}

		Set-WorkspaceWindowLayout -WorkspaceName 'MyWorkspace'

		Should -Invoke Save-CurrentLayout -Times 0 -Exactly
	}

	It "in alongside mode skips per-window normalization when no new windows are detected" {
		$existingHandles = New-Object 'System.Collections.Generic.HashSet[IntPtr]'
		[void]$existingHandles.Add([IntPtr]101)

		Mock Test-Path { $true }
		Mock Import-PowerShellDataFile {
			@{
				Layout   = @(
					@{ ProcessName = 'Code'; WindowTitle = '*'; DesktopNumber = 1 }
				)
				Monitors = @{
					MonitorA = @{
						VirtualDesktopLayouts = @{
							1 = 'One'
						}
					}
				}
			}
		}
		Mock Get-DesktopList { @(0) }
		Mock Get-WindowHandle {
			@([PSCustomObject]@{ Handle = [IntPtr]101; Title = 'Code'; ProcessId = 1234 })
		}

		Set-WorkspaceWindowLayout -WorkspaceName 'MyWorkspace' -Alongside -PreCapturedExistingWindows $existingHandles

		Should -Invoke Resize-Windows -Times 0 -ParameterFilter { $PSBoundParameters.ContainsKey('WindowHandle') }
		Should -Invoke Set-WindowLayouts -Times 1 -Exactly
	}

	It "preserves a title-less VS Code entry as a catch-all (all VS Code windows match by process)" {
		Mock Test-Path { $true }
		Mock Import-PowerShellDataFile {
			@{
				Layout   = @(
					@{ ProcessName = 'Code'; DesktopNumber = 1; Zone = 'Fullscreen'; Monitor = 'MonitorA' }
				)
				Monitors = @{
					MonitorA = @{
						VirtualDesktopLayouts = @{
							1 = 'One'
						}
					}
				}
			}
		}
		Mock Get-DesktopList { @(0) }
		Mock Snap-AllWindows { $script:LastSnapAllWindowsResult = [PSCustomObject]@{ SnappedCount = 1; FailedWindows = @() } }

		Set-WorkspaceWindowLayout -WorkspaceName 'Dotfiles'

		Should -Invoke Set-WindowLayouts -Times 1 -Exactly -ParameterFilter {
			$codeEntry = @($LayoutConfig | Where-Object { $_.ProcessName -eq 'Code' })
			($codeEntry.Count -eq 1) -and (-not $codeEntry[0].WindowTitle)
		}
	}

	It "passes a targeted VS Code entry through unchanged (bare-name title = deterministic match)" {
		Mock Test-Path { $true }
		Mock Import-PowerShellDataFile {
			@{
				Layout   = @(
					@{ ProcessName = 'Code'; WindowTitle = '^(?=.*Dotfiles)(?=.*Visual Studio Code).*$'; DesktopNumber = 1 }
				)
				Monitors = @{
					MonitorA = @{
						VirtualDesktopLayouts = @{
							1 = 'One'
						}
					}
				}
			}
		}
		Mock Get-DesktopList { @(0) }
		Mock Snap-AllWindows { $script:LastSnapAllWindowsResult = [PSCustomObject]@{ SnappedCount = 1; FailedWindows = @() } }

		Set-WorkspaceWindowLayout -WorkspaceName 'Dotfiles'

		Should -Invoke Set-WindowLayouts -Times 1 -Exactly -ParameterFilter {
			($LayoutConfig | Where-Object { $_.ProcessName -eq 'Code' }).WindowTitle -match 'Dotfiles'
		}
	}

	It "leaves multiple distinct VS Code entries' titles unchanged (windows split across zones)" {
		Mock Test-Path { $true }
		Mock Import-PowerShellDataFile {
			@{
				Layout   = @(
					@{ ProcessName = 'Code'; WindowTitle = 'Dotfiles'; DesktopNumber = 1; Zone = 'Left'; Monitor = 'MonitorA' }
					@{ ProcessName = 'Code'; WindowTitle = 'OtherProj'; DesktopNumber = 1; Zone = 'Right'; Monitor = 'MonitorA' }
				)
				Monitors = @{
					MonitorA = @{
						VirtualDesktopLayouts = @{
							1 = 'One'
						}
					}
				}
			}
		}
		Mock Get-DesktopList { @(0) }
		Mock Snap-AllWindows { $script:LastSnapAllWindowsResult = [PSCustomObject]@{ SnappedCount = 1; FailedWindows = @() } }

		Set-WorkspaceWindowLayout -WorkspaceName 'Dotfiles'

		Should -Invoke Set-WindowLayouts -Times 1 -Exactly -ParameterFilter {
			(@($LayoutConfig | Where-Object { $_.WindowTitle -eq 'Dotfiles' }).Count -eq 1) -and
			(@($LayoutConfig | Where-Object { $_.WindowTitle -eq 'OtherProj' }).Count -eq 1)
		}
	}

	Context "ProtectedWindowHandles (preserving alongside workspaces on a plain open)" {
		# A plain rerun of workspace A with workspace B open -Alongside used to destroy B three
		# ways: the desktop resize removed B's desktops (Ensure-VirtualDesktops removes from the
		# right - exactly where alongside lives), the layout pass stole B's windows, and the
		# snapshot write dropped B's CurrentLayout section. These tests pin the protection that
		# stops each mechanism.
		BeforeAll {
			# Local stub so the self-derive test can mock the Workflow-owned function without
			# importing the Workflow module here.
			function Get-WorkspaceOpenProtection { $null }

			function New-ProtectedHandleSet {
				param([int[]]$Handle)
				$set = New-Object 'System.Collections.Generic.HashSet[IntPtr]'
				foreach ($item in $Handle) { [void]$set.Add([IntPtr]$item) }
				$set
			}
		}

		BeforeEach {
			Mock Write-LogWarning { }
			Mock Get-WindowDesktopIndex { -1 }
			Mock Test-Path { $true }
			# One-desktop layout: small enough that any preserved alongside desktops sit above it.
			Mock Import-PowerShellDataFile {
				@{
					Layout   = @(
						@{ ProcessName = 'Code'; WindowTitle = '*'; DesktopNumber = 1 }
					)
					Monitors = @{
						MonitorA = @{
							VirtualDesktopLayouts = @{
								1 = 'One'
							}
						}
					}
				}
			}
			Mock Get-DesktopList { @(0) }
			Mock Snap-AllWindows { $script:LastSnapAllWindowsResult = [PSCustomObject]@{ SnappedCount = 1; FailedWindows = @() } }
		}

		It "never shrinks below the desktops the protected windows stand on" {
			# A (1 desktop) reruns while B holds desktops 2-3: current 3, layout needs 1, B's
			# highest window is on index 2 => the floor is 3 and nothing may be removed.
			Mock Get-DesktopList { @(0, 1, 2) }
			Mock Get-WindowDesktopIndex { 2 }

			Set-WorkspaceWindowLayout -WorkspaceName 'MyWorkspace' -ProtectedWindowHandles (New-ProtectedHandleSet 60)

			Should -Invoke Ensure-VirtualDesktops -Times 0
			Should -Invoke Remove-VirtualDesktops -Times 0
		}

		It "still grows when the layout needs more desktops than exist" {
			Mock Import-PowerShellDataFile {
				@{
					Layout   = @(@{ ProcessName = 'Code'; WindowTitle = '*'; DesktopNumber = 1 })
					Monitors = @{
						MonitorA = @{ VirtualDesktopLayouts = @{ 1 = 'One'; 2 = 'Two'; 3 = 'Three'; 4 = 'Four' } }
					}
				}
			}
			Mock Get-DesktopList { @(0, 1, 2) }
			Mock Get-WindowDesktopIndex { 2 }

			Set-WorkspaceWindowLayout -WorkspaceName 'MyWorkspace' -ProtectedWindowHandles (New-ProtectedHandleSet 60)

			Should -Invoke Ensure-VirtualDesktops -Times 1 -Exactly -ParameterFilter { $Count -eq 4 }
		}

		It "never shrinks when the protected windows' desktops cannot be resolved" {
			# Protected windows exist but every lookup returned -1 (enumeration hiccup). Shrinking
			# on unknown occupancy could delete the alongside workspace - keep the current count.
			Mock Get-DesktopList { @(0, 1, 2, 3, 4) }
			Mock Get-WindowDesktopIndex { -1 }

			Set-WorkspaceWindowLayout -WorkspaceName 'MyWorkspace' -ProtectedWindowHandles (New-ProtectedHandleSet 60)

			Should -Invoke Ensure-VirtualDesktops -Times 0
		}

		It "warns when a protected window sits inside this layout's own desktop range" {
			Mock Get-DesktopList { @(0) }
			Mock Get-WindowDesktopIndex { 0 }

			Set-WorkspaceWindowLayout -WorkspaceName 'MyWorkspace' -ProtectedWindowHandles (New-ProtectedHandleSet 60)

			Should -Invoke Write-LogWarning -ParameterFilter { $Message -match 'overlap' }
		}

		It "threads the protected handles into the layout pass, the verification, and the snapshot merge" {
			Mock Get-DesktopList { @(0, 1, 2) }
			Mock Get-WindowDesktopIndex { 2 }
			Mock Set-WindowLayouts { @([PSCustomObject]@{ Status = 'Configured' }) }

			Set-WorkspaceWindowLayout -WorkspaceName 'MyWorkspace' -ProtectedWindowHandles (New-ProtectedHandleSet 60)

			Should -Invoke Set-WindowLayouts -Times 1 -Exactly -ParameterFilter {
				$ProtectedWindowHandles -and $ProtectedWindowHandles.Contains([IntPtr]60)
			}
			# Plain-mode verification excludes the preserved windows - the layout pass was
			# forbidden from touching them, so they must not be judged either.
			Should -Invoke Confirm-WorkspaceWindowPositions -Times 1 -Exactly -ParameterFilter {
				$ExcludeWindowHandles -and $ExcludeWindowHandles.Contains([IntPtr]60)
			}
			# The plain snapshot write merges so the preserved workspaces keep their sections.
			Should -Invoke Save-CurrentLayout -Times 1 -Exactly -ParameterFilter { $PreserveOtherSections }
		}

		It "does not merge the snapshot on an unprotected plain open" {
			Set-WorkspaceWindowLayout -WorkspaceName 'MyWorkspace'

			Should -Invoke Save-CurrentLayout -Times 1 -Exactly -ParameterFilter { -not $PreserveOtherSections }
		}

		It "skips protected windows during the early move callback" {
			Mock Get-DesktopList { @(0, 1, 2) }
			Mock Get-WindowDesktopIndex { 2 }
			Mock Wait-ForWorkspaceWindows {
				param($LayoutConfig, $TimeoutSeconds, $OnWindowStable)

				& $OnWindowStable $LayoutConfig[0] ([PSCustomObject]@{
						Handle = [IntPtr]60
						Title  = 'Preserved alongside window'
					})

				@{ Success = $true; WindowStates = @{} }
			}

			Set-WorkspaceWindowLayout -WorkspaceName 'MyWorkspace' -ProtectedWindowHandles (New-ProtectedHandleSet 60)

			Should -Invoke Move-WindowToVirtualDesktop -Times 0 -Exactly
		}

		It "self-derives protection on a standalone plain call when the Workflow function is available" {
			# The blanket Get-Command mock returns $null (hermetic default: no self-derive); this
			# test opts the one lookup back in and stubs the function it finds.
			Mock Get-Command { $true } -ParameterFilter { $Name -eq 'Get-WorkspaceOpenProtection' }
			Mock Get-WorkspaceOpenProtection {
				[PSCustomObject]@{
					Entries       = @([ordered]@{ Workspace = 'AlongsideB'; Alongside = $true })
					WindowHandles = (New-ProtectedHandleSet 60)
				}
			}
			Mock Get-DesktopList { @(0, 1, 2) }
			Mock Get-WindowDesktopIndex { 2 }
			Mock Set-WindowLayouts { @([PSCustomObject]@{ Status = 'Configured' }) }

			Set-WorkspaceWindowLayout -WorkspaceName 'MyWorkspace'

			Should -Invoke Get-WorkspaceOpenProtection -Times 1 -Exactly
			Should -Invoke Set-WindowLayouts -Times 1 -Exactly -ParameterFilter {
				$ProtectedWindowHandles -and $ProtectedWindowHandles.Contains([IntPtr]60)
			}
		}

		It "never self-derives for an alongside open" {
			Mock Get-Command { $true } -ParameterFilter { $Name -eq 'Get-WorkspaceOpenProtection' }
			Mock Get-WorkspaceOpenProtection { throw 'must not be called' }
			Mock Get-DesktopList { @(0) }

			Set-WorkspaceWindowLayout -WorkspaceName 'MyWorkspace' -Alongside

			Should -Invoke Get-WorkspaceOpenProtection -Times 0
		}
	}

	Context "FancyZones reset between retries" {
		# Reproduction harness for the retry loop that could never recover.
		#
		# A snap/verification failure almost never means "the window refused to move" - it
		# means the zone grid the snap targeted was wrong. The retry used to re-run
		# position -> snap -> verify against that SAME broken grid, so all attempts failed
		# identically and the run escalated to a terminal respawn that reapplied FancyZones
		# idempotently (i.e. skipped it) and failed identically too.
		#
		# $script:FancyZonesSim models the state that actually decides whether a snap lands:
		#   Running          - the PowerToys.FancyZones process is alive
		#   ZonesApplied     - the LIVE zone grid matches the workspace layout
		#   StaleAppliedJson - applied-layouts.json claims the layout is already applied, so
		#                      Apply-FancyZones' idempotency check skips every shortcut send
		#                      while the live grid stays wrong (a "jumbled" FancyZones)
		BeforeEach {
			$script:FancyZonesSim = @{
				Running          = $true
				ZonesApplied     = $true
				StaleAppliedJson = $false
				CrashOnNextSnap  = $false
				ForcedApplies    = 0
			}

			Mock Start-FancyZones {
				if ($ForceRestart) {
					# A restarted FancyZones reloads applied-layouts.json but does NOT
					# re-assert the live grid - the layout shortcuts must be re-sent.
					$script:FancyZonesSim.Running = $true
					$script:FancyZonesSim.ZonesApplied = $false
				}
				elseif (-not $script:FancyZonesSim.Running) {
					$script:FancyZonesSim.Running = $true
					$script:FancyZonesSim.ZonesApplied = $false
				}
				$true
			}

			Mock Apply-FancyZones {
				# The real function starts FancyZones itself before applying anything.
				$script:FancyZonesSim.Running = $true

				if ($Force) {
					$script:FancyZonesSim.ForcedApplies++
					$script:FancyZonesSim.ZonesApplied = $true
				}
				elseif (-not $script:FancyZonesSim.StaleAppliedJson) {
					$script:FancyZonesSim.ZonesApplied = $true
				}
				# else: every monitor reports "Already Applied" and nothing is sent.
			}

			Mock Snap-AllWindows {
				if ($script:FancyZonesSim.CrashOnNextSnap) {
					$script:FancyZonesSim.CrashOnNextSnap = $false
					$script:FancyZonesSim.Running = $false
					$script:FancyZonesSim.ZonesApplied = $false
				}

				$script:LastSnapAllWindowsResult = if ($script:FancyZonesSim.Running -and $script:FancyZonesSim.ZonesApplied) {
					[PSCustomObject]@{ SnappedCount = 1; FailedWindows = @() }
				}
				else {
					[PSCustomObject]@{
						SnappedCount  = 0
						FailedWindows = @(
							[PSCustomObject]@{
								Handle      = [IntPtr]99
								WindowTitle = 'Code'
								ProcessName = 'Code'
								Expected    = '(0,0) 100x100'
								Actual      = '(10,10) 90x90'
								Error       = 'Snap FAILED for [Code] - not at expected zone'
							}
						)
					}
				}
			}

			Mock Confirm-WorkspaceWindowPositions {
				if ($script:FancyZonesSim.Running -and $script:FancyZonesSim.ZonesApplied) {
					@{ Success = $true }
				}
				else {
					@{
						Success  = $false
						Total    = 1
						Failures = @(
							[PSCustomObject]@{
								Handle      = [IntPtr]99
								WindowTitle = 'Code'
								ProcessName = 'Code'
								Expected    = '(0,0) 100x100'
								Actual      = '(10,10) 90x90'
							}
						)
					}
				}
			}

			Mock Set-WindowLayouts { @([PSCustomObject]@{ Status = 'Configured' }) }
			Mock Test-Path { $true }
			Mock Import-PowerShellDataFile {
				@{
					Layout   = @(
						@{ ProcessName = 'Code'; WindowTitle = '*Code*'; DesktopNumber = 1 }
					)
					Monitors = @{
						MonitorA = @{
							VirtualDesktopLayouts = @{
								1 = 'One'
							}
						}
					}
				}
			}
			Mock Get-DesktopList { @(0) }
		}

		It "recovers in-process when FancyZones holds a stale zone grid that idempotency would skip" {
			$script:FancyZonesSim.ZonesApplied = $false
			$script:FancyZonesSim.StaleAppliedJson = $true

			Set-WorkspaceWindowLayout -WorkspaceName 'MyWorkspace'

			# The retry has to re-send the layout shortcuts even though applied-layouts.json
			# claims they are already applied - that file is exactly what lies here.
			$script:FancyZonesSim.ForcedApplies | Should -BeGreaterThan 0
			$script:FancyZonesSim.ZonesApplied | Should -BeTrue
			Should -Invoke ReRun-LastCommand -Times 0
			Should -Invoke Save-CurrentLayout -Times 1 -Exactly
		}

		It "recovers in-process when FancyZones dies during the first snap pass" {
			$script:FancyZonesSim.CrashOnNextSnap = $true

			Set-WorkspaceWindowLayout -WorkspaceName 'MyWorkspace'

			$script:FancyZonesSim.Running | Should -BeTrue
			$script:FancyZonesSim.ZonesApplied | Should -BeTrue
			Should -Invoke ReRun-LastCommand -Times 0
			Should -Invoke Save-CurrentLayout -Times 1 -Exactly
		}

		It "force-restarts FancyZones and re-applies the zone layout on every in-process retry" {
			# Unrecoverable: the re-apply never takes effect, so all retries are spent and the
			# run still escalates - but each retry must have attempted the full reset.
			$script:FancyZonesSim.ZonesApplied = $false
			Mock Apply-FancyZones { }

			Set-WorkspaceWindowLayout -WorkspaceName 'MyWorkspace'

			# One reset per in-process retry (2) + the pre-respawn force-start (1).
			Should -Invoke Start-FancyZones -Times 3 -Exactly -ParameterFilter { $ForceRestart }
			# The initial pass stays idempotent; only the retries force the re-send.
			Should -Invoke Apply-FancyZones -Times 2 -Exactly -ParameterFilter { $Force }
			Should -Invoke ReRun-LastCommand -Times 1 -Exactly
		}

		It "forces the zone re-apply when running in window-only retry mode" {
			# The respawned run must not trust applied-layouts.json either: the run that
			# escalated to it did so precisely because the live grid was wrong.
			[Environment]::SetEnvironmentVariable('WORKSPACE_WINDOW_ONLY_RETRY', '1', 'Process')

			Set-WorkspaceWindowLayout -WorkspaceName 'MyWorkspace'

			Should -Invoke Apply-FancyZones -Times 1 -Exactly -ParameterFilter { $Force }
		}
	}

	Context "Per-desktop pipelining and the in-pass zone reset" {
		# Two desktops. The wait reports desktop 2 ready while desktop 1's window still loads,
		# then completes; the layout pass for desktop 2 must run DURING the wait, restricted to
		# the window the wait handed over, and the tail after the wait must finish desktop 1
		# without touching what was already placed.
		BeforeEach {
			Mock Test-Path { $true }
			Mock Import-PowerShellDataFile {
				@{
					Layout   = @(
						@{ ProcessName = 'Code'; WindowTitle = '*Code*'; DesktopNumber = 1 }
						@{ ProcessName = 'WindowsTerminal'; DesktopNumber = 2 }
					)
					Monitors = @{
						MonitorA = @{
							VirtualDesktopLayouts = @{
								1 = 'One'
								2 = 'Two'
							}
						}
					}
				}
			}
			Mock Get-DesktopList { @(0, 1) }

			$script:layoutCalls = @()
			Mock Set-WindowLayouts {
				$script:layoutCalls += [PSCustomObject]@{
					Entries    = @($LayoutConfig)
					Keep       = [bool]$KeepPositionedWindows
					Candidates = $CandidateWindowHandles
					Excluded   = $ExcludeWindowHandles
				}
				@($LayoutConfig | ForEach-Object {
						[PSCustomObject]@{ Status = 'Configured'; Handle = [IntPtr](100 + $_.DesktopNumber); ProcessName = $_.ProcessName; WindowProcessName = $_.ProcessName; DesktopNumber = $_.DesktopNumber; ExpectedX = 0 }
					})
			}

			$script:snapCalls = @()
			Mock Snap-AllWindows {
				$script:snapCalls += [PSCustomObject]@{ Desktops = $DesktopNumbers; HasReset = ($null -ne $ZoneReset) }
				$script:LastSnapAllWindowsResult = [PSCustomObject]@{ SnappedCount = 1; FailedWindows = @() }
			}

			$script:resizeCalls = @()
			Mock Resize-PositionedWindows {
				$script:resizeCalls += , @($DesktopNumbers)
				@{ FailedWindows = @() }
			}

			Mock Wait-ForWorkspaceWindows {
				param($LayoutConfig, $TimeoutSeconds, $OnWindowStable, $OnDesktopReady)
				if ($OnDesktopReady) {
					& $OnDesktopReady 2 @(@{
							LayoutEntry = $LayoutConfig[1]
							Window      = [PSCustomObject]@{ Handle = [IntPtr]102; Title = 'Terminal'; Left = 0; Top = 0; Width = 800; Height = 600 }
						})
				}
				@{
					Success       = $true
					WindowStates  = @{ ([IntPtr]101) = @{ Title = 'Code' }; ([IntPtr]102) = @{ Title = 'Terminal' } }
					ReadyDesktops = @(2)
				}
			}
		}

		It "positions and snaps a desktop reported ready during the wait, then finishes the rest without it" {
			Set-WorkspaceWindowLayout -WorkspaceName 'MyWorkspace'

			$script:layoutCalls.Count | Should -Be 2
			# During the wait: desktop 2's entry alone, appended to the shared tracking, restricted
			# to the window the wait handed over.
			$script:layoutCalls[0].Entries.Count | Should -Be 1
			$script:layoutCalls[0].Entries[0].ProcessName | Should -Be 'WindowsTerminal'
			$script:layoutCalls[0].Keep | Should -BeTrue
			$script:layoutCalls[0].Candidates.Contains([IntPtr]102) | Should -BeTrue
			# After the wait: desktop 1's entry alone, still appending, with the placed window off limits.
			$script:layoutCalls[1].Entries.Count | Should -Be 1
			$script:layoutCalls[1].Entries[0].ProcessName | Should -Be 'Code'
			$script:layoutCalls[1].Keep | Should -BeTrue
			$script:layoutCalls[1].Excluded.Contains([IntPtr]102) | Should -BeTrue

			# Resize and snap run per desktop, in that order, each with the FancyZones reset attached.
			$script:resizeCalls.Count | Should -Be 2
			@($script:resizeCalls[0]) | Should -Be @(2)
			@($script:resizeCalls[1]) | Should -Be @(1)
			$script:snapCalls.Count | Should -Be 2
			@($script:snapCalls[0].Desktops) | Should -Be @(2)
			@($script:snapCalls[1].Desktops) | Should -Be @(1)
			$script:snapCalls | ForEach-Object { $_.HasReset | Should -BeTrue }

			# One global verification, and both halves' results feed the snapshot.
			Should -Invoke Confirm-WorkspaceWindowPositions -Times 1 -Exactly
			Should -Invoke Save-CurrentLayout -Times 1 -Exactly -ParameterFilter { @($WindowStates).Count -eq 2 }
		}

		It "runs the plain sequential order when WorkspaceLayoutPipelining is false" {
			$global:Configuration.WorkspaceLayoutPipelining = $false

			Set-WorkspaceWindowLayout -WorkspaceName 'MyWorkspace'

			Should -Invoke Wait-ForWorkspaceWindows -Times 1 -Exactly -ParameterFilter { $null -eq $OnDesktopReady }
			$script:layoutCalls.Count | Should -Be 1
			$script:layoutCalls[0].Entries.Count | Should -Be 2
			$script:layoutCalls[0].Keep | Should -BeFalse
			$script:snapCalls.Count | Should -Be 1
			$script:snapCalls[0].Desktops | Should -BeNullOrEmpty
			# The in-pass zone reset is handed over regardless of pipelining.
			$script:snapCalls[0].HasReset | Should -BeTrue
		}

		It "does not pipeline a single-desktop layout" {
			Mock Import-PowerShellDataFile {
				@{
					Layout   = @(@{ ProcessName = 'Code'; WindowTitle = '*Code*'; DesktopNumber = 1 })
					Monitors = @{ MonitorA = @{ VirtualDesktopLayouts = @{ 1 = 'One' } } }
				}
			}
			Mock Get-DesktopList { @(0) }

			Set-WorkspaceWindowLayout -WorkspaceName 'MyWorkspace'

			Should -Invoke Wait-ForWorkspaceWindows -Times 1 -Exactly -ParameterFilter { $null -eq $OnDesktopReady }
		}

		It "runs the full layout again on the in-process retry after a pipelined first attempt" {
			$script:verifyCalls = 0
			Mock Confirm-WorkspaceWindowPositions {
				$script:verifyCalls++
				if ($script:verifyCalls -eq 1) { @{ Success = $false; Failures = @(); Total = 2 } } else { @{ Success = $true } }
			}

			Set-WorkspaceWindowLayout -WorkspaceName 'MyWorkspace'

			# Attempt 1: the per-desktop half plus the remaining half. Attempt 2: the whole layout,
			# fresh tracking, every desktop.
			$script:layoutCalls.Count | Should -Be 3
			$script:layoutCalls[2].Entries.Count | Should -Be 2
			$script:layoutCalls[2].Keep | Should -BeFalse
			$script:layoutCalls[2].Excluded | Should -BeNullOrEmpty
			$script:snapCalls.Count | Should -Be 3
			$script:snapCalls[2].Desktops | Should -BeNullOrEmpty
			Should -Invoke Start-FancyZones -Times 1 -Exactly -ParameterFilter { $ForceRestart }
		}

		It "counts a pipelined desktop's snap failures against the first attempt" {
			Mock Snap-AllWindows {
				$script:snapCalls += [PSCustomObject]@{ Desktops = $DesktopNumbers; HasReset = ($null -ne $ZoneReset) }
				$failed = @()
				if ($DesktopNumbers -and $DesktopNumbers -contains 2) {
					$failed = @([PSCustomObject]@{ Handle = [IntPtr]102; WindowTitle = 'Terminal'; ProcessName = 'WindowsTerminal'; Expected = '(0,0) 1x1'; Actual = '(5,5) 1x1'; Error = 'Snap FAILED' })
				}
				$script:LastSnapAllWindowsResult = [PSCustomObject]@{ SnappedCount = 0; FailedWindows = $failed }
			}

			Set-WorkspaceWindowLayout -WorkspaceName 'MyWorkspace'

			# Attempt 1 ends with the pipelined failure and never verifies; attempt 2 runs the
			# full layout after one FancyZones reset and verifies.
			$script:layoutCalls.Count | Should -Be 3
			Should -Invoke Start-FancyZones -Times 1 -Exactly -ParameterFilter { $ForceRestart }
			Should -Invoke Confirm-WorkspaceWindowPositions -Times 1 -Exactly
			Should -Invoke ReRun-LastCommand -Times 0 -Exactly
		}

		It "skips windows a per-desktop pass placed during first-open normalization" {
			$existing = New-Object 'System.Collections.Generic.HashSet[IntPtr]'
			[void]$existing.Add([IntPtr]5)
			Mock Get-WindowHandle {
				@(
					[PSCustomObject]@{ Handle = [IntPtr]101; Title = 'Code'; ProcessName = 'Code' }
					[PSCustomObject]@{ Handle = [IntPtr]102; Title = 'Terminal'; ProcessName = 'WindowsTerminal' }
				)
			}

			Set-WorkspaceWindowLayout -WorkspaceName 'MyWorkspace' -PreCapturedExistingWindows $existing

			# Window 102 was placed by the per-desktop pass; only 101 is normalized.
			Should -Invoke Resize-Windows -Times 1 -Exactly -ParameterFilter { $WindowHandle -eq [IntPtr]101 -and $null -eq $TargetX }
			Should -Invoke Resize-Windows -Times 0 -Exactly -ParameterFilter { $WindowHandle -eq [IntPtr]102 }
		}
	}
}
