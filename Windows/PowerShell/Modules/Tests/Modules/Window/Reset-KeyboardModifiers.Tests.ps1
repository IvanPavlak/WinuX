#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Reset-KeyboardModifiers.ps1"

	# Compile the native layer exactly as Window.psm1 does, so this suite also guards
	# WindowNative.cs against compile regressions.
	if (-not ([System.Management.Automation.PSTypeName]'WindowModule.Native').Type) {
		$nativePath = Join-Path $ModuleRoot "Window\WindowNative.cs"
		$nativeCode = Get-Content -Path $nativePath -Raw
		Add-Type -TypeDefinition $nativeCode -Language CSharp -ErrorAction Stop
	}

	# Unconditional best-effort release of every Shift variant, used as a safety net so
	# a failed assertion can never leave the tester's session with a held Shift.
	function Invoke-ShiftSafetyRelease {
		$keyUp = [WindowModule.Native]::KEYEVENTF_KEYUP
		foreach ($vk in @([WindowModule.Native]::VK_SHIFT, [WindowModule.Native]::VK_LSHIFT, [WindowModule.Native]::VK_RSHIFT)) {
			[WindowModule.Native]::keybd_event($vk, 0, $keyUp, [UIntPtr]::Zero)
		}
	}
}

Describe "Reset-KeyboardModifiers" {
	BeforeEach {
		Mock Write-LogWarning { }
		Mock Write-LogDebug { }
		Mock Test-LogVerbose { $false }
	}

	AfterEach {
		Invoke-ShiftSafetyRelease
	}

	It "exposes the native detection and release entry points" {
		[WindowModule.Native].GetMethod('GetStuckModifierKeys') | Should -Not -BeNullOrEmpty
		[WindowModule.Native].GetMethod('ReleaseModifierKeys', [type[]]@([bool])) | Should -Not -BeNullOrEmpty
		[WindowModule.Native].GetMethod('ReleaseModifierKeys', [type[]]@()) | Should -Not -BeNullOrEmpty
	}

	It "supports opting into mouse button release" {
		(Get-Command Reset-KeyboardModifiers).Parameters['IncludeMouseButton'].SwitchParameter |
			Should -BeTrue
	}

	It "runs without error and returns a (possibly empty) collection" {
		{ $script:resetResult = Reset-KeyboardModifiers } | Should -Not -Throw

		# On a quiescent keyboard nothing is released; if the tester happens to hold a
		# key at this instant the array is non-empty - both are valid shapes.
		, @($script:resetResult) | Should -BeOfType [array]
	}

	It "releases a synthetically stuck Shift key (the known-issue repro)" {
		# Reproduce the known issue's state directly: inject a Shift key-down with no
		# matching key-up, exactly what an interrupted synthesized sequence leaves behind.
		[WindowModule.Native]::keybd_event([WindowModule.Native]::VK_SHIFT, 0, 0, [UIntPtr]::Zero)
		Start-Sleep -Milliseconds 25

		$stuckBefore = @([WindowModule.Native]::GetStuckModifierKeys())

		if ($stuckBefore.Count -eq 0) {
			# Headless/service sessions may not register injected input at all - the
			# repro cannot be staged there, so the cure cannot be asserted either.
			Set-ItResult -Skipped -Because "this session does not register injected keyboard input"
			return
		}

		try {
			$released = Reset-KeyboardModifiers

			@($released).Count | Should -BeGreaterThan 0
			(@($released) -match 'Shift') | Should -Not -BeNullOrEmpty

			Start-Sleep -Milliseconds 25
			$stuckAfter = @([WindowModule.Native]::GetStuckModifierKeys())
			($stuckAfter -match 'Shift') | Should -BeNullOrEmpty
		}
		finally {
			Invoke-ShiftSafetyRelease
		}
	}

	It "reports released keys through the standard warning log" {
		[WindowModule.Native]::keybd_event([WindowModule.Native]::VK_SHIFT, 0, 0, [UIntPtr]::Zero)
		Start-Sleep -Milliseconds 25

		if (@([WindowModule.Native]::GetStuckModifierKeys()).Count -eq 0) {
			Set-ItResult -Skipped -Because "this session does not register injected keyboard input"
			return
		}

		try {
			$null = Reset-KeyboardModifiers

			Should -Invoke Write-LogWarning -Times 1
		}
		finally {
			Invoke-ShiftSafetyRelease
		}
	}
}
