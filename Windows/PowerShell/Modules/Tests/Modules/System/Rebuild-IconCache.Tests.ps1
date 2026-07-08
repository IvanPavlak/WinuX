#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Rebuild-IconCache.ps1"
}

Describe "Rebuild-IconCache" {
	BeforeEach {
		$script:Configuration = [PSCustomObject]@{
			Universal = [PSCustomObject]@{
				IconCacheDb     = "C:\\Temp\\IconCache.db"
				IconCacheFolder = "C:\\Temp"
			}
		}

		Mock Write-Host { }
		Mock Stop-Process { }
		Mock Start-Sleep { }
		Mock Test-Path { $true }
		Mock Remove-Item { }
		Mock Get-ChildItem { @([PSCustomObject]@{ FullName = "C:\\Temp\\iconcache_32.db" }) }
		Mock Start-Process { }
	}

	It "stops explorer, removes cache artifacts, and starts explorer" {
		{ Rebuild-IconCache } | Should -Not -Throw

		Should -Invoke Stop-Process -Times 1 -ParameterFilter { $ProcessName -eq "explorer" }
		Should -Invoke Remove-Item -Times 2
		Should -Invoke Start-Process -Times 1 -ParameterFilter { $FilePath -eq "explorer.exe" }
	}
}
