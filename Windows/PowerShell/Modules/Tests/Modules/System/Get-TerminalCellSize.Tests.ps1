#Requires -Modules Pester

BeforeAll {
	$SystemFunctionsPath = Join-Path (Get-RepositoryPath).Modules "System\Functions"
	. "$SystemFunctionsPath\Get-TerminalCellSize.ps1"

	$script:CellSizeFunctionFile = Join-Path $SystemFunctionsPath "Get-TerminalCellSize.ps1"
	$script:PowerShellExe = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
}

Describe "Get-TerminalCellSize" {
	BeforeEach {
		Mock Write-LogDebug { }
	}

	It "returns either nothing or a plausible cell size, depending on whether the host terminal answers" {
		# Run interactively in Windows Terminal or WezTerm this returns a real measurement; run on
		# CI or in any other terminal it returns nothing. Both are correct, and nothing in between
		# is: a reported cell is never zero, negative or non-numeric.
		$size = Get-TerminalCellSize -TimeoutMilliseconds 50

		if ($null -ne $size) {
			$size.Width | Should -BeOfType [int]
			$size.Height | Should -BeOfType [int]
			$size.Width | Should -BeGreaterThan 0
			$size.Height | Should -BeGreaterThan 0
		}
	}

	It "returns nothing when output is redirected, because no terminal can answer" {
		# Redirection is a property of the process, so the only way to test the guard deterministically
		# is to be a process whose output is captured. The child stubs the logging call it would
		# otherwise inherit from an imported module.
		$probe = @"
function Write-LogDebug { param([string]`$Message, [string]`$Style) }
. '$script:CellSizeFunctionFile'
if (`$null -eq (Get-TerminalCellSize -TimeoutMilliseconds 20)) { 'no-size' } else { 'size' }
"@

		& $script:PowerShellExe -NoProfile -NonInteractive -Command $probe | Should -Be "no-size"
	}

	It "never throws, whatever the host is" {
		{ Get-TerminalCellSize -TimeoutMilliseconds 20 } | Should -Not -Throw
	}

	It "rejects a timeout outside the supported range" {
		{ Get-TerminalCellSize -TimeoutMilliseconds 0 } | Should -Throw
		{ Get-TerminalCellSize -TimeoutMilliseconds 5001 } | Should -Throw
	}

	It "records what it decided so a missing image logo can be diagnosed" {
		Get-TerminalCellSize -TimeoutMilliseconds 20 | Out-Null

		Should -Invoke Write-LogDebug -Times 1 -Exactly -Scope It
	}
}

Describe "Test-TerminalCellSizeReply" {
	# The console read stops on this predicate, so it decides whether typed-ahead input can end the
	# read early. Before it existed the read stopped on ANY trailing 't': typing `github` into a
	# Windows Terminal tab that was still loading ended the read at `git`, the measurement failed,
	# and the real reply spilled onto the prompt as `hub[6;20;10t`.
	BeforeAll {
		$script:Esc = [char]27
	}

	It "recognizes a complete CSI 6 ; height ; width t report" {
		Test-TerminalCellSizeReply -Text "$script:Esc[6;20;10t" | Should -BeTrue
	}

	It "recognizes the report when typed-ahead characters precede or follow it" {
		Test-TerminalCellSizeReply -Text "gi$script:Esc[6;20;10t" | Should -BeTrue
		Test-TerminalCellSizeReply -Text "$script:Esc[6;20;10thub" | Should -BeTrue
	}

	It "does not stop on a word that merely ends in t" {
		Test-TerminalCellSizeReply -Text "git" | Should -BeFalse
	}

	It "does not stop on a report that is still arriving" {
		Test-TerminalCellSizeReply -Text "$script:Esc[6;20;1" | Should -BeFalse
		Test-TerminalCellSizeReply -Text "$script:Esc[6;20t" | Should -BeFalse
	}

	It "does not mistake another window report for the cell size" {
		# CSI 4 t answers the text-area size in pixels, CSI 8 t the size in characters.
		Test-TerminalCellSizeReply -Text "$script:Esc[4;1440;3440t" | Should -BeFalse
		Test-TerminalCellSizeReply -Text "$script:Esc[8;70;344t" | Should -BeFalse
	}

	It "treats an empty buffer as no report" {
		Test-TerminalCellSizeReply -Text "" | Should -BeFalse
	}
}

Describe "ConvertFrom-TerminalCellSizeReply" {
	BeforeAll {
		$script:Esc = [char]27
	}

	It "returns width and height in that order, although the report carries height first" {
		$size = ConvertFrom-TerminalCellSizeReply -Text "$script:Esc[6;20;10t"

		$size.Width | Should -Be 10
		$size.Height | Should -Be 20
	}

	It "parses the report out of the typed-ahead characters around it" {
		$size = ConvertFrom-TerminalCellSizeReply -Text "gi$script:Esc[6;20;10thub"

		$size.Width | Should -Be 10
		$size.Height | Should -Be 20
	}

	It "returns nothing when the text holds no report" {
		ConvertFrom-TerminalCellSizeReply -Text "git" | Should -BeNullOrEmpty
		ConvertFrom-TerminalCellSizeReply -Text "" | Should -BeNullOrEmpty
	}

	It "returns nothing for a degenerate cell" {
		ConvertFrom-TerminalCellSizeReply -Text "$script:Esc[6;0;10t" | Should -BeNullOrEmpty
		ConvertFrom-TerminalCellSizeReply -Text "$script:Esc[6;20;0t" | Should -BeNullOrEmpty
	}

	It "returns integers, so the cell block arithmetic never sees strings" {
		$size = ConvertFrom-TerminalCellSizeReply -Text "$script:Esc[6;20;10t"

		$size.Width | Should -BeOfType [int]
		$size.Height | Should -BeOfType [int]
	}
}
