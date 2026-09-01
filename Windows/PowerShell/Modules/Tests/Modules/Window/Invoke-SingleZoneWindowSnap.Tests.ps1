#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Invoke-SingleZoneWindowSnap.ps1"

	# Compile the native layer exactly as Window.psm1 does, so this suite also guards
	# WindowNative.cs against compile regressions. No test in this suite can reach
	# SendSnapKey/ShiftDragSnap: the fake handles never match the real foreground window, so
	# the atomic pre-injection re-check always bails first - no synthetic input is ever sent.
	if (-not ([System.Management.Automation.PSTypeName]'WindowModule.Native').Type) {
		$nativePath = Join-Path $ModuleRoot "Window\WindowNative.cs"
		$nativeCode = Get-Content -Path $nativePath -Raw
		Add-Type -TypeDefinition $nativeCode -Language CSharp -ErrorAction Stop
	}

	# Stubbed so Mock can attach in a dot-sourced unit; each has its own suite. The param
	# blocks mirror the real signatures so -ParameterFilter can match by name.
	function Get-WindowFrameMargin { param([IntPtr]$WindowHandle) }
	function Get-FancyZonesWindowAssignment { param([IntPtr]$WindowHandle) }
	function Clear-FancyZonesWindowAssignment { param([IntPtr]$WindowHandle) }
	function Wait-WindowRect { param([IntPtr]$WindowHandle, [int]$ExpectedX, [int]$ExpectedY, [int]$ExpectedWidth, [int]$ExpectedHeight, [int]$TolerancePx, [int]$TimeoutMs, [int]$PollIntervalMs) }
	function Confirm-WindowForeground { param([IntPtr]$WindowHandle, [int]$BaseSettleMs) }
	function Reset-KeyboardModifiers { param([switch]$IncludeMouseButton) }
	function Resize-Windows { param([IntPtr]$WindowHandle, [int]$TargetX, [int]$TargetY, [int]$TargetWidth, [int]$TargetHeight, [double]$InsetPercent) }
	function Get-WindowInsetPercent { }
}

Describe "Invoke-SingleZoneWindowSnap" {
	BeforeEach {
		Mock Write-Host { }
		Mock Write-LogDebug { }
		Mock Test-LogVerbose { $false }

		# Borderless, unassigned, unfocusable defaults; individual tests override.
		Mock Get-WindowFrameMargin { [PSCustomObject]@{ Left = 0; Top = 0; Right = 0; Bottom = 0 } }
		Mock Get-FancyZonesWindowAssignment { [uint64]0 }
		Mock Clear-FancyZonesWindowAssignment { $false }
		Mock Wait-WindowRect { [PSCustomObject]@{ Verified = $false; X = 0; Y = 0; Width = 1; Height = 1; ElapsedMs = 1 } }
		Mock Confirm-WindowForeground { $false }
		Mock Reset-KeyboardModifiers { @() }
		Mock Resize-Windows { $null }
		Mock Get-WindowInsetPercent { 0.05 }
	}

	It "clears a stale FancyZones assignment so the keyboard snap can resolve" {
		Mock Get-FancyZonesWindowAssignment { [uint64]1 }

		$null = Invoke-SingleZoneWindowSnap -WindowHandle ([IntPtr]201) -TargetX 10 -TargetY 20 -TargetWidth 300 -TargetHeight 400 -InsetPercent 0.05

		Should -Invoke Clear-FancyZonesWindowAssignment -Times 1 -Exactly
	}

	It "never clears anything for an unassigned window" {
		$null = Invoke-SingleZoneWindowSnap -WindowHandle ([IntPtr]202) -TargetX 10 -TargetY 20 -TargetWidth 300 -TargetHeight 400 -InsetPercent 0.05

		Should -Invoke Clear-FancyZonesWindowAssignment -Times 0 -Exactly
	}

	It "centers the window at double the shared inset before every attempt" {
		$null = Invoke-SingleZoneWindowSnap -WindowHandle ([IntPtr]203) -TargetX 10 -TargetY 20 -TargetWidth 300 -TargetHeight 400 -InsetPercent 0.05

		# One centering per attempt (focus never sticks, so the drag re-center is not reached).
		Should -Invoke Resize-Windows -Times 3 -Exactly -ParameterFilter {
			$TargetX -eq 10 -and $TargetY -eq 20 -and $TargetWidth -eq 300 -and $TargetHeight -eq 400 -and $InsetPercent -eq 0.1
		}
	}

	It "caps the deeper inset at 20% per side" {
		$null = Invoke-SingleZoneWindowSnap -WindowHandle ([IntPtr]204) -TargetX 10 -TargetY 20 -TargetWidth 300 -TargetHeight 400 -InsetPercent 0.15

		Should -Invoke Resize-Windows -Times 3 -Exactly -ParameterFilter { $InsetPercent -eq 0.2 }
	}

	It "reports failure with Method None when every attempt is exhausted" {
		$result = Invoke-SingleZoneWindowSnap -WindowHandle ([IntPtr]205) -TargetX 10 -TargetY 20 -TargetWidth 300 -TargetHeight 400 -InsetPercent 0.05

		$result.Verified | Should -BeFalse
		$result.Method | Should -Be 'None'
		$result.Attempts | Should -Be 3
		Should -Invoke Confirm-WindowForeground -Times 3 -Exactly
	}

	It "honors MaxAttempts" {
		$null = Invoke-SingleZoneWindowSnap -WindowHandle ([IntPtr]206) -TargetX 10 -TargetY 20 -TargetWidth 300 -TargetHeight 400 -MaxAttempts 1 -InsetPercent 0.05

		Should -Invoke Confirm-WindowForeground -Times 1 -Exactly
	}

	It "resets stuck modifiers between attempts" {
		$null = Invoke-SingleZoneWindowSnap -WindowHandle ([IntPtr]207) -TargetX 10 -TargetY 20 -TargetWidth 300 -TargetHeight 400 -InsetPercent 0.05

		# Attempts 2 and 3 each clear the keyboard first.
		Should -Invoke Reset-KeyboardModifiers -Times 2 -Exactly
	}

	It "returns every contract field" {
		$result = Invoke-SingleZoneWindowSnap -WindowHandle ([IntPtr]208) -TargetX 10 -TargetY 20 -TargetWidth 300 -TargetHeight 400 -InsetPercent 0.05

		foreach ($name in 'Verified', 'Registered', 'Method', 'Attempts', 'X', 'Y', 'Width', 'Height') {
			$result.PSObject.Properties.Name | Should -Contain $name
		}
	}
}
