#Requires -Modules Pester

BeforeAll {
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Start-ProcessDetached.ps1"
}

Describe "Start-ProcessDetached" {
	BeforeEach {
		Mock Write-LogDebug { }
		Mock Invoke-CimMethod { [PSCustomObject]@{ ReturnValue = 0; ProcessId = 4242 } }
	}

	It "creates the process through WMI with the quoted executable and the arguments as given" {
		$result = Start-ProcessDetached -FilePath 'C:\Apps\Tool\Tool.exe' -ArgumentList '-n', '"C:\My Project"'

		$result | Should -Be 4242
		Should -Invoke Invoke-CimMethod -Times 1 -Exactly -ParameterFilter {
			$ClassName -eq 'Win32_Process' -and $MethodName -eq 'Create' -and
			$Arguments.CommandLine -eq '"C:\Apps\Tool\Tool.exe" -n "C:\My Project"' -and
			-not $Arguments.ContainsKey('CurrentDirectory')
		}
	}

	It "passes only the quoted executable when there are no arguments" {
		Start-ProcessDetached -FilePath 'C:\Apps\Tool\Tool.exe'

		Should -Invoke Invoke-CimMethod -Times 1 -Exactly -ParameterFilter {
			$Arguments.CommandLine -eq '"C:\Apps\Tool\Tool.exe"'
		}
	}

	It "hands the working directory to WMI" {
		Start-ProcessDetached -FilePath 'C:\Apps\Tool\Tool.exe' -WorkingDirectory 'C:\Work'

		Should -Invoke Invoke-CimMethod -Times 1 -Exactly -ParameterFilter {
			$Arguments.CurrentDirectory -eq 'C:\Work'
		}
	}

	It "returns nothing when WMI refuses to create the process" {
		Mock Invoke-CimMethod { [PSCustomObject]@{ ReturnValue = 8; ProcessId = $null } }

		Start-ProcessDetached -FilePath 'C:\Apps\Tool\Tool.exe' | Should -BeNullOrEmpty
	}

	It "returns nothing and does not throw when WMI throws" {
		Mock Invoke-CimMethod { throw 'access denied' }

		{ $script:detachedResult = Start-ProcessDetached -FilePath 'C:\Apps\Tool\Tool.exe' } | Should -Not -Throw
		$script:detachedResult | Should -BeNullOrEmpty
	}
}
