#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Invoke-ClearAndFastfetch.ps1"

	# fastfetch is an external binary absent on CI runners; stub it so Mock can attach
	# (no-op where fastfetch is installed).
	if (-not (Get-Command fastfetch -ErrorAction SilentlyContinue)) {
		function fastfetch { }
	}
}

Describe "Invoke-ClearAndFastfetch" {
	BeforeEach {
		Mock Clear-Host { }
		Mock fastfetch { }
		$script:OriginalWtSession = $env:WT_SESSION
	}

	AfterEach {
		$env:WT_SESSION = $script:OriginalWtSession
	}

	Context "outside Windows Terminal" {
		BeforeEach { $env:WT_SESSION = $null }

		It "clears terminal and invokes fastfetch once" {
			{ Invoke-ClearAndFastfetch } | Should -Not -Throw
			Should -Invoke Clear-Host -Times 1 -Exactly
			Should -Invoke fastfetch -Times 1 -Exactly
		}
	}

	Context "with -NoResize" {
		BeforeEach { $env:WT_SESSION = "1" }

		It "skips auto-fit and invokes fastfetch once even inside Windows Terminal" {
			{ Invoke-ClearAndFastfetch -NoResize } | Should -Not -Throw
			Should -Invoke Clear-Host -Times 1 -Exactly
			Should -Invoke fastfetch -Times 1 -Exactly
		}
	}

	Context "inside Windows Terminal" {
		BeforeEach { $env:WT_SESSION = "1" }

		It "always clears and renders the panel without throwing" {
			# Auto-fit (font measurement / keystrokes) only engages when a real
			# console window is present; the clear + render must run regardless.
			{ Invoke-ClearAndFastfetch } | Should -Not -Throw
			Should -Invoke Clear-Host -Times 1 -Exactly
			Should -Invoke fastfetch
		}
	}
}
