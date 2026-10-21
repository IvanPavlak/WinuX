#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Find-Item.ps1"
}

Describe "Find-Item" {
	BeforeEach {
		Mock Write-Host { }
		Mock Get-Location { [PSCustomObject]@{ Path = "C:\\Repo" } }
		Mock Get-ChildItem { @() }
		Mock Split-Path { "C:\\" }
	}

	It "returns null when no matching items are found" {
		$result = Find-Item -Pattern "*.sln" -StartPath "C:\\Repo" -MaxUpwardDepth 1 -MaxDownwardDepth 1

		$result | Should -Be $null
		Should -Invoke Get-ChildItem -Times 1
	}

	It "returns the picked file when two files share a name" {
		# The pick used to be mapped back by file name, which always returned the first one.
		$first = [PSCustomObject]@{ Name = "App.sln"; FullName = "C:\Repo\One\App.sln"; DirectoryName = "C:\Repo\One"; BaseName = "App"; Extension = ".sln" }
		$second = [PSCustomObject]@{ Name = "App.sln"; FullName = "C:\Repo\Two\App.sln"; DirectoryName = "C:\Repo\Two"; BaseName = "App"; Extension = ".sln" }
		Mock Get-ChildItem { @($first, $second) }
		Mock Resolve-Selection { $OptionList[1] }
		Mock Write-LogSuccess { }

		$result = Find-Item -Pattern "*.sln" -StartPath "C:\Repo" -MaxUpwardDepth 1 -MaxDownwardDepth 1

		$result.FullName | Should -Be "C:\Repo\Two\App.sln"
	}

	It "returns the picked directory when its name contains wildcard characters" {
		$plain = [PSCustomObject]@{ Name = "Db"; FullName = "C:\Repo\Db"; BaseName = "Db"; Extension = "" }
		$bracketed = [PSCustomObject]@{ Name = "[Old] Db"; FullName = "C:\Repo\[Old] Db"; BaseName = "[Old] Db"; Extension = "" }
		Mock Get-ChildItem { @($plain, $bracketed) }
		Mock Resolve-Selection { $OptionList[1] }
		Mock Write-LogSuccess { }

		$result = Find-Item -Pattern "*Db*" -StartPath "C:\Repo" -SearchTarget Directory -MaxUpwardDepth 1 -MaxDownwardDepth 1

		$result.FullName | Should -Be "C:\Repo\[Old] Db"
	}
}
