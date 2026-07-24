#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Wait-WindowRect.ps1"

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
	}

	It "returns unverified immediately for a zero handle" {
		$result = Wait-WindowRect -WindowHandle ([IntPtr]::Zero) `
			-ExpectedX 0 -ExpectedY 0 -ExpectedWidth 100 -ExpectedHeight 100 -TimeoutMs 500

		$result.Verified | Should -BeFalse
		$result.X | Should -BeNullOrEmpty
		# GetWindowRect fails for a dead handle - polling cannot succeed, so the poll
		# budget must NOT be waited out.
		$result.ElapsedMs | Should -BeLessThan 400
	}

	It "returns unverified immediately when the window handle is not readable" {
		# A bogus non-zero handle: GetWindowRect fails, the loop bails on the first pass.
		$result = Wait-WindowRect -WindowHandle ([IntPtr]0x7FFFFFFF) `
			-ExpectedX 0 -ExpectedY 0 -ExpectedWidth 100 -ExpectedHeight 100 -TimeoutMs 500

		$result.Verified | Should -BeFalse
		$result.ElapsedMs | Should -BeLessThan 400
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
		$result.ElapsedMs | Should -BeLessThan 400
	}

	It "gives up after the time budget when the window never reaches the expected bounds" {
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
		$result.ElapsedMs | Should -BeGreaterOrEqual 150
		# The last observed bounds are reported for the caller's failure diagnostics.
		$result.Width | Should -Be $live.Width
	}
}
