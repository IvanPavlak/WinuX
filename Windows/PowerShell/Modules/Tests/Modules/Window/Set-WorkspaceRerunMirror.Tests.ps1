#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Set-WorkspaceRerunMirror.ps1"
}

Describe "Set-WorkspaceRerunMirror" {
	# Process scope throughout - see the note in Get-WorkspaceRerunMirror.Tests.ps1 for why.
	BeforeEach {
		$script:MirrorName = 'WINUX_TEST_RERUN_MIRROR_WRITE'
		[Environment]::SetEnvironmentVariable($script:MirrorName, $null, 'Process')
	}

	AfterEach {
		[Environment]::SetEnvironmentVariable($script:MirrorName, $null, 'Process')
	}

	It "stamps the value with a unix timestamp" {
		$before = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

		Set-WorkspaceRerunMirror -Name $script:MirrorName -Value '1' -Scope Process

		$written = [Environment]::GetEnvironmentVariable($script:MirrorName, 'Process')
		$parts = $written -split '\|', 2
		$parts[0] | Should -Be '1'

		$stamp = 0L
		[long]::TryParse($parts[1], [ref]$stamp) | Should -BeTrue
		$stamp | Should -BeGreaterOrEqual $before
		$stamp | Should -BeLessOrEqual ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
	}

	It "overwrites an existing mirror rather than appending to it" {
		Set-WorkspaceRerunMirror -Name $script:MirrorName -Value 'first' -Scope Process
		Set-WorkspaceRerunMirror -Name $script:MirrorName -Value 'second' -Scope Process

		$written = [Environment]::GetEnvironmentVariable($script:MirrorName, 'Process')
		($written -split '\|', 2)[0] | Should -Be 'second'
	}

	It "clears an existing mirror" {
		Set-WorkspaceRerunMirror -Name $script:MirrorName -Value '1' -Scope Process

		Set-WorkspaceRerunMirror -Name $script:MirrorName -Value $null -Scope Process

		[Environment]::GetEnvironmentVariable($script:MirrorName, 'Process') | Should -BeNullOrEmpty
	}

	It "treats an empty string as a clear" {
		Set-WorkspaceRerunMirror -Name $script:MirrorName -Value '1' -Scope Process

		Set-WorkspaceRerunMirror -Name $script:MirrorName -Value '' -Scope Process

		[Environment]::GetEnvironmentVariable($script:MirrorName, 'Process') | Should -BeNullOrEmpty
	}

	It "leaves an already-clear mirror clear, without throwing" {
		# The read-before-write guard's reason for existing is that a User-scope write costs a
		# WM_SETTINGCHANGE broadcast, and this clear runs on the success path of every workspace
		# open. That saving is a performance property and not asserted here; what is asserted is
		# the contract it must not break - clearing nothing is a no-op, not an error.
		{ Set-WorkspaceRerunMirror -Name $script:MirrorName -Value $null -Scope Process } | Should -Not -Throw

		[Environment]::GetEnvironmentVariable($script:MirrorName, 'Process') | Should -BeNullOrEmpty
	}

	It "round-trips through Get-WorkspaceRerunMirror" {
		. (Join-Path (Join-Path (Get-RepositoryPath).Modules "Window\Functions") "Get-WorkspaceRerunMirror.ps1")

		Set-WorkspaceRerunMirror -Name $script:MirrorName -Value 'Firefox' -Scope Process

		Get-WorkspaceRerunMirror -Name $script:MirrorName -Scope Process | Should -Be 'Firefox'
	}
}
