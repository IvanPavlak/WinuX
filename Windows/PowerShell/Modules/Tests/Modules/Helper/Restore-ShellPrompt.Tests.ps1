#Requires -Modules Pester

BeforeDiscovery {
	# A hidden test worker's output is redirected, so the console has no cursor to read there; the
	# redraw then has nowhere to draw and reports $false. The success case needs a real console.
	$script:consoleAvailable = try { $null = [Console]::CursorTop; $true } catch { $false }
	$script:psReadLineLoaded = $null -ne ('Microsoft.PowerShell.PSConsoleReadLine' -as [type])
}

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	. (Join-Path $ModuleRoot "Helper\Functions\Restore-ShellPrompt.ps1")

	# Stand-ins for PSReadLine's PSConsoleReadLine: a static InvokePrompt that records its call, and
	# one that throws. Uniquely named, because a compiled type lives as long as the worker process.
	$suffix = [guid]::NewGuid().ToString("N")
	Add-Type -TypeDefinition @"
public static class RecordingReadLine_$suffix {
	public static int Calls;
	public static object LastKey = "unset";
	public static object LastRow;
	public static void InvokePrompt(object key, object arg) { Calls++; LastKey = key; LastRow = arg; }
}
public static class ThrowingReadLine_$suffix {
	public static void InvokePrompt(object key, object arg) { throw new System.InvalidOperationException("no line editor session"); }
}
"@
	$script:recording = "RecordingReadLine_$suffix" -as [type]
	$script:throwing = "ThrowingReadLine_$suffix" -as [type]
}

Describe "Restore-ShellPrompt" {
	BeforeEach {
		$script:recording::Calls = 0
		$script:recording::LastKey = "unset"
		$script:recording::LastRow = $null
	}

	It "returns `$false and draws nothing when there is no line editor" {
		Restore-ShellPrompt -ReadLine $null | Should -BeFalse
	}

	It "returns `$false instead of throwing when the redraw fails" {
		{ $script:result = Restore-ShellPrompt -ReadLine $script:throwing } | Should -Not -Throw
		$script:result | Should -BeFalse
	}

	It "draws the prompt through InvokePrompt at the cursor's row and returns `$true" -Skip:(-not $consoleAvailable) {
		$row = [Console]::CursorTop

		Restore-ShellPrompt -ReadLine $script:recording | Should -BeTrue

		$script:recording::Calls | Should -Be 1
		$script:recording::LastKey | Should -BeNullOrEmpty
		$script:recording::LastRow | Should -Be $row
	}

	It "returns `$false and never calls InvokePrompt when the console has no cursor" -Skip:$consoleAvailable {
		Restore-ShellPrompt -ReadLine $script:recording | Should -BeFalse

		$script:recording::Calls | Should -Be 0
	}

	It "defaults to nothing to redraw when PSReadLine is not loaded" -Skip:$psReadLineLoaded {
		Restore-ShellPrompt | Should -BeFalse
	}
}
