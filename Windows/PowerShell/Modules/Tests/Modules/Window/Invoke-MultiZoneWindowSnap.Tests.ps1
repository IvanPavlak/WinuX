#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Invoke-MultiZoneWindowSnap.ps1"

	# Compile the native layer exactly as Window.psm1 does. No test in this suite can reach
	# SendSnapKey/ShiftDragSnap: the fake handles never match the real foreground window, so
	# the atomic pre-injection re-check always bails first - no synthetic input is ever sent.
	if (-not ([System.Management.Automation.PSTypeName]'WindowModule.Native').Type) {
		$nativePath = Join-Path $ModuleRoot "Window\WindowNative.cs"
		$nativeCode = Get-Content -Path $nativePath -Raw
		Add-Type -TypeDefinition $nativeCode -Language CSharp -ErrorAction Stop
	}

	# Stubbed so Mock can attach in a dot-sourced unit; each has its own suite. The param
	# blocks mirror the real signatures so -ParameterFilter can match by name.
	function Wait-WindowRect { param([IntPtr]$WindowHandle, [int]$ExpectedX, [int]$ExpectedY, [int]$ExpectedWidth, [int]$ExpectedHeight, [int]$TolerancePx, [int]$TimeoutMs, [int]$PollIntervalMs) }
	function Confirm-WindowForeground { param([IntPtr]$WindowHandle, [int]$BaseSettleMs) }
	function Reset-KeyboardModifiers { param([switch]$IncludeMouseButton) }
	function Resize-Windows { param([IntPtr]$WindowHandle, [int]$TargetX, [int]$TargetY, [int]$TargetWidth, [int]$TargetHeight, [double]$InsetPercent) }
	function Get-WindowInsetPercent { }
}

Describe "Invoke-MultiZoneWindowSnap" {
	BeforeEach {
		Mock Write-Host { }
		Mock Write-Warning { }
		Mock Write-LogDebug { }
		Mock Test-LogVerbose { $false }
		Mock Start-Sleep { }

		# Unfocusable defaults; individual tests override.
		Mock Wait-WindowRect { [PSCustomObject]@{ Verified = $false; X = 0; Y = 0; Width = 1; Height = 1; ElapsedMs = 1 } }
		Mock Confirm-WindowForeground { $false }
		Mock Reset-KeyboardModifiers { @() }
		Mock Resize-Windows { $null }
		Mock Get-WindowInsetPercent { 0.05 }
	}

	It "reports failure with Method None and the full attempt count when focus never sticks" {
		$result = Invoke-MultiZoneWindowSnap -WindowHandle ([IntPtr]301) -ExpectedX 10 -ExpectedY 20 -ExpectedWidth 300 -ExpectedHeight 400 -WindowTitle 'App'

		$result.Verified | Should -BeFalse
		$result.Method | Should -Be 'None'
		$result.Attempts | Should -Be 3
		$result.Error | Should -BeNullOrEmpty
		# The rect was never read: no attempt got as far as the snap key.
		$result.X | Should -BeNullOrEmpty
		Should -Invoke Confirm-WindowForeground -Times 3 -Exactly
		Should -Invoke Wait-WindowRect -Times 0 -Exactly
	}

	It "grows the focus settle on every attempt" {
		$null = Invoke-MultiZoneWindowSnap -WindowHandle ([IntPtr]302) -ExpectedX 10 -ExpectedY 20 -ExpectedWidth 300 -ExpectedHeight 400

		Should -Invoke Confirm-WindowForeground -Times 1 -Exactly -ParameterFilter { $BaseSettleMs -eq 10 }
		Should -Invoke Confirm-WindowForeground -Times 1 -Exactly -ParameterFilter { $BaseSettleMs -eq 50 }
		Should -Invoke Confirm-WindowForeground -Times 1 -Exactly -ParameterFilter { $BaseSettleMs -eq 90 }
	}

	It "clears the modifiers and re-insets the window before every retry, never before the first attempt" {
		$null = Invoke-MultiZoneWindowSnap -WindowHandle ([IntPtr]303) -ExpectedX 10 -ExpectedY 20 -ExpectedWidth 300 -ExpectedHeight 400 -InsetPercent 0.05

		Should -Invoke Reset-KeyboardModifiers -Times 2 -Exactly
		# One re-inset per retry (focus never sticks, so the pre-drag re-inset is not reached).
		Should -Invoke Resize-Windows -Times 2 -Exactly -ParameterFilter {
			$WindowHandle -eq [IntPtr]303 -and $TargetX -eq 10 -and $TargetY -eq 20 -and $TargetWidth -eq 300 -and $TargetHeight -eq 400 -and $InsetPercent -eq 0.05
		}
	}

	It "honours -MaxAttempts" {
		$result = Invoke-MultiZoneWindowSnap -WindowHandle ([IntPtr]304) -ExpectedX 10 -ExpectedY 20 -ExpectedWidth 300 -ExpectedHeight 400 -MaxAttempts 1

		$result.Attempts | Should -Be 1
		Should -Invoke Confirm-WindowForeground -Times 1 -Exactly
		Should -Invoke Reset-KeyboardModifiers -Times 0 -Exactly
		Should -Invoke Resize-Windows -Times 0 -Exactly
	}

	It "never injects the snap key when the atomic foreground re-check fails" {
		# Focus "acquired", but the fake handle can never be the real foreground window, so the
		# re-check right before injection bails - the guard that keeps a chord off the wrong window.
		Mock Confirm-WindowForeground { $true }

		$result = Invoke-MultiZoneWindowSnap -WindowHandle ([IntPtr]305) -ExpectedX 10 -ExpectedY 20 -ExpectedWidth 300 -ExpectedHeight 400

		$result.Verified | Should -BeFalse
		Should -Invoke Wait-WindowRect -Times 0 -Exactly
	}

	It "surfaces the last attempt's exception in Error and still reports every attempt" {
		Mock Confirm-WindowForeground { throw 'focus exploded' }

		$result = Invoke-MultiZoneWindowSnap -WindowHandle ([IntPtr]306) -ExpectedX 10 -ExpectedY 20 -ExpectedWidth 300 -ExpectedHeight 400

		$result.Verified | Should -BeFalse
		$result.Attempts | Should -Be 3
		$result.Error | Should -BeLike '*focus exploded*'
	}
}
