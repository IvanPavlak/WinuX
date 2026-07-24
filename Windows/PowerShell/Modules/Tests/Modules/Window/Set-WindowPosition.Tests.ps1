#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Set-WindowPosition.ps1"
}

Describe "Set-WindowPosition" {
	BeforeEach {
		$script:WindowModuleDelays = @{ WindowRestoreMs = 1; WindowPositionMs = 1 }
		Mock Start-Sleep { }
	}

	It "returns false when window cannot be positioned" {
		$result = Set-WindowPosition -WindowHandle ([IntPtr]::Zero) -X 0 -Y 0 -Width 800 -Height 600

		$result | Should -BeFalse
	}

	It "skips every settle sleep for a window already in the normal show state" {
		# Find a live, non-maximized window whose placement is already SW_SHOWNORMAL;
		# repositioning it to its CURRENT bounds is a visual no-op.
		$normalWindow = $null
		foreach ($candidate in [WindowModule.Native]::GetAllWindows()) {
			if ([WindowModule.Native]::IsZoomed($candidate.Handle)) { continue }
			$placement = New-Object WindowModule.WINDOWPLACEMENT
			$placement.length = [System.Runtime.InteropServices.Marshal]::SizeOf([type][WindowModule.WINDOWPLACEMENT])
			if (-not [WindowModule.Native]::GetWindowPlacement($candidate.Handle, [ref]$placement)) { continue }
			if ($placement.showCmd -ne [WindowModule.Native]::SW_SHOWNORMAL) { continue }
			$normalWindow = $candidate
			break
		}

		if (-not $normalWindow) {
			Set-ItResult -Skipped -Because "no normal-state window available in this session"
			return
		}

		$result = Set-WindowPosition -WindowHandle $normalWindow.Handle `
			-X $normalWindow.Left -Y $normalWindow.Top -Width $normalWindow.Width -Height $normalWindow.Height

		$result | Should -BeTrue
		# Already-normal window: no restore settle is needed, and the fixed
		# post-SetWindowPos delay is gone (callers verify or settle themselves) -
		# the previous behavior paid 2x25ms on EVERY call in the positioning pipeline.
		Should -Invoke Start-Sleep -Times 0
	}
}
