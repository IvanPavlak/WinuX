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
		BeforeEach {
			$env:WT_SESSION = "1"

			# No resolvable binary, so the measuring run falls back to the command name and the
			# real fastfetch is never spawned by the suite on a machine that has it installed.
			Mock Get-Command { $null } -ParameterFilter { $Name -eq "fastfetch" }
		}

		It "always clears and renders the panel without throwing" {
			# Auto-fit (font measurement / keystrokes) only engages when a real
			# console window is present; the clear + render must run regardless.
			{ Invoke-ClearAndFastfetch } | Should -Not -Throw
			Should -Invoke Clear-Host -Times 1 -Exactly
			Should -Invoke fastfetch
		}
	}

	Context "measuring the panel when the fastfetch binary is resolvable" {
		BeforeEach {
			$env:WT_SESSION = "1"

			# A stand-in binary that prints a two-line panel and exits. The measuring run has to go
			# to the BINARY, not to the `fastfetch` command name, so that a profile-defined
			# `fastfetch` function cannot distort the measurement with a decoration that has no
			# measurable width - an inline-image logo is a single enormous line.
			$script:FakeBinary = Join-Path $TestDrive "fastfetch-stand-in.cmd"
			Set-Content -LiteralPath $script:FakeBinary -Value @("@echo off", "echo panel row one", "echo panel row two")
			Mock Get-Command { [pscustomobject]@{ Source = $script:FakeBinary } } -ParameterFilter { $Name -eq "fastfetch" }
		}

		It "renders through the command name exactly once, so the measuring run bypassed the wrapper" {
			# One invocation of the mocked command name = the displaying run only. If the measuring
			# run also went through it, this would be two (or one when auto-fit does not engage,
			# which is why the assertion is an upper bound as well as a lower one).
			{ Invoke-ClearAndFastfetch } | Should -Not -Throw
			Should -Invoke Clear-Host -Times 1 -Exactly
			Should -Invoke fastfetch -Times 1 -Exactly
		}
	}
}
