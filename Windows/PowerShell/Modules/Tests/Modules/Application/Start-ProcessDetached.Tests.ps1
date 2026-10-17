#Requires -Modules Pester

BeforeAll {
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Start-ProcessDetached.ps1"
}

Describe "Start-ProcessDetached" {
	BeforeEach {
		$script:fallback = @{ FilePath = 'tool'; ArgumentList = @('-n', '"C:\My Project"'); NoNewWindow = $true }

		Mock Write-LogDebug { }
		Mock Start-Process { }
		Mock Invoke-CimMethod { [PSCustomObject]@{ ReturnValue = 0; ProcessId = 4242 } }
	}

	It "creates the process through WMI with the quoted executable and the arguments as given" {
		$result = Start-ProcessDetached -FilePath 'C:\Apps\Tool\Tool.exe' -ArgumentList '-n', '"C:\My Project"' -Fallback $script:fallback

		$result | Should -Be 4242
		Should -Invoke Invoke-CimMethod -Times 1 -Exactly -ParameterFilter {
			$ClassName -eq 'Win32_Process' -and $MethodName -eq 'Create' -and
			$Arguments.CommandLine -eq '"C:\Apps\Tool\Tool.exe" -n "C:\My Project"'
		}
		Should -Invoke Start-Process -Times 0
	}

	It "passes only the quoted executable when there are no arguments" {
		Start-ProcessDetached -FilePath 'C:\Apps\Tool\Tool.exe'

		Should -Invoke Invoke-CimMethod -Times 1 -Exactly -ParameterFilter {
			$Arguments.CommandLine -eq '"C:\Apps\Tool\Tool.exe"'
		}
	}

	It "returns nothing and launches nothing when WMI refuses and no fallback is given" {
		Mock Invoke-CimMethod { [PSCustomObject]@{ ReturnValue = 8; ProcessId = $null } }

		Start-ProcessDetached -FilePath 'C:\Apps\Tool\Tool.exe' | Should -BeNullOrEmpty

		Should -Invoke Start-Process -Times 0
	}

	It "returns nothing and does not throw when WMI throws and no fallback is given" {
		Mock Invoke-CimMethod { throw 'access denied' }

		{ $script:detachedResult = Start-ProcessDetached -FilePath 'C:\Apps\Tool\Tool.exe' } | Should -Not -Throw
		$script:detachedResult | Should -BeNullOrEmpty
	}

	It "runs Start-Process with the fallback parameters and returns nothing when WMI refuses" {
		Mock Invoke-CimMethod { [PSCustomObject]@{ ReturnValue = 8; ProcessId = $null } }

		Start-ProcessDetached -FilePath 'C:\Apps\Tool\Tool.exe' -Fallback $script:fallback | Should -BeNullOrEmpty

		Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
			$FilePath -eq 'tool' -and $NoNewWindow -and $ArgumentList[0] -eq '-n' -and $ArgumentList[1] -eq '"C:\My Project"'
		}
	}

	It "runs the fallback when WMI throws" {
		Mock Invoke-CimMethod { throw 'access denied' }

		Start-ProcessDetached -FilePath 'C:\Apps\Tool\Tool.exe' -Fallback $script:fallback | Should -BeNullOrEmpty

		Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $FilePath -eq 'tool' }
	}

	It "runs the fallback without touching WMI when no executable is given" {
		Start-ProcessDetached -FilePath '' -ArgumentList '-n' -Fallback $script:fallback | Should -BeNullOrEmpty

		Should -Invoke Invoke-CimMethod -Times 0
		Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $FilePath -eq 'tool' }
	}

	It "returns nothing without touching WMI when no executable and no fallback are given" {
		Start-ProcessDetached -FilePath $null | Should -BeNullOrEmpty

		Should -Invoke Invoke-CimMethod -Times 0
		Should -Invoke Start-Process -Times 0
	}

	It "lets a fallback launch error propagate to the caller" {
		Mock Invoke-CimMethod { [PSCustomObject]@{ ReturnValue = 8; ProcessId = $null } }
		Mock Start-Process { throw 'tool is not installed' }

		{ Start-ProcessDetached -FilePath 'C:\Apps\Tool\Tool.exe' -Fallback $script:fallback } | Should -Throw 'tool is not installed'
	}
}
