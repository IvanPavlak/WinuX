#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Invoke-SingleZoneWindowPlacement.ps1"

	# Stubbed so Mock can attach in a dot-sourced unit; all three have their own suites. The
	# param blocks mirror the real signatures so -ParameterFilter can match by name.
	function Set-WindowPosition { param([IntPtr]$WindowHandle, [int]$X, [int]$Y, [int]$Width, [int]$Height) }
	function Wait-WindowRect { param([IntPtr]$WindowHandle, [int]$ExpectedX, [int]$ExpectedY, [int]$ExpectedWidth, [int]$ExpectedHeight, [int]$TolerancePx, [int]$TimeoutMs, [int]$PollIntervalMs) }
	function Get-WindowFrameMargin { param([IntPtr]$WindowHandle) }
}

Describe "Invoke-SingleZoneWindowPlacement" {
	BeforeEach {
		Mock Write-Host { }
		Mock Write-LogDebug { }

		# Borderless default, so the tests that are not about frame compensation assert the
		# zone rectangle itself. The compensating cases override this per test.
		Mock Get-WindowFrameMargin { [PSCustomObject]@{ Left = 0; Top = 0; Right = 0; Bottom = 0 } }
	}

	It "verifies on the first attempt when the placement lands" {
		Mock Set-WindowPosition { $true }
		Mock Wait-WindowRect { [PSCustomObject]@{ Verified = $true; X = 0; Y = 0; Width = 2000; Height = 1000; ElapsedMs = 5 } }

		$result = Invoke-SingleZoneWindowPlacement -WindowHandle ([IntPtr]100) -TargetX 0 -TargetY 0 -TargetWidth 2000 -TargetHeight 1000

		$result.Verified | Should -BeTrue
		$result.Attempts | Should -Be 1
		Should -Invoke Set-WindowPosition -Times 1 -Exactly
		Should -Invoke Wait-WindowRect -Times 1 -Exactly
	}

	It "passes the exact zone rect to Set-WindowPosition when the window has no border (no inset, no bias)" {
		Mock Set-WindowPosition { $true }
		Mock Wait-WindowRect { [PSCustomObject]@{ Verified = $true; X = 10; Y = 20; Width = 300; Height = 400; ElapsedMs = 5 } }

		$null = Invoke-SingleZoneWindowPlacement -WindowHandle ([IntPtr]101) -TargetX 10 -TargetY 20 -TargetWidth 300 -TargetHeight 400

		Should -Invoke Set-WindowPosition -Times 1 -Exactly -ParameterFilter {
			$X -eq 10 -and $Y -eq 20 -and $Width -eq 300 -and $Height -eq 400
		}
	}

	It "grows the placement rect by the window's frame margins" {
		# The standard desktop window shape: an invisible border on the left, right and
		# bottom. Placing the frame at the zone would leave the visible window inset by it.
		Mock Get-WindowFrameMargin { [PSCustomObject]@{ Left = 7; Top = 0; Right = 7; Bottom = 7 } }
		Mock Set-WindowPosition { $true }
		Mock Wait-WindowRect { [PSCustomObject]@{ Verified = $true; X = 3; Y = 20; Width = 314; Height = 407; ElapsedMs = 5 } }

		$null = Invoke-SingleZoneWindowPlacement -WindowHandle ([IntPtr]106) -TargetX 10 -TargetY 20 -TargetWidth 300 -TargetHeight 400

		Should -Invoke Set-WindowPosition -Times 1 -Exactly -ParameterFilter {
			$X -eq 3 -and $Y -eq 20 -and $Width -eq 314 -and $Height -eq 407
		}
	}

	It "verifies against the compensated rect, not the zone rect" {
		Mock Get-WindowFrameMargin { [PSCustomObject]@{ Left = 7; Top = 0; Right = 7; Bottom = 7 } }
		Mock Set-WindowPosition { $true }
		Mock Wait-WindowRect { [PSCustomObject]@{ Verified = $true; X = 3; Y = 20; Width = 314; Height = 407; ElapsedMs = 5 } }

		$null = Invoke-SingleZoneWindowPlacement -WindowHandle ([IntPtr]107) -TargetX 10 -TargetY 20 -TargetWidth 300 -TargetHeight 400

		Should -Invoke Wait-WindowRect -Times 1 -Exactly -ParameterFilter {
			$ExpectedX -eq 3 -and $ExpectedY -eq 20 -and $ExpectedWidth -eq 314 -and $ExpectedHeight -eq 407
		}
	}

	It "measures the frame margin once, not per attempt" {
		# Neither the window's style nor its monitor changes between retries.
		Mock Get-WindowFrameMargin { [PSCustomObject]@{ Left = 7; Top = 0; Right = 7; Bottom = 7 } }
		Mock Set-WindowPosition { $true }
		Mock Wait-WindowRect { [PSCustomObject]@{ Verified = $false; X = 0; Y = 0; Width = 1; Height = 1; ElapsedMs = 150 } }

		$null = Invoke-SingleZoneWindowPlacement -WindowHandle ([IntPtr]108) -TargetX 10 -TargetY 20 -TargetWidth 300 -TargetHeight 400

		Should -Invoke Set-WindowPosition -Times 3 -Exactly
		Should -Invoke Get-WindowFrameMargin -Times 1 -Exactly
	}

	It "retries and verifies after a transient failure" {
		$script:waitCalls = 0
		Mock Set-WindowPosition { $true }
		Mock Wait-WindowRect {
			$script:waitCalls++
			if ($script:waitCalls -ge 2) {
				[PSCustomObject]@{ Verified = $true; X = 0; Y = 0; Width = 2000; Height = 1000; ElapsedMs = 5 }
			}
			else {
				[PSCustomObject]@{ Verified = $false; X = 5; Y = 5; Width = 1990; Height = 990; ElapsedMs = 150 }
			}
		}

		$result = Invoke-SingleZoneWindowPlacement -WindowHandle ([IntPtr]102) -TargetX 0 -TargetY 0 -TargetWidth 2000 -TargetHeight 1000

		$result.Verified | Should -BeTrue
		$result.Attempts | Should -Be 2
		Should -Invoke Set-WindowPosition -Times 2 -Exactly
	}

	It "reports failure with the last observed bounds when never verified" {
		Mock Set-WindowPosition { $true }
		Mock Wait-WindowRect { [PSCustomObject]@{ Verified = $false; X = 50; Y = 60; Width = 700; Height = 500; ElapsedMs = 150 } }

		$result = Invoke-SingleZoneWindowPlacement -WindowHandle ([IntPtr]103) -TargetX 0 -TargetY 0 -TargetWidth 2000 -TargetHeight 1000

		$result.Verified | Should -BeFalse
		$result.Attempts | Should -Be 3
		$result.X | Should -Be 50
		$result.Width | Should -Be 700
		Should -Invoke Set-WindowPosition -Times 3 -Exactly
	}

	It "retries when Set-WindowPosition itself fails and reports null bounds when the rect was never read" {
		Mock Set-WindowPosition { $false }
		Mock Wait-WindowRect { }

		$result = Invoke-SingleZoneWindowPlacement -WindowHandle ([IntPtr]104) -TargetX 0 -TargetY 0 -TargetWidth 2000 -TargetHeight 1000

		$result.Verified | Should -BeFalse
		$result.X | Should -BeNullOrEmpty
		Should -Invoke Set-WindowPosition -Times 3 -Exactly
		Should -Invoke Wait-WindowRect -Times 0 -Exactly
	}

	It "honors MaxAttempts" {
		Mock Set-WindowPosition { $true }
		Mock Wait-WindowRect { [PSCustomObject]@{ Verified = $false; X = 0; Y = 0; Width = 1; Height = 1; ElapsedMs = 150 } }

		$result = Invoke-SingleZoneWindowPlacement -WindowHandle ([IntPtr]105) -TargetX 0 -TargetY 0 -TargetWidth 2000 -TargetHeight 1000 -MaxAttempts 1

		$result.Attempts | Should -Be 1
		Should -Invoke Set-WindowPosition -Times 1 -Exactly
	}
}
