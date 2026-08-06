#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Configure-WSLSSH.ps1"
}

Describe "Configure-WSLSSH" {
	BeforeEach {
		$script:Configuration = [PSCustomObject]@{
			DefaultWSLDistribution = "Ubuntu"
		}

		# `id -un` / `echo $HOME` probes and the copy/chown/chmod calls all hit this mock;
		# a non-empty return satisfies the derived-user guard.
		Mock wsl { "ivan" }
		Mock Write-Host { }
	}

	It "executes WSL commands to copy and secure SSH keys" {
		{ Configure-WSLSSH } | Should -Not -Throw

		# 2 probes (user, home) + rm + mkdir + cp + chown + 4 chmod groups
		Should -Invoke wsl -Times 10 -Exactly
	}

	It "derives the WSL user instead of using the Windows username" {
		{ Configure-WSLSSH } | Should -Not -Throw

		Should -Invoke wsl -ParameterFilter { $args -contains 'chown' -and $args -ccontains 'ivan:ivan' } -Times 1 -Exactly
	}

	It "skips when the WSL user cannot be determined" {
		Mock wsl { "" }

		{ Configure-WSLSSH } | Should -Not -Throw

		# Only the two probes run - nothing is copied or chmodded
		Should -Invoke wsl -Times 2 -Exactly
	}

	It "skips when no WSL distribution is configured" {
		$script:Configuration = [PSCustomObject]@{
			DefaultWSLDistribution = ""
		}

		{ Configure-WSLSSH } | Should -Not -Throw

		Should -Invoke wsl -Times 0
	}
}
