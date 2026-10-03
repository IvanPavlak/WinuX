#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "AI\Functions"
	. "$FunctionsPath\Get-AiSkillManifest.ps1"
	. "$FunctionsPath\Update-AiMods.ps1"
}

Describe "Update-AiMods" {
	BeforeEach {
		Mock Write-LogTitle { }
		Mock Write-LogStep { }
		Mock Write-LogSuccess { }
		Mock Write-LogWarning { }
		Mock Write-LogError { }

		# TestDrive is shared by every It in this Describe, so start each test from a clean slate.
		$script:Root = Join-Path $TestDrive "Mods"
		$script:Fixture = Join-Path $TestDrive "fixture\MyMod-abc123"
		foreach ($stale in @($script:Root, (Join-Path $TestDrive "fixture"))) {
			if (Test-Path -Path $stale) { Remove-Item -Path $stale -Recurse -Force }
		}

		# The "archive": a repository whose root is a mod, shaped like a GitHub zipball and laid
		# down by the Expand-Archive mock so no network or zip handling is involved.
		New-Item -ItemType Directory -Path (Join-Path $script:Fixture ".claude-plugin") -Force | Out-Null
		Set-Content -Path (Join-Path $script:Fixture ".claude-plugin\plugin.json") -Value '{"name":"my-mod","description":"Draws | a band"}'
		foreach ($folder in @("hooks", "types", "tests", "design", "docs", ".github\workflows")) {
			New-Item -ItemType Directory -Path (Join-Path $script:Fixture $folder) -Force | Out-Null
			Set-Content -Path (Join-Path $script:Fixture "$folder\file.txt") -Value $folder
		}
		Set-Content -Path (Join-Path $script:Fixture "README.md") -Value "readme"
		Set-Content -Path (Join-Path $script:Fixture "LICENSE") -Value "MIT License"

		$script:Sources = @{
			demo = @{
				Repository = "MyOrg/MyMod"
				Ref        = "v1.0.0"
			}
		}
		Mock Resolve-AiModsConfig { @{ Root = $script:Root; Harnesses = @(); WSLHarnesses = @(); Sources = $script:Sources } }

		Mock Invoke-RestMethod { [pscustomobject]@{ sha = "abc123def456" } }
		Mock Invoke-WebRequest { }
		Mock Expand-Archive {
			New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
			Copy-Item -Path $script:Fixture -Destination $DestinationPath -Recurse -Force
		}
	}

	It "vendors a repository whose root is the mod under its plugin.json name" {
		Update-AiMods

		$mod = Join-Path $script:Root "demo\my-mod"
		Test-Path (Join-Path $mod ".claude-plugin\plugin.json") | Should -BeTrue
		Test-Path (Join-Path $mod "hooks\file.txt") | Should -BeTrue
		Test-Path (Join-Path $mod "types\file.txt") | Should -BeTrue
		Test-Path (Join-Path $mod "README.md") | Should -BeTrue
		Should -Invoke Write-LogError -Times 0
	}

	It "leaves the default skipped paths upstream" {
		Update-AiMods

		$mod = Join-Path $script:Root "demo\my-mod"
		foreach ($skipped in @("tests", "design", "docs", ".github")) {
			Test-Path (Join-Path $mod $skipped) | Should -BeFalse
		}
		Get-Content -Path (Join-Path $script:Root "demo\UPSTREAM.md") -Raw | Should -Match '\*\*Skipped paths:\*\* `\.git`, `\.github`, `tests`, `design`, `docs`'
	}

	It "replaces the skipped paths with an explicit SkipPaths, including an empty one" {
		$script:Sources.demo.SkipPaths = @()

		Update-AiMods

		Test-Path (Join-Path $script:Root "demo\my-mod\tests\file.txt") | Should -BeTrue
		Get-Content -Path (Join-Path $script:Root "demo\UPSTREAM.md") -Raw | Should -Match '\*\*Skipped paths:\*\* none'
	}

	It "resolves the ref through the commits API and downloads that exact commit" {
		Update-AiMods

		Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter { $Uri -eq "https://api.github.com/repos/MyOrg/MyMod/commits/v1.0.0" }
		Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter { $Uri -eq "https://github.com/MyOrg/MyMod/archive/abc123def456.zip" }
	}

	It "writes UPSTREAM.md in the Update-AiSkills format that Get-AiSkillManifest reads, and copies the license" {
		Update-AiMods

		$manifestPath = Join-Path $script:Root "demo\UPSTREAM.md"
		$manifest = Get-Content -Path $manifestPath -Raw
		$manifest | Should -Match 'https://github.com/MyOrg/MyMod'
		$manifest | Should -Match '\*\*Commit:\*\* `abc123def456` \(ref `v1\.0\.0`\)'
		$manifest | Should -Match '\| `my-mod` \| `\.` \| Draws \\\| a band \|'
		$read = Get-AiSkillManifest -Path $manifestPath
		$read.Commit | Should -Be "abc123def456"
		@($read.Skills) | Should -Be @("my-mod")
		Get-Content -Path (Join-Path $script:Root "demo\LICENSE.MyOrg-MyMod.txt") -Raw | Should -Match 'MIT License'
	}

	It "falls back to the repository name when a root mod's plugin.json has no usable name" {
		Set-Content -Path (Join-Path $script:Fixture ".claude-plugin\plugin.json") -Value '{"name":"bad name!"}'

		Update-AiMods

		Test-Path (Join-Path $script:Root "demo\MyMod\.claude-plugin\plugin.json") | Should -BeTrue
	}

	It "scans subfolders when a configured folder is not itself a mod, honouring Exclude" {
		$multi = Join-Path $TestDrive "fixture\Multi-abc123"
		foreach ($name in @("alpha", "bravo")) {
			New-Item -ItemType Directory -Path (Join-Path $multi "mods\$name\.claude-plugin") -Force | Out-Null
			Set-Content -Path (Join-Path $multi "mods\$name\.claude-plugin\plugin.json") -Value "{`"name`":`"$name`"}"
		}
		New-Item -ItemType Directory -Path (Join-Path $multi "mods\not-a-mod") -Force | Out-Null
		$script:Fixture = $multi
		$script:Sources.demo.Folders = @("mods")
		$script:Sources.demo.Exclude = @("bravo")

		Update-AiMods

		(Get-ChildItem -Path (Join-Path $script:Root "demo") -Directory).Name | Should -Be @("alpha")
		Get-Content -Path (Join-Path $script:Root "demo\UPSTREAM.md") -Raw | Should -Match '\*\*Excluded:\*\* `bravo`'
	}

	It "leaves hand-made folders alone and removes only previously vendored mods that vanished upstream" {
		Update-AiMods

		$own = Join-Path $script:Root "demo\my-own-mod"
		New-Item -ItemType Directory -Path $own -Force | Out-Null
		Set-Content -Path (Join-Path $own "keep.txt") -Value "mine"
		Set-Content -Path (Join-Path $script:Fixture ".claude-plugin\plugin.json") -Value '{"name":"renamed"}'

		Update-AiMods

		(Get-ChildItem -Path (Join-Path $script:Root "demo") -Directory).Name | Sort-Object | Should -Be @("my-own-mod", "renamed")
		Get-Content -Path (Join-Path $own "keep.txt") -Raw | Should -Match 'mine'
		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -like "*Removed mods*my-mod*" }
	}

	It "errors and leaves the vendored copy untouched when no mods are found" {
		Update-AiMods
		Remove-Item -Path (Join-Path $script:Fixture ".claude-plugin") -Recurse -Force

		Update-AiMods

		Should -Invoke Write-LogError -Times 1 -ParameterFilter { $Message -like "*No mods found*" }
		Test-Path (Join-Path $script:Root "demo\my-mod\.claude-plugin\plugin.json") | Should -BeTrue
	}

	It "reports up to date, behind and not vendored with -Check without downloading or writing" {
		Update-AiMods -Check
		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -like "*Not vendored yet*" }
		Test-Path (Join-Path $script:Root "demo") | Should -BeFalse

		Update-AiMods
		Update-AiMods -Check
		Should -Invoke Write-LogSuccess -Times 1 -ParameterFilter { $Message -like "*Up to date*" }

		Mock Invoke-RestMethod { [pscustomobject]@{ sha = "ffff000011112222" } }
		Update-AiMods -Check
		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -like "*Behind upstream*" }
		Should -Invoke Invoke-WebRequest -Times 1 -Exactly
	}

	It "reports a failed download and leaves the existing vendored copy untouched" {
		Update-AiMods
		Mock Invoke-WebRequest { throw "offline" }

		Update-AiMods

		Should -Invoke Write-LogError -Times 1 -ParameterFilter { $Message -like "*offline*" }
		Test-Path (Join-Path $script:Root "demo\my-mod\.claude-plugin\plugin.json") | Should -BeTrue
	}

	It "refreshes only the named source and rejects unknown names" {
		$script:Sources.other = @{ Repository = "MyOrg/Other"; Ref = "main" }

		Update-AiMods -Source other

		Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $Uri -eq "https://api.github.com/repos/MyOrg/Other/commits/main" }
		Test-Path (Join-Path $script:Root "demo") | Should -BeFalse

		Update-AiMods -Source nope
		Should -Invoke Write-LogError -Times 1 -ParameterFilter { $Message -like "*Unknown AI mod source*" }
	}

	It "does nothing when no sources are configured" {
		$script:Sources = @{}

		Update-AiMods

		Should -Invoke Invoke-RestMethod -Times 0
		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -like "*No AI mod sources*" }
	}

	It "rejects a repository that is not owner/name" {
		$script:Sources.demo.Repository = "not-a-repo"

		Update-AiMods

		Should -Invoke Write-LogError -Times 1 -ParameterFilter { $Message -like "*owner/name*" }
		Should -Invoke Invoke-RestMethod -Times 0
	}
}
