#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Snap-AllWindows.ps1"
	. "$FunctionsPath\Get-PositionedWindowCount.ps1"
	. "$FunctionsPath\ConvertTo-InternalDesktopIndex.ps1"
	. "$FunctionsPath\Get-InsetWindowBounds.ps1"

	# Compile the native layer exactly as Window.psm1 does: the positioned-windows pass reads
	# the tracked window's process, rect and title through it before any snap helper runs.
	if (-not ([System.Management.Automation.PSTypeName]'WindowModule.Native').Type) {
		$nativePath = Join-Path $ModuleRoot "Window\WindowNative.cs"
		$nativeCode = Get-Content -Path $nativePath -Raw
		Add-Type -TypeDefinition $nativeCode -Language CSharp -ErrorAction Stop
	}

	# Those native reads cannot be mocked, so the tracked "window" is a real one: a hidden
	# WinForms form owned by this process. Its handle is created without ever showing it, it
	# has a title and a rect, and it belongs to $PID, so the pre-snap fingerprint, rect and
	# title checks all pass exactly as they do for a workspace window. The snap helpers that
	# would send input are mocked, so no synthetic input is ever sent.
	Add-Type -AssemblyName System.Windows.Forms
	Add-Type -AssemblyName System.Drawing
	$script:TestForm = New-Object System.Windows.Forms.Form
	$script:TestForm.Text = 'Snap-AllWindows test window'
	$script:TestForm.StartPosition = 'Manual'
	$script:TestForm.Location = New-Object System.Drawing.Point(100, 100)
	$script:TestForm.Size = New-Object System.Drawing.Size(400, 300)
	$script:TestForm.ShowInTaskbar = $false
	$script:TestHandle = $script:TestForm.Handle
	$formRect = New-Object WindowModule.RECT
	[void][WindowModule.Native]::GetWindowRect($script:TestHandle, [ref]$formRect)
	$script:FormLeft = $formRect.Left
	$script:FormTop = $formRect.Top
	$script:FormWidth = $formRect.Right - $formRect.Left
	$script:FormHeight = $formRect.Bottom - $formRect.Top

	# Stubbed so Mock can attach in a dot-sourced unit and without the VirtualDesktop module.
	# The param blocks mirror the real signatures so -ParameterFilter can match by name.
	function Get-WindowInsetPercent { }
	function Invoke-MultiZoneWindowSnap { param([IntPtr]$WindowHandle, [int]$ExpectedX, [int]$ExpectedY, [int]$ExpectedWidth, [int]$ExpectedHeight, [string]$WindowTitle, [int]$MaxAttempts, [double]$InsetPercent) }
	function Invoke-SingleZoneWindowSnap { param([IntPtr]$WindowHandle, [int]$TargetX, [int]$TargetY, [int]$TargetWidth, [int]$TargetHeight, [string]$WindowTitle, [int]$MaxAttempts, [double]$InsetPercent) }
	function Switch-Desktop { [CmdletBinding()] param($Desktop) }
	function Wait-DesktopSwitch { [CmdletBinding()] param([int]$TargetDesktopIndex, [int]$TimeoutMs, [int]$PollIntervalMs) }
	function Get-DesktopFromWindow { [CmdletBinding()] param($Hwnd) }
	function Get-DesktopIndex { [CmdletBinding()] param($Desktop) }
	function Reset-VirtualDesktopState { }
	function Move-WindowToVirtualDesktop { [CmdletBinding()] param([IntPtr]$WindowHandle, [int]$DesktopNumber) }
	function Get-WindowDesktopIndex { param([IntPtr]$WindowHandle) }
	function Get-CachedMonitors { }
	function Clear-WindowCache { }
	function Clear-MonitorCache { }
	function Resolve-PositionedWindowHandle { param($WindowState) }
	function Resize-Windows { param([IntPtr]$WindowHandle, [int]$TargetX, [int]$TargetY, [int]$TargetWidth, [int]$TargetHeight, [double]$InsetPercent) }
	function Reset-KeyboardModifiers { param([switch]$IncludeMouseButton) }
	function Test-FancyZonesLayoutApplied { param($VirtualDesktopGuid) }
	function Get-VirtualDesktopGuid { param([int]$DesktopIndex) }

	# One tracked entry for the test form. Several entries may share the handle - the pass
	# processes entries, and the form passes every pre-snap check each time.
	function Add-TestTrackedWindow {
		param([int]$Desktop = 1, [switch]$SingleZone)
		$script:PositionedWindowHandles.Add(@{
				Handle         = $script:TestHandle
				ExpectedX      = $script:FormLeft
				ExpectedY      = $script:FormTop
				ExpectedWidth  = $script:FormWidth
				ExpectedHeight = $script:FormHeight
				WindowTitle    = 'Snap-AllWindows test window'
				DesktopNumber  = $Desktop
				ProcessName    = 'pwsh'
				ProcessId      = [uint32]$PID
				SingleZone     = [bool]$SingleZone
			}) > $null
	}
}

AfterAll {
	if ($script:TestForm) { $script:TestForm.Dispose() }
}

Describe "Snap-AllWindows" {
	BeforeEach {
		Mock Write-Host { }
		Mock Write-Warning { }
		Mock Write-LogDebug { }
		Mock Write-LogWarning { }
		Mock Write-LogError { }
		Mock Test-LogVerbose { $false }
		Mock Start-Sleep { }
		Mock Ensure-WindowsFormsLoaded { }
		Mock Start-FancyZones { $true }
		# Zero inset: the adjusted pre-snap bounds equal the expected bounds, and the form sits
		# exactly at its own rect, so the position check passes without moving anything.
		Mock Get-WindowInsetPercent { 0 }
		Mock Reset-KeyboardModifiers { @() }
		Mock Get-Process { @([PSCustomObject]@{ ProcessName = 'PowerToys.FancyZones' }) }
		Mock Switch-Desktop { }
		Mock Wait-DesktopSwitch { $true }
		Mock Clear-WindowCache { }
		Mock Clear-MonitorCache { }
		Mock Get-CachedMonitors { @([PSCustomObject]@{ Bounds = [PSCustomObject]@{ Left = -100000; Top = -100000; Right = 100000; Bottom = 100000 } }) }
		Mock Get-DesktopFromWindow { 'desktop' }
		# The window reports the desktop being processed, so no realignment move is needed.
		Mock Get-DesktopIndex { $script:ProcessingDesktopIndex }
		Mock Move-WindowToVirtualDesktop { $true }
		# Post-pass sweep: "cannot tell" leaves every window alone.
		Mock Get-WindowDesktopIndex { -1 }
		Mock Resize-Windows { }
		Mock Resolve-PositionedWindowHandle { $null }
		Mock Invoke-MultiZoneWindowSnap { [PSCustomObject]@{ Verified = $true; Method = 'KeyboardSnap'; Attempts = 1; X = 0; Y = 0; Width = 1; Height = 1; Error = $null } }
		Mock Invoke-SingleZoneWindowSnap { [PSCustomObject]@{ Verified = $true; Registered = $true; Method = 'KeyboardSnap'; Attempts = 1; X = 0; Y = 0; Width = 1; Height = 1 } }

		# Module-scoped tables the function reads; in a dot-sourced unit they live in this file's
		# scope. The pre-snap position check compares against PreSnapValidationPx, and the
		# inset helper offsets the target by a 2 px bias, so without a tolerance every window
		# would read as "moved after positioning" and be skipped before any snap helper ran.
		$script:WindowModuleTolerances = @{ PositionVerificationPx = 20; PreSnapValidationPx = 75 }
		$script:WindowModuleDelays = @{ CursorSettleMs = 0; FocusSettleMs = 0; KeyboardShortcutMs = 0; LayoutCommitMs = 0; WindowRestoreMs = 0; WindowPositionMs = 0; VirtualDesktopMs = 0 }

		$script:ProcessingDesktopIndex = 0
		$script:PositionedWindowHandles = [System.Collections.ArrayList]::new()
		$script:LastSnapAllWindowsResult = $null

		# Caller-supplied zone reset, counted.
		$script:zoneResets = 0
		$script:zoneResetReasons = @()
		$script:zoneReset = { param($Reason) $script:zoneResets++; $script:zoneResetReasons += $Reason }
	}

	It "returns when no positioned windows are tracked" {
		$result = Snap-AllWindows

		$result | Should -BeNullOrEmpty
		Should -Invoke Start-FancyZones -Times 1
		$script:LastSnapAllWindowsResult.SnappedCount | Should -Be 0
	}

	It "snaps a window that verifies in its first round without any reset" {
		Add-TestTrackedWindow -Desktop 1

		Snap-AllWindows -DesktopOffset 0 -ZoneReset $script:zoneReset

		$script:LastSnapAllWindowsResult.SnappedCount | Should -Be 1
		@($script:LastSnapAllWindowsResult.FailedWindows).Count | Should -Be 0
		$script:zoneResets | Should -Be 0
		Should -Invoke Invoke-MultiZoneWindowSnap -Times 1 -Exactly
	}

	Context "Zone-grid reset and second round for an exhausted window" {
		It "resets the zone grid once and retries the SAME window when its attempts are exhausted" {
			Add-TestTrackedWindow -Desktop 1
			$script:multiCalls = 0
			Mock Invoke-MultiZoneWindowSnap {
				$script:multiCalls++
				$verified = ($script:multiCalls -ge 2)
				[PSCustomObject]@{ Verified = $verified; Method = $(if ($verified) { 'ShiftDrag' } else { 'None' }); Attempts = $(if ($verified) { 1 } else { 3 }); X = 5; Y = 5; Width = 10; Height = 10; Error = $null }
			}

			Snap-AllWindows -DesktopOffset 0 -ZoneReset $script:zoneReset

			$script:zoneResets | Should -Be 1
			$script:zoneResetReasons[0] | Should -BeLike '*Snap-AllWindows test window*'
			Should -Invoke Invoke-MultiZoneWindowSnap -Times 2 -Exactly
			# Modifiers and the mouse button are released before the reset, the desktop is
			# re-confirmed after it, and the window goes back to its inset for round two.
			Should -Invoke Reset-KeyboardModifiers -Times 1 -Exactly -ParameterFilter { $IncludeMouseButton }
			Should -Invoke Switch-Desktop -Times 2 -Exactly -ParameterFilter { $Desktop -eq 0 }
			Should -Invoke Resize-Windows -Times 1 -Exactly -ParameterFilter { $WindowHandle -eq $script:TestHandle }
			$script:LastSnapAllWindowsResult.SnappedCount | Should -Be 1
			@($script:LastSnapAllWindowsResult.FailedWindows).Count | Should -Be 0
		}

		It "records one failure when the second round fails too, naming both rounds" {
			Add-TestTrackedWindow -Desktop 1
			Mock Invoke-MultiZoneWindowSnap { [PSCustomObject]@{ Verified = $false; Method = 'None'; Attempts = 3; X = 7; Y = 8; Width = 9; Height = 10; Error = $null } }

			Snap-AllWindows -DesktopOffset 0 -ZoneReset $script:zoneReset

			$script:zoneResets | Should -Be 1
			Should -Invoke Invoke-MultiZoneWindowSnap -Times 2 -Exactly
			$failures = @($script:LastSnapAllWindowsResult.FailedWindows)
			$failures.Count | Should -Be 1
			$failures[0].Error | Should -BeLike '*after 6 attempts*zone grid reset once*'
			$failures[0].Actual | Should -Be '(7, 8) 9x10'
			$script:LastSnapAllWindowsResult.SnappedCount | Should -Be 0
		}

		It "gives the third exhausted window in one pass no reset" {
			Add-TestTrackedWindow -Desktop 1
			Add-TestTrackedWindow -Desktop 1
			Add-TestTrackedWindow -Desktop 1
			Mock Invoke-MultiZoneWindowSnap { [PSCustomObject]@{ Verified = $false; Method = 'None'; Attempts = 3; X = $null; Y = $null; Width = $null; Height = $null; Error = $null } }

			Snap-AllWindows -DesktopOffset 0 -ZoneReset $script:zoneReset

			# Two windows get a reset and a second round (2 + 2 helper calls); the third exhausts
			# once and records straight away (1 call), which also trips the circuit breaker.
			$script:zoneResets | Should -Be 2
			Should -Invoke Invoke-MultiZoneWindowSnap -Times 5 -Exactly
			$failures = @($script:LastSnapAllWindowsResult.FailedWindows)
			$failures.Count | Should -Be 3
			$failures[2].Error | Should -BeLike '*after 3 attempts*'
			$failures[2].Error | Should -Not -BeLike '*zone grid reset*'
		}

		It "restarts FancyZones alone when the caller supplied no -ZoneReset" {
			Add-TestTrackedWindow -Desktop 1
			$script:multiCalls = 0
			Mock Invoke-MultiZoneWindowSnap {
				$script:multiCalls++
				[PSCustomObject]@{ Verified = ($script:multiCalls -ge 2); Method = 'KeyboardSnap'; Attempts = 3; X = 0; Y = 0; Width = 1; Height = 1; Error = $null }
			}

			Snap-AllWindows -DesktopOffset 0

			Should -Invoke Start-FancyZones -Times 1 -Exactly -ParameterFilter { $ForceRestart }
			Should -Invoke Invoke-MultiZoneWindowSnap -Times 2 -Exactly
			$script:LastSnapAllWindowsResult.SnappedCount | Should -Be 1
		}

		It "recovers a single-zone window through the same reset and second round" {
			Add-TestTrackedWindow -Desktop 1 -SingleZone
			$script:singleCalls = 0
			Mock Invoke-SingleZoneWindowSnap {
				$script:singleCalls++
				$verified = ($script:singleCalls -ge 2)
				[PSCustomObject]@{ Verified = $verified; Registered = $verified; Method = 'KeyboardSnap'; Attempts = $(if ($verified) { 1 } else { 3 }); X = 0; Y = 0; Width = 1; Height = 1 }
			}

			Snap-AllWindows -DesktopOffset 0 -ZoneReset $script:zoneReset

			$script:zoneResets | Should -Be 1
			Should -Invoke Invoke-SingleZoneWindowSnap -Times 2 -Exactly
			Should -Invoke Invoke-MultiZoneWindowSnap -Times 0 -Exactly
			$script:LastSnapAllWindowsResult.SnappedCount | Should -Be 1
		}

		It "records the failure without a second round when the desktop cannot be re-confirmed after the reset" {
			Add-TestTrackedWindow -Desktop 1
			Mock Invoke-MultiZoneWindowSnap { [PSCustomObject]@{ Verified = $false; Method = 'None'; Attempts = 3; X = $null; Y = $null; Width = $null; Height = $null; Error = $null } }
			$script:switchWaits = 0
			# First confirmation (the pass entering the desktop) succeeds, the post-reset one fails.
			Mock Wait-DesktopSwitch { $script:switchWaits++; $script:switchWaits -lt 2 }

			Snap-AllWindows -DesktopOffset 0 -ZoneReset $script:zoneReset

			$script:zoneResets | Should -Be 1
			Should -Invoke Invoke-MultiZoneWindowSnap -Times 1 -Exactly
			@($script:LastSnapAllWindowsResult.FailedWindows).Count | Should -Be 1
		}
	}

	Context "-DesktopNumbers" {
		It "restricts the pass to the tracked windows on those desktops" {
			Add-TestTrackedWindow -Desktop 1
			Add-TestTrackedWindow -Desktop 2
			$script:ProcessingDesktopIndex = 1

			Snap-AllWindows -DesktopOffset 0 -DesktopNumbers 2 -ZoneReset $script:zoneReset

			# Only desktop 2 (internal index 1) is switched to and snapped.
			Should -Invoke Switch-Desktop -Times 1 -Exactly
			Should -Invoke Switch-Desktop -Times 1 -Exactly -ParameterFilter { $Desktop -eq 1 }
			Should -Invoke Invoke-MultiZoneWindowSnap -Times 1 -Exactly
			$script:LastSnapAllWindowsResult.SnappedCount | Should -Be 1
		}

		It "processes every tracked window when the filter is omitted" {
			Add-TestTrackedWindow -Desktop 1
			Add-TestTrackedWindow -Desktop 1

			Snap-AllWindows -DesktopOffset 0

			Should -Invoke Invoke-MultiZoneWindowSnap -Times 2 -Exactly
			$script:LastSnapAllWindowsResult.SnappedCount | Should -Be 2
		}
	}
}
