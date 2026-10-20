#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$FunctionsPath\Get-VSCodeLocalExtensions.ps1"
}

Describe "Get-VSCodeLocalExtensions" {
	BeforeEach {
		Mock Write-LogWarning { }
		Mock Write-LogDebug { }

		$script:Root = Join-Path $TestDrive "Extensions"
		Remove-Item -Path $script:Root -Recurse -Force -ErrorAction SilentlyContinue
		New-Item -ItemType Directory -Path $script:Root -Force | Out-Null
	}

	It "lists nothing when the folder does not exist" {
		@(Get-VSCodeLocalExtensions -Root (Join-Path $TestDrive "Missing")).Count | Should -Be 0
	}

	It "reads the id, version, link name and source from package.json" {
		$folder = Join-Path $script:Root "Themes"
		New-Item -ItemType Directory -Path $folder | Out-Null
		Set-Content -Path (Join-Path $folder "package.json") -Value '{ "publisher": "MyPublisher", "name": "Themes", "version": "1.2.0" }'

		$extensions = @(Get-VSCodeLocalExtensions -Root $script:Root)

		$extensions.Count | Should -Be 1
		$extensions[0].Id | Should -Be "mypublisher.themes"
		$extensions[0].Version | Should -Be "1.2.0"
		$extensions[0].LinkName | Should -Be "mypublisher.themes-1.2.0"
		$extensions[0].Source | Should -Be $folder
	}

	It "ignores folders without a package.json and sorts by folder name" {
		foreach ($name in @("Zeta", "Alpha")) {
			$folder = Join-Path $script:Root $name
			New-Item -ItemType Directory -Path $folder | Out-Null
			Set-Content -Path (Join-Path $folder "package.json") -Value "{ ""publisher"": ""p"", ""name"": ""$($name.ToLower())"", ""version"": ""1.0.0"" }"
		}
		New-Item -ItemType Directory -Path (Join-Path $script:Root "Notes") | Out-Null

		@(Get-VSCodeLocalExtensions -Root $script:Root | ForEach-Object { $_.Id }) -join "," | Should -Be "p.alpha,p.zeta"
	}

	It "skips a package.json that is not valid JSON and lists the rest" {
		$bad = Join-Path $script:Root "Bad"
		$good = Join-Path $script:Root "Good"
		New-Item -ItemType Directory -Path $bad, $good | Out-Null
		Set-Content -Path (Join-Path $bad "package.json") -Value "{ not json"
		Set-Content -Path (Join-Path $good "package.json") -Value '{ "publisher": "p", "name": "good", "version": "1.0.0" }'

		$extensions = @(Get-VSCodeLocalExtensions -Root $script:Root)

		@($extensions | ForEach-Object { $_.Id }) | Should -Be @("p.good")
		Should -Invoke Write-LogWarning -Times 1 -Exactly
	}

	It "skips a package.json without a version" {
		$folder = Join-Path $script:Root "NoVersion"
		New-Item -ItemType Directory -Path $folder | Out-Null
		Set-Content -Path (Join-Path $folder "package.json") -Value '{ "publisher": "p", "name": "noversion" }'

		@(Get-VSCodeLocalExtensions -Root $script:Root).Count | Should -Be 0
		Should -Invoke Write-LogWarning -Times 1 -Exactly
	}
}
