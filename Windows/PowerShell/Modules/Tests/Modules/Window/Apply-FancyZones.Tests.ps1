#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Apply-FancyZones.ps1"
	. "$FunctionsPath\ConvertTo-InternalDesktopIndex.ps1"
	. "$FunctionsPath\Get-DuplicateMonitorEdid.ps1"
	. "$FunctionsPath\Get-VirtualDesktopGuid.ps1"
	. "$FunctionsPath\Get-MonitorDeviceIdentityMap.ps1"
	. "$FunctionsPath\Write-AppliedFancyZonesLayouts.ps1"
	. "$FunctionsPath\Test-AppliedFancyZonesLayouts.ps1"
	. "$FunctionsPath\Send-FancyZonesLayoutShortcut.ps1"

	# VirtualDesktop module cmdlets and the retry helpers as stubs, so Mock can attach on a machine
	# (or CI runner) where the module is absent. The file-mode context mocks every one of them.
	function Get-CurrentDesktop { }
	function Get-DesktopIndex { param($Desktop) }
	function Get-DesktopList { }
	function Switch-Desktop { param($Desktop) }
	function Invoke-WithRetry { param([scriptblock]$ScriptBlock, $MaxAttempts, $InitialDelayMs, $OnRetry) & $ScriptBlock }
	function Wait-DesktopSwitch { param($TargetDesktopIndex, $TimeoutMs, $PollIntervalMs) $true }
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
			CursorSettleMs         = 0
			FocusSettleMs          = 0
			KeyboardShortcutMs     = 0
			LayoutCommitMs         = 0
			AppliedLayoutsReloadMs = 0
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
		# The desktop GUID lookup goes through Get-VirtualDesktopGuid, one registry read per
		# desktop plus the read that finds the end of the list - two for the single fixture GUID.
		Should -Invoke Get-ItemProperty -Times 2 -Exactly
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

	It "skips the applied-layouts idempotency read entirely when -Force is specified" {
		# The applied-layouts state is read once up front and drives both the per-desktop
		# pre-check and the per-monitor skip. -Force must not read it at all: that file
		# records what FancyZones was LAST told to apply, not what its live zone grid
		# actually is, so a stale record would suppress the very re-send -Force exists for.
		#
		# The monitor deliberately matches no physical monitor, so the loop bails at
		# "Monitor Not Found" before the layout hotkey would be injected - this test must
		# never fire a real Win+Ctrl+Alt+N at the machine running the suite.
		$monitorConfig = @{
			Primary = @{
				X                     = 0; Y = 0; Width = 3440; Height = 1440
				VirtualDesktopLayouts = @{
					1 = 'One'
				}
			}
		}

		$appliedKey = 'TESTMON1:{11111111-1111-1111-1111-111111111111}'
		Mock Get-AppliedFancyZonesState {
			@{ $appliedKey = '{11111111-1111-1111-1111-111111111111}' }
		}

		$results = @(Apply-FancyZones -MonitorConfig $monitorConfig -DesktopNumber 1 -Force)

		Should -Invoke Get-AppliedFancyZonesState -Times 0 -Exactly
		Should -Invoke Get-CachedFancyZonesLayouts -Times 0 -Exactly
		@($results | Where-Object { $_.Status -eq 'Already Applied' }).Count | Should -Be 0
	}

	It "reads the applied-layouts state without -Force (idempotency remains the default)" {
		$monitorConfig = @{
			Primary = @{
				X                     = 0; Y = 0; Width = 3440; Height = 1440
				VirtualDesktopLayouts = @{
					1 = 'One'
				}
			}
		}

		Mock Get-AppliedFancyZonesState { @{} }

		$null = Apply-FancyZones -MonitorConfig $monitorConfig -DesktopNumber 1

		Should -Invoke Get-AppliedFancyZonesState -Times 1 -Exactly
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

	Context "Applied-layouts file mode" {
		BeforeEach {
			# Two virtual desktops, desktop 0 current. Every FancyZones-facing helper is mocked so
			# nothing reaches the real applied-layouts.json, the cursor or the keyboard, and the
			# VirtualDesktop cmdlets are mocked so no desktop is switched.
			$script:D1 = '{11111111-1111-1111-1111-111111111111}'
			$script:D2 = '{22222222-2222-2222-2222-222222222222}'
			$script:D3 = '{33333333-3333-3333-3333-333333333333}'

			Mock Get-CurrentDesktop { 'desktop-object' }
			Mock Get-DesktopIndex { 0 }
			Mock Get-DesktopList { @([PSCustomObject]@{ Number = 0; Name = 'Desktop 1' }, [PSCustomObject]@{ Number = 1; Name = 'Desktop 2' }) }
			Mock Invoke-WithRetry { param([scriptblock]$ScriptBlock, $MaxAttempts, $InitialDelayMs, $OnRetry) & $ScriptBlock }
			Mock Switch-Desktop { }
			Mock Wait-DesktopSwitch { $true }
			Mock Get-VirtualDesktopGuid {
				param($DesktopIndex)
				switch ($DesktopIndex) { 0 { $script:D1 } 1 { $script:D2 } 2 { $script:D3 } default { $null } }
			}
			Mock Get-MonitorDeviceIdentityMap { [PSCustomObject]@{ Edid = @{ TESTMON1 = 'TESTMON' }; Instance = @{ TESTMON1 = '4&ABC&0&UID1' } } }
			Mock Get-AppliedFancyZonesState { @{} }
			Mock Send-FancyZonesLayoutShortcut { }

			$script:writeCalls = @()
			Mock Write-AppliedFancyZonesLayouts {
				param($Targets, [switch]$Force, $AppliedLayoutsPath, $CustomLayoutsPath)
				$script:writeCalls += [PSCustomObject]@{ Targets = @($Targets); Force = [bool]$Force }
				[PSCustomObject]@{
					Written             = $true
					WrittenAtUtc        = [datetime]::UtcNow
					Path                = 'applied-layouts.json'
					WrittenCount        = @($Targets).Count
					AlreadyAppliedCount = 0
					UnresolvedCount     = 0
					Error               = $null
					Targets             = @($Targets | ForEach-Object {
							[PSCustomObject]@{ Monitor = $_.Monitor; MonitorInstance = $_.MonitorInstance; VirtualDesktop = $_.VirtualDesktop; LayoutName = $_.LayoutName; Uuid = '{AAAAAAAA-0000-0000-0000-000000000001}'; Label = $_.Label; Status = 'Written' }
						})
				}
			}

			# Default verifier: FancyZones saved after the probe and every entry survived.
			$script:verifyStatusByDesktop = @{}
			Mock Test-AppliedFancyZonesLayouts {
				param($Targets, $WaitForWriteAfterUtc, $TimeoutMs, $PollIntervalMs, $AppliedLayoutsPath)
				$records = @($Targets | ForEach-Object {
						$status = if ($script:verifyStatusByDesktop.ContainsKey($_.VirtualDesktop)) { $script:verifyStatusByDesktop[$_.VirtualDesktop] } else { 'Verified' }
						[PSCustomObject]@{ Monitor = $_.Monitor; MonitorInstance = $_.MonitorInstance; VirtualDesktop = $_.VirtualDesktop; Uuid = $_.Uuid; Label = $_.Label; Status = $status; ActualUuid = $_.Uuid }
					})
				$verified = @($records | Where-Object { $_.Status -eq 'Verified' }).Count
				[PSCustomObject]@{ SaveObserved = $true; Readable = $true; AllVerified = ($verified -eq $records.Count); VerifiedCount = $verified; Targets = $records }
			}

			$script:monitorConfig = @{
				Primary = @{
					X = 0; Y = 0; Width = 1920; Height = 1080
					VirtualDesktopLayouts = @{ 1 = 'One'; 2 = 'One' }
				}
			}
		}

		It "writes one entry per owned desktop and switches to no desktop when FancyZones verifies them all" {
			$results = @(Apply-FancyZones -MonitorConfig $script:monitorConfig)

			Should -Invoke Write-AppliedFancyZonesLayouts -Times 1 -Exactly
			$targets = $script:writeCalls[0].Targets
			$targets.Count | Should -Be 2
			@($targets | ForEach-Object VirtualDesktop) | Should -Be @($script:D1, $script:D2)
			$targets[0].Monitor | Should -Be 'TESTMON'
			$targets[0].MonitorInstance | Should -Be '4&ABC&0&UID1'
			$targets[0].LayoutName | Should -Be 'One'
			$script:writeCalls[0].Force | Should -BeFalse

			# One probe shortcut on the current desktop, verified against FancyZones' own save.
			Should -Invoke Send-FancyZonesLayoutShortcut -Times 1 -Exactly -ParameterFilter { $LayoutNumber -eq 1 }
			Should -Invoke Test-AppliedFancyZonesLayouts -Times 1 -Exactly -ParameterFilter { $null -ne $WaitForWriteAfterUtc }
			Should -Invoke Switch-Desktop -Times 0 -Exactly
			@($results | Where-Object { $_.Status -eq 'Layout Written' }).Count | Should -Be 2
			@($results | Where-Object { $_.Status -eq 'Shortcut Sent' }).Count | Should -Be 0
		}

		It "falls back to the shortcut pass for a desktop whose entry did not survive FancyZones' save" {
			$script:verifyStatusByDesktop[$script:D2] = 'Missing'

			$results = @(Apply-FancyZones -MonitorConfig $script:monitorConfig)

			# Desktop 1 verified through the file; desktop 2 gets the switch + shortcut, then the pass
			# returns to the original desktop and re-applies there as it always did.
			@($results | Where-Object { $_.Status -eq 'Layout Written' }).Count | Should -Be 1
			@($results | Where-Object { $_.Status -eq 'Shortcut Sent' -and $_.DesktopNumber -eq 2 }).Count | Should -Be 1
			Should -Invoke Switch-Desktop -Times 1 -Exactly -ParameterFilter { $Desktop -eq 1 }
			Should -Invoke Switch-Desktop -Times 2 -Exactly
			Should -Invoke Send-FancyZonesLayoutShortcut -Times 3 -Exactly
		}

		It "uses the shortcut pass for every desktop when FancyZones does not save after the probe" {
			Mock Test-AppliedFancyZonesLayouts {
				param($Targets, $WaitForWriteAfterUtc, $TimeoutMs, $PollIntervalMs, $AppliedLayoutsPath)
				[PSCustomObject]@{ SaveObserved = $false; Readable = $true; AllVerified = $false; VerifiedCount = 0; Targets = @() }
			}

			$results = @(Apply-FancyZones -MonitorConfig $script:monitorConfig)

			@($results | Where-Object { $_.Status -eq 'Layout Written' }).Count | Should -Be 0
			# Both desktops switched to, plus the switch back; probe + two desktops + the return re-apply.
			Should -Invoke Switch-Desktop -Times 3 -Exactly
			Should -Invoke Send-FancyZonesLayoutShortcut -Times 4 -Exactly
			@($results | Where-Object { $_.Status -eq 'Shortcut Sent' }).Count | Should -Be 3
		}

		It "uses the shortcut pass alone when FancyZonesApplyMethod is Hotkeys" {
			$global:Configuration.FancyZonesApplyMethod = 'Hotkeys'

			$results = @(Apply-FancyZones -MonitorConfig $script:monitorConfig)

			Should -Invoke Write-AppliedFancyZonesLayouts -Times 0 -Exactly
			Should -Invoke Test-AppliedFancyZonesLayouts -Times 0 -Exactly
			Should -Invoke Switch-Desktop -Times 3 -Exactly
			@($results | Where-Object { $_.Status -eq 'Shortcut Sent' }).Count | Should -Be 3
		}

		It "rewrites the file under -Force and still proves it through the probe" {
			$results = @(Apply-FancyZones -MonitorConfig $script:monitorConfig -Force)

			$script:writeCalls[0].Force | Should -BeTrue
			Should -Invoke Get-AppliedFancyZonesState -Times 0 -Exactly
			Should -Invoke Send-FancyZonesLayoutShortcut -Times 1 -Exactly
			Should -Invoke Switch-Desktop -Times 0 -Exactly
			@($results | Where-Object { $_.Status -eq 'Layout Written' }).Count | Should -Be 2
		}

		It "leaves a monitor without an EDID mapping to the shortcut pass" {
			Mock Get-MonitorDeviceIdentityMap { [PSCustomObject]@{ Edid = @{}; Instance = @{} } }

			$results = @(Apply-FancyZones -MonitorConfig $script:monitorConfig)

			Should -Invoke Write-AppliedFancyZonesLayouts -Times 0 -Exactly
			Should -Invoke Switch-Desktop -Times 3 -Exactly
			@($results | Where-Object { $_.Status -eq 'Shortcut Sent' }).Count | Should -Be 3
		}

		It "probes on the first owned desktop when the current desktop lies outside a DesktopOffset range" {
			Mock Get-DesktopList { @(0, 1, 2 | ForEach-Object { [PSCustomObject]@{ Number = $_; Name = "Desktop $($_ + 1)" } }) }

			$results = @(Apply-FancyZones -MonitorConfig $script:monitorConfig -DesktopOffset 1 -DesktopCount 2)

			$targets = $script:writeCalls[0].Targets
			@($targets | ForEach-Object VirtualDesktop) | Should -Be @($script:D2, $script:D3)
			@($targets | ForEach-Object LayoutKey) | Should -Be @(1, 2)
			# One switch, to the first owned desktop for the probe - where the shortcut pass would
			# have ended anyway - and none afterwards.
			Should -Invoke Switch-Desktop -Times 1 -Exactly -ParameterFilter { $Desktop -eq 1 }
			Should -Invoke Send-FancyZonesLayoutShortcut -Times 1 -Exactly
			@($results | Where-Object { $_.Status -eq 'Layout Written' }).Count | Should -Be 2
		}
	}
}
