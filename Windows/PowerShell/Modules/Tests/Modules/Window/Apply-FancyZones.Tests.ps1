#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Apply-FancyZones.ps1"
	. "$FunctionsPath\ConvertTo-InternalDesktopIndex.ps1"
	. "$FunctionsPath\Get-DuplicateMonitorEdid.ps1"
}

Describe "Apply-FancyZones" {
	BeforeEach {
		Mock Write-Host { }
		Mock Write-Warning { }
		Mock Write-Error { }
		Mock Start-Sleep { }
		Mock Ensure-WindowsFormsLoaded { }
		Mock Import-VirtualDesktopModule { $true }
		Mock Start-FancyZones { $true }
		Mock Get-MonitorInfo {
			@(
				[PSCustomObject]@{
					DeviceName = 'TESTMON1'
					Left       = 0
					Top        = 0
					Width      = 1920
					Height     = 1080
				}
			)
		}
		Mock Get-CachedFancyZonesLayouts {
			@{
				'custom-layouts' = @(
					[PSCustomObject]@{ name = 'One'; uuid = '{11111111-1111-1111-1111-111111111111}' }
				)
			}
		}
		Mock Format-Table { }

		# Isolate idempotency tests from the host's real monitors: GetMonitorDeviceInfo cannot
		# be mocked (static native call), so on a machine with duplicate-EDID monitors the
		# duplicate guard would disable idempotency. Force "no duplicates" for deterministic runs.
		Mock Get-DuplicateMonitorEdid { @() }

		# Single virtual desktop GUID in registry bytes for idempotency lookup
		$guid = [Guid]'11111111-1111-1111-1111-111111111111'
		Mock Get-ItemProperty {
			[PSCustomObject]@{
				VirtualDesktopIDs = $guid.ToByteArray()
			}
		}

		$script:WindowModuleDelays = @{
			CursorSettleMs     = 0
			FocusSettleMs      = 0
			KeyboardShortcutMs = 0
			LayoutCommitMs     = 0
		}

		$script:AppliedLayoutsCache = @{
			Data      = $null
			Timestamp = [datetime]::MinValue
		}

		$global:Configuration = @{
			LayoutNumbers = @{
				One = 1
			}
		}
	}

	It "uses per-desktop string layout and marks monitor as Already Applied when state matches" {
		$monitorConfig = @{
			Primary = @{
				X = 0; Y = 0; Width = 1920; Height = 1080
				VirtualDesktopLayouts = @{
					1 = 'One'
				}
			}
		}

		$appliedKey = 'TESTMON1:{11111111-1111-1111-1111-111111111111}'
		Mock Get-AppliedFancyZonesState {
			@{ $appliedKey = '{11111111-1111-1111-1111-111111111111}' }
		}

		$null = Apply-FancyZones -MonitorConfig $monitorConfig -DesktopNumber 1

		Should -Invoke Get-CachedFancyZonesLayouts -Times 1 -Exactly
		Should -Invoke Get-ItemProperty -Times 1 -Exactly
		Should -Invoke Write-Warning -Times 0
		Should -Invoke Start-Sleep -Times 0
	}

	It "reports Layout Number Unknown when layout name is missing from configuration mapping" {
		$monitorConfig = @{
			Primary = @{
				X = 0; Y = 0; Width = 1920; Height = 1080
				VirtualDesktopLayouts = @{
					1 = 'MissingLayout'
				}
			}
		}

		Mock Get-AppliedFancyZonesState { @{} }

		$null = Apply-FancyZones -MonitorConfig $monitorConfig -DesktopNumber 1

		Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter { $Message -like "*Layout 'MissingLayout' not found in configuration*" }
	}

	It "returns the per-monitor outcome records produced inside the apply scriptblock (scope regression)" {
		$monitorConfig = @{
			Primary = @{
				X = 0; Y = 0; Width = 1920; Height = 1080
				VirtualDesktopLayouts = @{
					1 = 'MissingLayout'
				}
			}
		}

		Mock Get-AppliedFancyZonesState { @{} }

		$results = @(Apply-FancyZones -MonitorConfig $monitorConfig -DesktopNumber 1)

		# Records appended INSIDE the $applyLayouts scriptblock used to be silently lost
		# (`+=` on a scriptblock parameter rebinds a scope-local copy), which kept the
		# caller's result set empty and made the applied-layouts cache invalidation dead
		# code. The record must survive into the function's return value.
		@($results | Where-Object { $_.Status -eq 'Layout Number Unknown' }).Count | Should -Be 1
	}
}
