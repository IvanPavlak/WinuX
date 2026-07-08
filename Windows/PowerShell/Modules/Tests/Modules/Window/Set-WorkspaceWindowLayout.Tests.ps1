#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Initialize-WorkspaceWindowLayoutRerun.ps1"
	. "$FunctionsPath\Get-CurrentLayout.ps1"
	. "$FunctionsPath\Save-CurrentLayout.ps1"
	. "$FunctionsPath\Set-WorkspaceWindowLayout.ps1"

	function Remove-PositionedWindowHandles { }
	function Verify-WindowPlacement { $true }

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

		$env:WORKSPACE_RERUN_COUNT = $null
		[Environment]::SetEnvironmentVariable('WORKSPACE_WINDOW_ONLY_RETRY', $null, 'Process')
		[Environment]::SetEnvironmentVariable('WORKSPACE_WINDOW_ONLY_RETRY_TITLE', $null, 'Process')
		[Environment]::SetEnvironmentVariable('WORKSPACE_WINDOW_ONLY_RETRY_PROCESS', $null, 'Process')
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

		Should -Invoke Start-FancyZones -Times 1 -Exactly
		Should -Invoke Initialize-WorkspaceWindowLayoutRerun -Times 1 -Exactly -ParameterFilter { $WindowOnlyRetry }
		Should -Invoke ReRun-LastCommand -Times 1 -Exactly
	}

	It "triggers auto-rerun immediately when snap retries fail" {
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

		Should -Invoke Confirm-WorkspaceWindowPositions -Times 0
		Should -Invoke Start-FancyZones -Times 1 -Exactly
		Should -Invoke Initialize-WorkspaceWindowLayoutRerun -Times 1 -Exactly -ParameterFilter { $WindowOnlyRetry }
		Should -Invoke Resize-Windows -Times 1 -ParameterFilter { $WindowHandle -eq [IntPtr]99 }
		Should -Invoke ReRun-LastCommand -Times 1 -Exactly
		[Environment]::GetEnvironmentVariable('WORKSPACE_WINDOW_ONLY_RETRY', 'Process') | Should -Be '1'
		[Environment]::GetEnvironmentVariable('WORKSPACE_WINDOW_ONLY_RETRY_TITLE', 'Process') | Should -Be 'Code'
		[Environment]::GetEnvironmentVariable('WORKSPACE_WINDOW_ONLY_RETRY_PROCESS', 'Process') | Should -Be 'Code'
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
		Should -Invoke Snap-AllWindows -Times 1 -Exactly -ParameterFilter { $DesktopOffset -eq 5 -and $DesktopCount -eq 3 }
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
}
