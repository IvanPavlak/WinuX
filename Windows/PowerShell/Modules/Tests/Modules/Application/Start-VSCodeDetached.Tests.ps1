#Requires -Modules Pester

BeforeAll {
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Start-VSCodeDetached.ps1"
	. "$AppFunctionsPath\Start-ProcessDetached.ps1"
	. "$AppFunctionsPath\Get-VSCodeExecutablePath.ps1"
	. "$AppFunctionsPath\Get-VSCodeCliPath.ps1"
}

Describe "Start-VSCodeDetached" {
	BeforeEach {
		Mock Write-LogDebug { }
		Mock Start-Process { }
		Mock Get-VSCodeExecutablePath { 'C:\Apps\Code\Code.exe' }
		Mock Start-ProcessDetached { 4242 }
	}

	It "launches Code.exe detached with the arguments and never touches Start-Process" {
		Start-VSCodeDetached -ArgumentList '-n', '"C:\Repos\MyProject"'

		Should -Invoke Start-ProcessDetached -Times 1 -Exactly -ParameterFilter {
			$FilePath -eq 'C:\Apps\Code\Code.exe' -and $ArgumentList[0] -eq '-n' -and $ArgumentList[1] -eq '"C:\Repos\MyProject"'
		}
		Should -Invoke Start-Process -Times 0
	}

	It "opens an empty window when no arguments are given" {
		Start-VSCodeDetached

		Should -Invoke Start-ProcessDetached -Times 1 -Exactly -ParameterFilter {
			$FilePath -eq 'C:\Apps\Code\Code.exe' -and -not $ArgumentList
		}
	}

	It "falls back to code on PATH, sharing the console, when Code.exe cannot be found" {
		Mock Get-VSCodeExecutablePath { $null }

		Start-VSCodeDetached -ArgumentList '-n', '"C:\Repos\MyProject"'

		Should -Invoke Start-ProcessDetached -Times 0
		Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
			$FilePath -eq 'code' -and $NoNewWindow -and $ArgumentList[0] -eq '-n' -and $ArgumentList[1] -eq '"C:\Repos\MyProject"'
		}
	}

	It "falls back to code on PATH when the detached launch fails" {
		Mock Start-ProcessDetached { $null }

		Start-VSCodeDetached

		Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
			$FilePath -eq 'code' -and $NoNewWindow -and -not $ArgumentList
		}
	}

	It "lets a failed fallback launch throw to the caller" {
		Mock Get-VSCodeExecutablePath { $null }
		Mock Start-Process { throw 'code is not installed' }

		{ Start-VSCodeDetached } | Should -Throw
	}
}
