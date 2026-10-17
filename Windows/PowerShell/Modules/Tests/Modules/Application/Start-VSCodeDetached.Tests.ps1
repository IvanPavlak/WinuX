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
		Mock Get-VSCodeExecutablePath { 'C:\Apps\Code\Code.exe' }
		Mock Start-ProcessDetached { 4242 }
	}

	It "launches Code.exe detached with the arguments and the previous code launch as the fallback" {
		Start-VSCodeDetached -ArgumentList '-n', '"C:\Repos\MyProject"'

		Should -Invoke Start-ProcessDetached -Times 1 -Exactly -ParameterFilter {
			$FilePath -eq 'C:\Apps\Code\Code.exe' -and
			$ArgumentList[0] -eq '-n' -and $ArgumentList[1] -eq '"C:\Repos\MyProject"' -and
			$Fallback.FilePath -eq 'code' -and $Fallback.NoNewWindow -and $Fallback.ErrorAction -eq 'Stop' -and
			$Fallback.ArgumentList[0] -eq '-n' -and $Fallback.ArgumentList[1] -eq '"C:\Repos\MyProject"'
		}
	}

	It "opens an empty window, with a bare code launch as the fallback, when no arguments are given" {
		Start-VSCodeDetached

		Should -Invoke Start-ProcessDetached -Times 1 -Exactly -ParameterFilter {
			$FilePath -eq 'C:\Apps\Code\Code.exe' -and -not $ArgumentList -and
			$Fallback.FilePath -eq 'code' -and $Fallback.NoNewWindow -and -not $Fallback.ContainsKey('ArgumentList')
		}
	}

	It "hands an empty executable and the fallback to the helper when Code.exe cannot be found" {
		Mock Get-VSCodeExecutablePath { $null }

		Start-VSCodeDetached -ArgumentList '-n', '"C:\Repos\MyProject"'

		Should -Invoke Start-ProcessDetached -Times 1 -Exactly -ParameterFilter {
			-not $FilePath -and $Fallback.FilePath -eq 'code' -and $Fallback.ArgumentList[1] -eq '"C:\Repos\MyProject"'
		}
	}

	It "lets a failed launch throw to the caller" {
		Mock Start-ProcessDetached { throw 'code is not installed' }

		{ Start-VSCodeDetached } | Should -Throw 'code is not installed'
	}
}
