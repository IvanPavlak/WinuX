#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$FunctionsPath\Get-VSCodeProfileItems.ps1"
}

Describe "Get-VSCodeProfileItems" {
	BeforeEach {
		$script:Source = Join-Path $TestDrive "repo\MyProfile"
		$script:Location = Join-Path $TestDrive "user"
		Remove-Item -Path (Join-Path $TestDrive "repo") -Recurse -Force -ErrorAction SilentlyContinue
		New-Item -ItemType Directory -Path $script:Source -Force | Out-Null
	}

	It "lists settings, keybindings, tasks and snippets in that order" {
		$items = @(Get-VSCodeProfileItems -Source $script:Source -Location $script:Location)

		@($items | ForEach-Object { $_.Name }) -join "," | Should -Be "settings.json,keybindings.json,tasks.json,snippets"
		$items[3].IsDirectory | Should -BeTrue
		$items[0].Live | Should -Be (Join-Path $script:Location "settings.json")
	}

	It "marks which items the repository carries" {
		Set-Content -Path (Join-Path $script:Source "settings.json") -Value "{}"

		$items = @(Get-VSCodeProfileItems -Source $script:Source -Location $script:Location)

		$items[0].InRepo | Should -BeTrue
		$items[1].InRepo | Should -BeFalse
	}

	It "uses the shared keybindings.json when there is no Windows file" {
		Set-Content -Path (Join-Path $script:Source "keybindings.json") -Value "[]"

		$keybindings = @(Get-VSCodeProfileItems -Source $script:Source -Location $script:Location)[1]

		$keybindings.Repo | Should -Be (Join-Path $script:Source "keybindings.json")
		$keybindings.Live | Should -Be (Join-Path $script:Location "keybindings.json")
	}

	It "prefers keybindings.windows.json over the shared file" {
		Set-Content -Path (Join-Path $script:Source "keybindings.json") -Value "[]"
		Set-Content -Path (Join-Path $script:Source "keybindings.windows.json") -Value "[]"

		$keybindings = @(Get-VSCodeProfileItems -Source $script:Source -Location $script:Location)[1]

		$keybindings.Repo | Should -Be (Join-Path $script:Source "keybindings.windows.json")
		$keybindings.Live | Should -Be (Join-Path $script:Location "keybindings.json")
	}
}
