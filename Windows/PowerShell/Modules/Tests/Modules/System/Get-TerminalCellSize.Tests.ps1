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
