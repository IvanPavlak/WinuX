#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. (Join-Path $ModuleRoot "Helper\Functions\New-WaitClock.ps1")
	. (Join-Path $ModuleRoot "Helper\Functions\Wait-Until.ps1")
	. "$FunctionsPath\Wait-WindowRect.ps1"
	. (Join-Path $ModuleRoot "Tests\Modules\Support\FakeWaitClock.ps1")

	# Native tolerance table the function defaults from (module-scoped in production,
	# test-script-scoped here because the function is dot-sourced).
	$script:WindowModuleTolerances = @{
		PositionVerificationPx = 20
		PreSnapValidationPx    = 75
	}
}

Describe "Wait-WindowRect" {
	BeforeEach {
		Mock Write-Host { }
		# Time is virtual: Sleep advances the clock instead of blocking, so the budgets below
		# are exact poll counts rather than wall-clock guesses.
		$script:clock = New-FakeWaitClock
		Mock New-WaitClock { $script:clock }
	}

	It "returns unverified immediately for a zero handle" {
		$result = Wait-WindowRect -WindowHandle ([IntPtr]::Zero) `
			-ExpectedX 0 -ExpectedY 0 -ExpectedWidth 100 -ExpectedHeight 100 -TimeoutMs 500

		$result.Verified | Should -BeFalse
		$result.X | Should -BeNullOrEmpty
		# GetWindowRect fails for a dead handle - polling cannot succeed, so the poll
		# budget must NOT be waited out: no sleep, no elapsed time.
		$script:clock.Sleeps.Count | Should -Be 0
		$result.ElapsedMs | Should -Be 0
	}

	It "returns unverified immediately when the window handle is not readable" {
		# A bogus non-zero handle: GetWindowRect fails, the wait ends on the first check.
		$result = Wait-WindowRect -WindowHandle ([IntPtr]0x7FFFFFFF) `
			-ExpectedX 0 -ExpectedY 0 -ExpectedWidth 100 -ExpectedHeight 100 -TimeoutMs 500

		$result.Verified | Should -BeFalse
		$script:clock.Sleeps.Count | Should -Be 0
		$result.ElapsedMs | Should -Be 0
	}

	It "returns the result contract fields" {
		$result = Wait-WindowRect -WindowHandle ([IntPtr]::Zero) `
			-ExpectedX 0 -ExpectedY 0 -ExpectedWidth 1 -ExpectedHeight 1

		foreach ($prop in 'Verified', 'X', 'Y', 'Width', 'Height', 'ElapsedMs') {
			$result.PSObject.Properties.Name | Should -Contain $prop
		}
	}

	It "verifies a live window that is already at the expected bounds on the first check" {
		# Use a real window from this session when one exists (EnumWindows via the native
		# type) so the immediate-first-check fast path is exercised against real geometry.
		$liveWindows = [WindowModule.Native]::GetAllWindows()
		if (-not $liveWindows -or $liveWindows.Count -eq 0) {
			Set-ItResult -Skipped -Because "no visible windows available in this session"
			return
		}

		$live = $liveWindows[0]
		$result = Wait-WindowRect -WindowHandle $live.Handle `
			-ExpectedX $live.Left -ExpectedY $live.Top `
			-ExpectedWidth $live.Width -ExpectedHeight $live.Height -TimeoutMs 500

		$result.Verified | Should -BeTrue
		# Already-correct windows must verify on the immediate first check, not after sleeps.
		$script:clock.Sleeps.Count | Should -Be 0
		$result.ElapsedMs | Should -Be 0
	}

	It "gives up after the time budget when the window never reaches the expected bounds: 150 ms at 10 ms polls is 15 sleeps" {
		$liveWindows = [WindowModule.Native]::GetAllWindows()
		if (-not $liveWindows -or $liveWindows.Count -eq 0) {
			Set-ItResult -Skipped -Because "no visible windows available in this session"
			return
		}

		$live = $liveWindows[0]
		# Impossible target: far away from the window's real bounds.
		$result = Wait-WindowRect -WindowHandle $live.Handle `
			-ExpectedX ($live.Left + 5000) -ExpectedY ($live.Top + 5000) `
			-ExpectedWidth 123 -ExpectedHeight 45 -TimeoutMs 150 -PollIntervalMs 10

		$result.Verified | Should -BeFalse
		# Checks at 0, 10, ... 140 fail with budget left; the sleep to 150 spends it and the
		# check at 150 still runs before giving up.
		$script:clock.Sleeps.Count | Should -Be 15
		$result.ElapsedMs | Should -Be 150
		# The last observed bounds are reported for the caller's failure diagnostics.
		$result.Width | Should -Be $live.Width
	}

	It "polls through the clock it is handed instead of creating one" {
		$liveWindows = [WindowModule.Native]::GetAllWindows()
		if (-not $liveWindows -or $liveWindows.Count -eq 0) {
			Set-ItResult -Skipped -Because "no visible windows available in this session"
			return
		}

		$live = $liveWindows[0]
		$other = New-FakeWaitClock
		$result = Wait-WindowRect -WindowHandle $live.Handle `
			-ExpectedX ($live.Left + 5000) -ExpectedY ($live.Top + 5000) `
			-ExpectedWidth 123 -ExpectedHeight 45 -TimeoutMs 300 -PollIntervalMs 15 -Clock $other

		$result.Verified | Should -BeFalse
		$other.Sleeps.Count | Should -Be 20
		$result.ElapsedMs | Should -Be 300
		Should -Invoke New-WaitClock -Times 0
	}
}
