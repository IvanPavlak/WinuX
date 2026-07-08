#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Clear-WhatsAppLocalStorage.ps1"
}

Describe "Clear-WhatsAppLocalStorage" {
	BeforeEach {
		$script:Configuration = [PSCustomObject]@{
			Universal = [PSCustomObject]@{
				WhatsAppLocalStoragePath = "C:\\Temp\\WhatsAppStorage"
			}
		}

		Mock Test-AdminPrivileges { }
		Mock Get-Process { $null }
		Mock Stop-Process { }
		Mock Test-Path { $false }
		Mock Resolve-Selection { "Yes" }
		Mock Remove-Item { }
		Mock Write-Host { }
		Mock Write-LogTitle { }
		Mock Write-LogStep { }
		Mock Write-LogWarning { }
	}

	It "returns early when storage path does not exist" {
		{ Clear-WhatsAppLocalStorage } | Should -Not -Throw
		Should -Invoke Resolve-Selection -Times 0
		Should -Invoke Remove-Item -Times 0
		Should -Invoke Write-LogTitle -Times 1
		Should -Invoke Write-LogStep -Times 1
		Should -Invoke Write-LogWarning -Times 2
	}
}
