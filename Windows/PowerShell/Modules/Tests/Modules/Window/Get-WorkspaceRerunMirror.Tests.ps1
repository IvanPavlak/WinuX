#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Set-WorkspaceRerunMirror.ps1"
	. "$FunctionsPath\Get-WorkspaceRerunMirror.ps1"
}

Describe "Get-WorkspaceRerunMirror" {
	# Every test runs against Process scope. The parsing, the one-shot consume and the TTL are
	# scope-independent, and Process scope costs microseconds where a User-scope write broadcasts
	# WM_SETTINGCHANGE to every top-level window and blocks on the slowest to answer - seconds, on
	# a busy desktop. Process scope is also per-process, so these tests cannot disturb a parallel
	# worker or leave anything on the machine. The only thing left uncovered is the literal
	# default -Scope value, which is a constant.
	BeforeEach {
		$script:MirrorName = 'WINUX_TEST_RERUN_MIRROR'
		[Environment]::SetEnvironmentVariable($script:MirrorName, $null, 'Process')
	}

	AfterEach {
		[Environment]::SetEnvironmentVariable($script:MirrorName, $null, 'Process')
	}

	It "returns null when no mirror is set" {
		Get-WorkspaceRerunMirror -Name $script:MirrorName -Scope Process | Should -BeNullOrEmpty
	}

	It "returns the value of a freshly written mirror" {
		Set-WorkspaceRerunMirror -Name $script:MirrorName -Value '1' -Scope Process

		Get-WorkspaceRerunMirror -Name $script:MirrorName -Scope Process | Should -Be '1'
	}

	It "discards a value that itself contains the separator" {
		# The split takes the FIRST separator as the delimiter, so everything after it has to
		# parse as the timestamp - which a value carrying its own pipe cannot. Such a mirror is
		# therefore dropped rather than half-read. It matters only for the window-title marker,
		# which is informational (the rerun re-applies the whole layout either way), so this
		# pins the existing behavior rather than papering over it.
		$stamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
		[Environment]::SetEnvironmentVariable($script:MirrorName, "Code|Visual Studio|$stamp", 'Process')

		Get-WorkspaceRerunMirror -Name $script:MirrorName -Scope Process | Should -BeNullOrEmpty
	}

	It "consumes the mirror on read so it cannot influence a later run" {
		Set-WorkspaceRerunMirror -Name $script:MirrorName -Value '1' -Scope Process

		Get-WorkspaceRerunMirror -Name $script:MirrorName -Scope Process | Should -Be '1'
		Get-WorkspaceRerunMirror -Name $script:MirrorName -Scope Process | Should -BeNullOrEmpty
	}

	It "returns null for a mirror older than the TTL" {
		$stamp = [DateTimeOffset]::UtcNow.AddMinutes(-20).ToUnixTimeSeconds()
		[Environment]::SetEnvironmentVariable($script:MirrorName, "1|$stamp", 'Process')

		Get-WorkspaceRerunMirror -Name $script:MirrorName -Scope Process | Should -BeNullOrEmpty
	}

	It "honors a custom TTL" {
		$stamp = [DateTimeOffset]::UtcNow.AddMinutes(-5).ToUnixTimeSeconds()
		[Environment]::SetEnvironmentVariable($script:MirrorName, "1|$stamp", 'Process')

		Get-WorkspaceRerunMirror -Name $script:MirrorName -TtlMinutes 1 -Scope Process | Should -BeNullOrEmpty
	}

	It "returns null for a mirror timestamped in the future (clock moved)" {
		$stamp = [DateTimeOffset]::UtcNow.AddMinutes(20).ToUnixTimeSeconds()
		[Environment]::SetEnvironmentVariable($script:MirrorName, "1|$stamp", 'Process')

		Get-WorkspaceRerunMirror -Name $script:MirrorName -Scope Process | Should -BeNullOrEmpty
	}

	It "returns null when the mirror carries no timestamp" {
		[Environment]::SetEnvironmentVariable($script:MirrorName, 'justavalue', 'Process')

		Get-WorkspaceRerunMirror -Name $script:MirrorName -Scope Process | Should -BeNullOrEmpty
	}

	It "returns null when the timestamp is not a number" {
		[Environment]::SetEnvironmentVariable($script:MirrorName, '1|not-a-timestamp', 'Process')

		Get-WorkspaceRerunMirror -Name $script:MirrorName -Scope Process | Should -BeNullOrEmpty
	}

	It "consumes an expired mirror as well, so it is not re-read on every open" {
		$stamp = [DateTimeOffset]::UtcNow.AddMinutes(-20).ToUnixTimeSeconds()
		[Environment]::SetEnvironmentVariable($script:MirrorName, "1|$stamp", 'Process')

		Get-WorkspaceRerunMirror -Name $script:MirrorName -Scope Process | Should -BeNullOrEmpty

		[Environment]::GetEnvironmentVariable($script:MirrorName, 'Process') | Should -BeNullOrEmpty
	}
}
