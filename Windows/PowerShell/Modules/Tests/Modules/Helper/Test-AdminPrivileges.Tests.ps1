#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Test-AdminPrivileges.ps1"

	# The elevation state cannot be mocked ([WindowsIdentity]::GetCurrent() is a static .NET call),
	# so each branch runs only in a session that matches it and skips with a reason in the other.
	# Run once from a normal terminal and once from an elevated one to cover both halves.
	$script:IsElevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
		[Security.Principal.WindowsBuiltInRole]::Administrator)

	$script:FunctionFiles = @(
		(Join-Path $FunctionsPath "Test-AdminPrivileges.ps1"),
		(Join-Path $FunctionsPath "Get-ConfigSetting.ps1")
	)

	# Runs Test-AdminPrivileges in an isolated runspace. The non-elevated path ends with
	# throw [PipelineStoppedException], which no try/catch (and so no Should -Throw) can observe:
	# it tears down the whole pipeline, and Pester fails the test instead. In a child runspace the
	# throw only stops that runspace, whose InvocationStateInfo then reports State = Stopped. The
	# collaborators are replaced by recording stubs (functions take precedence over cmdlets, so
	# Get-PSCallStack is replaced too) and every call lands in $Calls for the assertions.
	$script:InvokeIsolated = {
		param(
			[hashtable]$ConfigurationValue = @{},
			[hashtable]$Parameters = @{},
			[object]$SelectionAnswer = "Yes",
			[string[]]$CallStackLines = @("", "Install-Something -Foo")
		)

		$calls = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
		$powershell = [powershell]::Create()
		try {
			$null = $powershell.AddScript({
					param($FunctionFiles, $ConfigurationValue, $Parameters, $SelectionAnswer, $CallStackLines, $Calls)

					foreach ($functionFile in $FunctionFiles) { . $functionFile }
					$global:Configuration = $ConfigurationValue

					function Get-PSCallStack {
						foreach ($line in $CallStackLines) {
							[pscustomobject]@{ InvocationInfo = [pscustomobject]@{ Line = $line } }
						}
					}
					function Resolve-Selection {
						param($MenuTitle, $PromptMessage, $AllowEmptyPromptResponse)
						$Calls.Enqueue([pscustomobject]@{ Name = "Resolve-Selection" })
						$SelectionAnswer
					}
					function Open-Terminal {
						param([string[]]$Command, [switch]$Administrator)
						$Calls.Enqueue([pscustomobject]@{ Name = "Open-Terminal"; Command = ($Command -join "`n"); Administrator = [bool]$Administrator })
					}
					function Write-LogError {
						param($Message)
						$Calls.Enqueue([pscustomobject]@{ Name = "Write-LogError"; Message = $Message })
					}
					function Write-LogSuccess {
						param($Message)
						$Calls.Enqueue([pscustomobject]@{ Name = "Write-LogSuccess"; Message = $Message })
					}

					Test-AdminPrivileges @Parameters
					$Calls.Enqueue([pscustomobject]@{ Name = "Returned" })
				}).AddArgument($script:FunctionFiles).AddArgument($ConfigurationValue).AddArgument($Parameters).AddArgument($SelectionAnswer).AddArgument($CallStackLines).AddArgument($calls)

			$output = $powershell.Invoke()

			[pscustomobject]@{
				State  = [string]$powershell.InvocationStateInfo.State
				Reason = $powershell.InvocationStateInfo.Reason
				Output = @($output)
				Errors = @($powershell.Streams.Error | ForEach-Object { "$_" })
				Calls  = @($calls.ToArray())
			}
		}
		finally {
			$powershell.Dispose()
		}
	}

	$script:CallCount = {
		param($Result, [string]$Name)
		@($Result.Calls | Where-Object { $_.Name -eq $Name }).Count
	}
}

Describe "Test-AdminPrivileges" {
	Context "CheckOnly" {
		It "returns a boolean in CheckOnly mode" {
			$result = Test-AdminPrivileges -CheckOnly

			$result | Should -BeOfType ([bool])
		}

		It "never prompts or relaunches in CheckOnly mode, whatever -AutoElevate and AutoElevate say" {
			$result = & $script:InvokeIsolated -ConfigurationValue @{ AutoElevate = $true } -Parameters @{ CheckOnly = $true; AutoElevate = $true }

			$result.State | Should -Be "Completed"
			$result.Output.Count | Should -Be 1
			$result.Output[0] | Should -Be $script:IsElevated
			& $script:CallCount $result "Resolve-Selection" | Should -Be 0
			& $script:CallCount $result "Open-Terminal" | Should -Be 0
		}
	}

	Context "When the session is already elevated" {
		It "returns without prompting, relaunching or logging an error" {
			if (-not $script:IsElevated) {
				Set-ItResult -Skipped -Because "this session is not elevated; run Run-Tests from an elevated terminal to cover this branch"
				return
			}

			$result = & $script:InvokeIsolated

			$result.State | Should -Be "Completed"
			& $script:CallCount $result "Returned" | Should -Be 1
			& $script:CallCount $result "Resolve-Selection" | Should -Be 0
			& $script:CallCount $result "Open-Terminal" | Should -Be 0
			& $script:CallCount $result "Write-LogError" | Should -Be 0
		}

		It "returns without relaunching when -AutoElevate is passed and AutoElevate is true" {
			if (-not $script:IsElevated) {
				Set-ItResult -Skipped -Because "this session is not elevated; run Run-Tests from an elevated terminal to cover this branch"
				return
			}

			$result = & $script:InvokeIsolated -ConfigurationValue @{ AutoElevate = $true } -Parameters @{ AutoElevate = $true }

			$result.State | Should -Be "Completed"
			& $script:CallCount $result "Returned" | Should -Be 1
			& $script:CallCount $result "Open-Terminal" | Should -Be 0
		}
	}

	Context "When the session is not elevated" {
		It "prompts, relaunches elevated from the current directory and stops the pipeline when nothing sets AutoElevate" {
			if ($script:IsElevated) {
				Set-ItResult -Skipped -Because "this session is elevated; run Run-Tests from a normal terminal to cover this branch"
				return
			}

			$result = & $script:InvokeIsolated -ConfigurationValue @{}

			$result.State | Should -Be "Stopped" -Because "errors: $($result.Errors -join '; ')"
			$result.Reason | Should -BeOfType ([System.Management.Automation.PipelineStoppedException])
			& $script:CallCount $result "Write-LogError" | Should -Be 1
			& $script:CallCount $result "Resolve-Selection" | Should -Be 1
			$relaunch = @($result.Calls | Where-Object { $_.Name -eq "Open-Terminal" })
			$relaunch.Count | Should -Be 1
			$relaunch[0].Administrator | Should -BeTrue
			$relaunch[0].Command | Should -BeLike "Set-Location -Path '*'; Install-Something -Foo"
			& $script:CallCount $result "Returned" | Should -Be 0
		}

		It "relaunches without prompting when AutoElevate is true in configuration" {
			if ($script:IsElevated) {
				Set-ItResult -Skipped -Because "this session is elevated; run Run-Tests from a normal terminal to cover this branch"
				return
			}

			$result = & $script:InvokeIsolated -ConfigurationValue @{ AutoElevate = $true }

			$result.State | Should -Be "Stopped" -Because "errors: $($result.Errors -join '; ')"
			& $script:CallCount $result "Resolve-Selection" | Should -Be 0
			& $script:CallCount $result "Open-Terminal" | Should -Be 1
			& $script:CallCount $result "Write-LogError" | Should -Be 1
			$success = @($result.Calls | Where-Object { $_.Name -eq "Write-LogSuccess" })
			$success.Count | Should -Be 1 -Because "the relaunch is logged before the pipeline stops"
			$success[0].Message | Should -BeLike "*Install-Something -Foo*"
		}

		It "relaunches without prompting when -AutoElevate is passed and AutoElevate is false" {
			if ($script:IsElevated) {
				Set-ItResult -Skipped -Because "this session is elevated; run Run-Tests from a normal terminal to cover this branch"
				return
			}

			$result = & $script:InvokeIsolated -ConfigurationValue @{ AutoElevate = $false } -Parameters @{ AutoElevate = $true }

			$result.State | Should -Be "Stopped" -Because "errors: $($result.Errors -join '; ')"
			& $script:CallCount $result "Resolve-Selection" | Should -Be 0
			& $script:CallCount $result "Open-Terminal" | Should -Be 1
		}

		It "prompts when -AutoElevate:`$false is passed even though AutoElevate is true" {
			if ($script:IsElevated) {
				Set-ItResult -Skipped -Because "this session is elevated; run Run-Tests from a normal terminal to cover this branch"
				return
			}

			$result = & $script:InvokeIsolated -ConfigurationValue @{ AutoElevate = $true } -Parameters @{ AutoElevate = $false }

			$result.State | Should -Be "Stopped" -Because "errors: $($result.Errors -join '; ')"
			& $script:CallCount $result "Resolve-Selection" | Should -Be 1
			& $script:CallCount $result "Open-Terminal" | Should -Be 1
		}

		It "does not relaunch when the prompt is declined, but still stops the pipeline" {
			if ($script:IsElevated) {
				Set-ItResult -Skipped -Because "this session is elevated; run Run-Tests from a normal terminal to cover this branch"
				return
			}

			$result = & $script:InvokeIsolated -ConfigurationValue @{} -SelectionAnswer "No"

			$result.State | Should -Be "Stopped" -Because "errors: $($result.Errors -join '; ')"
			& $script:CallCount $result "Resolve-Selection" | Should -Be 1
			& $script:CallCount $result "Open-Terminal" | Should -Be 0
			& $script:CallCount $result "Write-LogSuccess" | Should -Be 0
		}

		It "treats an empty prompt answer as Yes" {
			if ($script:IsElevated) {
				Set-ItResult -Skipped -Because "this session is elevated; run Run-Tests from a normal terminal to cover this branch"
				return
			}

			$result = & $script:InvokeIsolated -ConfigurationValue @{} -SelectionAnswer $null

			$result.State | Should -Be "Stopped" -Because "errors: $($result.Errors -join '; ')"
			& $script:CallCount $result "Open-Terminal" | Should -Be 1
		}

		It "replays the outermost typed command, not an inner engine line like '& `$stepName'" {
			if ($script:IsElevated) {
				Set-ItResult -Skipped -Because "this session is elevated; run Run-Tests from a normal terminal to cover this branch"
				return
			}

			# Frame 0 is Test-AdminPrivileges itself, frame 1 the engine line that dispatched it,
			# frame 2 the typed command and frame 3 the interactive prompt, which records no line.
			$result = & $script:InvokeIsolated -ConfigurationValue @{ AutoElevate = $true } -CallStackLines @("", '& $stepName', "Install-Something -Foo", "")

			$relaunch = @($result.Calls | Where-Object { $_.Name -eq "Open-Terminal" })
			$relaunch.Count | Should -Be 1
			$relaunch[0].Command | Should -BeLike "Set-Location -Path '*'; Install-Something -Foo"
			$relaunch[0].Command | Should -Not -BeLike '*$stepName*'
		}
	}
}
