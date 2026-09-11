#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	. "$ModuleRoot\System\Functions\Initialize-PSReadLine.ps1"

	# PSReadLine ships with PowerShell 7, but an automation host may run without it loaded. Stub
	# the two cmdlets when absent so Mock has commands to attach to (no-op where they exist).
	if (-not (Get-Command Set-PSReadLineOption -ErrorAction SilentlyContinue)) {
		function Set-PSReadLineOption { param($EditMode, $MaximumHistoryCount, $HistorySavePath, [switch]$HistoryNoDuplicates, $PredictionSource, $PredictionViewStyle) }
	}
	if (-not (Get-Command Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue)) {
		function Set-PSReadLineKeyHandler { param($Key, $Function) }
	}
	if (-not (Get-Command Write-LogWarning -ErrorAction SilentlyContinue)) { function Write-LogWarning { param($Message) } }
	if (-not (Get-Command Write-LogDebug -ErrorAction SilentlyContinue)) { function Write-LogDebug { param($Message) } }
}

Describe "Initialize-PSReadLine" {
	BeforeEach {
		# Inside a Pester mock body or -ParameterFilter the call's arguments arrive as plain variables and
		# $PSBoundParameters is empty, so "was this parameter passed" is asserted through Pester's own
		# $PesterBoundParameters. A plain `$null -ne $MaximumHistoryCount` would not do: that name is also
		# a global preference variable, and an unbound parameter falls through to it.
		Mock Set-PSReadLineOption { }
		Mock Set-PSReadLineKeyHandler { }
		Mock Write-LogWarning { }
		Mock Write-LogDebug { }

		$script:SavedConfiguration = $global:Configuration
		$script:SavedMaximumHistoryCount = $global:MaximumHistoryCount
	}

	AfterEach {
		$global:Configuration = $script:SavedConfiguration
		$global:MaximumHistoryCount = $script:SavedMaximumHistoryCount
	}

	Context "empty section" {
		It "does nothing when the section is <Label>" -ForEach @(
			@{ Label = "null"; Settings = $null }
			@{ Label = "an empty hashtable"; Settings = @{} }
		) {
			{ Initialize-PSReadLine -Settings $Settings } | Should -Not -Throw
			Should -Invoke Set-PSReadLineOption -Times 0 -Exactly
			Should -Invoke Set-PSReadLineKeyHandler -Times 0 -Exactly
			Should -Invoke Write-LogDebug -Times 1 -Exactly
		}

		It "reads Configuration.PSReadLine when no -Settings is passed" {
			$global:Configuration = @{ PSReadLine = @{ EditMode = "Emacs" } }
			Initialize-PSReadLine
			Should -Invoke Set-PSReadLineOption -Times 1 -Exactly -ParameterFilter { $EditMode -eq "Emacs" }
		}
	}

	Context "null keys are skipped" {
		It "makes no call for a key set to null" {
			Initialize-PSReadLine -Settings @{
				EditMode            = $null
				MaximumHistoryCount = $null
				HistorySavePath     = $null
				HistoryNoDuplicates = $null
				PredictionSource    = $null
				PredictionViewStyle = $null
				KeyHandlers         = @{ UpArrow = $null }
			}
			Should -Invoke Set-PSReadLineOption -Times 0 -Exactly
			Should -Invoke Set-PSReadLineKeyHandler -Times 0 -Exactly
		}
	}

	Context "base section" {
		BeforeEach {
			$script:Base = @{
				EditMode            = "Windows"
				KeyHandlers         = @{ UpArrow = "HistorySearchBackward"; DownArrow = "HistorySearchForward" }
				MaximumHistoryCount = $null
				HistorySavePath     = $null
				HistoryNoDuplicates = $true
				PredictionSource    = "History"
				PredictionViewStyle = "ListView"
			}
		}

		It "applies the edit mode" {
			Initialize-PSReadLine -Settings $script:Base
			Should -Invoke Set-PSReadLineOption -Times 1 -Exactly -ParameterFilter { $EditMode -eq "Windows" }
		}

		It "binds every key handler" {
			Initialize-PSReadLine -Settings $script:Base
			Should -Invoke Set-PSReadLineKeyHandler -Times 1 -Exactly -ParameterFilter { $Key -eq "UpArrow" -and $Function -eq "HistorySearchBackward" }
			Should -Invoke Set-PSReadLineKeyHandler -Times 1 -Exactly -ParameterFilter { $Key -eq "DownArrow" -and $Function -eq "HistorySearchForward" }
		}

		It "applies HistoryNoDuplicates and both prediction options" {
			Initialize-PSReadLine -Settings $script:Base
			Should -Invoke Set-PSReadLineOption -Times 1 -Exactly -ParameterFilter { $PesterBoundParameters.ContainsKey("HistoryNoDuplicates") -and $HistoryNoDuplicates }
			Should -Invoke Set-PSReadLineOption -Times 1 -Exactly -ParameterFilter { $PredictionSource -eq "History" }
			Should -Invoke Set-PSReadLineOption -Times 1 -Exactly -ParameterFilter { $PredictionViewStyle -eq "ListView" }
		}

		It "never touches the history limit or path when they are null" {
			Initialize-PSReadLine -Settings $script:Base
			Should -Invoke Set-PSReadLineOption -Times 0 -Exactly -ParameterFilter { $PesterBoundParameters.ContainsKey("MaximumHistoryCount") }
			Should -Invoke Set-PSReadLineOption -Times 0 -Exactly -ParameterFilter { $PesterBoundParameters.ContainsKey("HistorySavePath") }
			$global:MaximumHistoryCount | Should -Be $script:SavedMaximumHistoryCount
		}

		It "passes HistoryNoDuplicates false through as an explicit off" {
			$script:Base.HistoryNoDuplicates = $false
			Initialize-PSReadLine -Settings $script:Base
			Should -Invoke Set-PSReadLineOption -Times 1 -Exactly -ParameterFilter { $PesterBoundParameters.ContainsKey("HistoryNoDuplicates") -and -not $HistoryNoDuplicates }
		}
	}

	Context "ordering" {
		It "sets EditMode before any key handler and the prediction options last" {
			$script:Calls = [System.Collections.Generic.List[string]]::new()
			Mock Set-PSReadLineOption {
				if ($PesterBoundParameters.ContainsKey("EditMode")) { $script:Calls.Add("EditMode") }
				if ($PesterBoundParameters.ContainsKey("MaximumHistoryCount")) { $script:Calls.Add("History") }
				if ($PesterBoundParameters.ContainsKey("PredictionSource")) { $script:Calls.Add("PredictionSource") }
				if ($PesterBoundParameters.ContainsKey("PredictionViewStyle")) { $script:Calls.Add("PredictionViewStyle") }
			}
			Mock Set-PSReadLineKeyHandler { $script:Calls.Add("Key:$Key") }

			Initialize-PSReadLine -Settings @{
				PredictionViewStyle = "ListView"
				PredictionSource    = "History"
				MaximumHistoryCount = 100
				KeyHandlers         = @{ UpArrow = "HistorySearchBackward" }
				EditMode            = "Windows"
			}

			$script:Calls | Should -Be @("EditMode", "Key:UpArrow", "History", "PredictionSource", "PredictionViewStyle")
		}
	}

	Context "MaximumHistoryCount" {
		It "sets the PSReadLine cap and the session variable to the same value below the ceiling" {
			Initialize-PSReadLine -Settings @{ MaximumHistoryCount = 10000 }
			Should -Invoke Set-PSReadLineOption -Times 1 -Exactly -ParameterFilter { $PesterBoundParameters.ContainsKey("MaximumHistoryCount") -and $MaximumHistoryCount -eq 10000 }
			$global:MaximumHistoryCount | Should -Be 10000
		}

		It "clamps only the session variable at 32767" {
			Initialize-PSReadLine -Settings @{ MaximumHistoryCount = 50000 }
			Should -Invoke Set-PSReadLineOption -Times 1 -Exactly -ParameterFilter { $PesterBoundParameters.ContainsKey("MaximumHistoryCount") -and $MaximumHistoryCount -eq 50000 }
			$global:MaximumHistoryCount | Should -Be 32767
		}

		It "accepts a numeric string" {
			Initialize-PSReadLine -Settings @{ MaximumHistoryCount = "4096" }
			Should -Invoke Set-PSReadLineOption -Times 1 -Exactly -ParameterFilter { $PesterBoundParameters.ContainsKey("MaximumHistoryCount") -and $MaximumHistoryCount -eq 4096 }
		}

		It "warns and leaves both limits alone for <Label>" -ForEach @(
			@{ Label = "a non-numeric value"; Value = "lots" }
			@{ Label = "zero"; Value = 0 }
			@{ Label = "a negative number"; Value = -5 }
			@{ Label = "a fraction"; Value = 1.5 }
		) {
			Initialize-PSReadLine -Settings @{ MaximumHistoryCount = $Value }
			Should -Invoke Set-PSReadLineOption -Times 0 -Exactly
			Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -like "*MaximumHistoryCount*positive integer*" }
			$global:MaximumHistoryCount | Should -Be $script:SavedMaximumHistoryCount
		}
	}

	Context "HistorySavePath" {
		It "expands %ENV% variables before handing the path to PSReadLine" {
			Initialize-PSReadLine -Settings @{ HistorySavePath = "%TEMP%\history.txt" }
			$expected = Join-Path $env:TEMP "history.txt"
			Should -Invoke Set-PSReadLineOption -Times 1 -Exactly -ParameterFilter { $HistorySavePath -eq $expected }
		}

		It "skips an empty string" {
			Initialize-PSReadLine -Settings @{ HistorySavePath = "" }
			Should -Invoke Set-PSReadLineOption -Times 0 -Exactly
		}
	}

	Context "key handlers" {
		It "skips a null handler but binds the others" {
			Initialize-PSReadLine -Settings @{ KeyHandlers = @{ UpArrow = $null; Tab = "MenuComplete" } }
			Should -Invoke Set-PSReadLineKeyHandler -Times 1 -Exactly
			Should -Invoke Set-PSReadLineKeyHandler -Times 1 -Exactly -ParameterFilter { $Key -eq "Tab" -and $Function -eq "MenuComplete" }
		}

		It "ignores a KeyHandlers value that is not a hashtable" {
			{ Initialize-PSReadLine -Settings @{ KeyHandlers = "UpArrow" } } | Should -Not -Throw
			Should -Invoke Set-PSReadLineKeyHandler -Times 0 -Exactly
		}
	}

	Context "console without virtual-terminal support" {
		It "keeps every earlier setting when the prediction options throw, and does not rethrow" {
			Mock Set-PSReadLineOption { throw "no VT" } -ParameterFilter { $PesterBoundParameters.ContainsKey("PredictionSource") }

			{
				Initialize-PSReadLine -Settings @{
					EditMode            = "Windows"
					MaximumHistoryCount = 500
					PredictionSource    = "History"
					PredictionViewStyle = "ListView"
				}
			} | Should -Not -Throw

			Should -Invoke Set-PSReadLineOption -Times 1 -Exactly -ParameterFilter { $EditMode -eq "Windows" }
			Should -Invoke Set-PSReadLineOption -Times 1 -Exactly -ParameterFilter { $PesterBoundParameters.ContainsKey("MaximumHistoryCount") -and $MaximumHistoryCount -eq 500 }
			Should -Invoke Set-PSReadLineOption -Times 0 -Exactly -ParameterFilter { $PesterBoundParameters.ContainsKey("PredictionViewStyle") }
			Should -Invoke Write-LogDebug -Times 1 -Exactly -ParameterFilter { $Message -like "*prediction options skipped*" }
			Should -Invoke Write-LogWarning -Times 0 -Exactly
		}
	}
}
