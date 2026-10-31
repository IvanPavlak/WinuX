#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "AI\Functions"
	# Dot-sourced so it exists to Mock even in sessions whose imported AI module predates it.
	. "$FunctionsPath\Resolve-AiArtifactsConfig.ps1"
	. "$FunctionsPath\Update-AiArtifacts.ps1"
	. "$FunctionsPath\Get-AiSkillManifest.ps1"
	. "$FunctionsPath\Get-AiSkillDescription.ps1"
	. "$FunctionsPath\Sync-AiManifestCache.ps1"

	function New-FixtureFile([string]$Relative, [string]$Value = "content") {
		$path = Join-Path $script:Fixture $Relative
		New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
		Set-Content -Path $path -Value $Value
	}
}

Describe "Update-AiArtifacts" {
	BeforeEach {
		Mock Write-LogTitle { }
		Mock Write-LogStep { }
		Mock Write-LogSuccess { }
		Mock Write-LogWarning { }
		Mock Write-LogError { }

		# TestDrive is shared by every It in this Describe, so start each test from a clean slate.
		$script:Root = Join-Path $TestDrive "AI"
		$script:Fixture = Join-Path $TestDrive "fixture\MyRepo-abc123"
		foreach ($stale in @($script:Root, (Join-Path $TestDrive "fixture"))) {
			if (Test-Path -Path $stale) { Remove-Item -Path $stale -Recurse -Force }
		}

		# The "archive": one upstream feeding three kinds, laid down by the Expand-Archive mock so
		# no network or zip handling is involved.
		New-FixtureFile "skills\engineering\alpha\SKILL.md" @("---", "name: alpha", "description: Alpha skill.", "---")
		New-FixtureFile "skills\engineering\bravo\SKILL.md" @("---", "name: bravo", "description: Bravo skill.", "---")
		New-FixtureFile "skills\engineering\bravo\tests\case.txt"
		New-FixtureFile "plugins\my-mod\.claude-plugin\plugin.json" '{"name":"band-mod","description":"Draws a band"}'
		New-FixtureFile "plugins\my-mod\hooks\hooks.json"
		New-FixtureFile "rules\Team.md" @("---", "description: Team rules.", "---")
		New-FixtureFile "rules\Strict\RULES.md"
		New-FixtureFile "rules\README.md"
		New-FixtureFile "LICENSE" "MIT License"

		$script:Source = @{
			Repository = "MyOrg/MyRepo"
			Ref        = "main"
			Kinds      = [ordered]@{ skills = @("skills/engineering"); mods = @("plugins"); rules = @("rules") }
			Exclude    = @()
			SkipPaths  = @(".git", ".github", "tests", "design", "docs")
		}
		$script:Sources = [ordered]@{ demo = $script:Source }
		Mock Resolve-AiArtifactsConfig { @{ Root = $script:Root; Sources = $script:Sources } }

		# Every test starts anonymous: no token variables and no GitHub CLI.
		$script:SavedTokens = @{ GITHUB_TOKEN = $env:GITHUB_TOKEN; GH_TOKEN = $env:GH_TOKEN }
		Remove-Item -Path Env:GITHUB_TOKEN, Env:GH_TOKEN -ErrorAction SilentlyContinue
		Mock Get-Command { $null } -ParameterFilter { $Name -eq 'gh' }

		Mock Invoke-RestMethod { [pscustomobject]@{ sha = "abc123def456" } }
		Mock Invoke-WebRequest { }
		Mock Expand-Archive {
			New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
			Copy-Item -Path $script:Fixture -Destination $DestinationPath -Recurse -Force
		}
	}

	AfterEach {
		foreach ($key in $script:SavedTokens.Keys) {
			if ($null -eq $script:SavedTokens[$key]) {
				Remove-Item -Path "Env:$key" -ErrorAction SilentlyContinue
			}
			else {
				Set-Item -Path "Env:$key" -Value $script:SavedTokens[$key]
			}
		}
	}

	It "vendors every kind of one source into its own kind folder from one download" {
		Update-AiArtifacts

		Test-Path (Join-Path $script:Root "Skills\demo\alpha\SKILL.md") | Should -BeTrue
		Test-Path (Join-Path $script:Root "Skills\demo\bravo\SKILL.md") | Should -BeTrue
		Test-Path (Join-Path $script:Root "Mods\demo\band-mod\.claude-plugin\plugin.json") | Should -BeTrue
		Test-Path (Join-Path $script:Root "Mods\demo\band-mod\hooks\hooks.json") | Should -BeTrue
		Should -Invoke Invoke-WebRequest -Times 1 -Exactly
		Should -Invoke Write-LogError -Times 0
	}

	It "turns a top-level NAME.md into item NAME holding the kind's portable file, and skips README" {
		Update-AiArtifacts

		Test-Path (Join-Path $script:Root "Rules\demo\Team\RULES.md") | Should -BeTrue
		Test-Path (Join-Path $script:Root "Rules\demo\Strict\RULES.md") | Should -BeTrue
		Test-Path (Join-Path $script:Root "Rules\demo\README") | Should -BeFalse
	}

	It "leaves the skipped paths of an item upstream" {
		Update-AiArtifacts

		Test-Path (Join-Path $script:Root "Skills\demo\bravo\tests") | Should -BeFalse
	}

	It "leaves an excluded item out" {
		$script:Source.Exclude = @("bravo")

		Update-AiArtifacts

		Test-Path (Join-Path $script:Root "Skills\demo\bravo") | Should -BeFalse
		Test-Path (Join-Path $script:Root "Skills\demo\alpha") | Should -BeTrue
	}

	It "writes an UPSTREAM.md per kind folder that pins the commit and lists the items" {
		Update-AiArtifacts

		$skills = Get-AiSkillManifest -Path (Join-Path $script:Root "Skills\demo\UPSTREAM.md")
		$skills.Commit | Should -Be "abc123def456"
		$skills.Skills | Should -Be @("alpha", "bravo")
		(Get-AiSkillManifest -Path (Join-Path $script:Root "Mods\demo\UPSTREAM.md")).Skills | Should -Be @("band-mod")
		(Get-AiSkillManifest -Path (Join-Path $script:Root "Rules\demo\UPSTREAM.md")).Skills | Should -Be @("Strict", "Team")
		Test-Path (Join-Path $script:Root "Skills\demo\LICENSE.MyOrg-MyRepo.txt") | Should -BeTrue
	}

	It "removes only the items the previous manifest vendored" {
		Update-AiArtifacts
		$handMade = Join-Path $script:Root "Skills\demo\hand-made"
		New-Item -ItemType Directory -Path $handMade -Force | Out-Null
		Remove-Item -Path (Join-Path $script:Fixture "skills\engineering\bravo") -Recurse -Force

		Update-AiArtifacts

		Test-Path (Join-Path $script:Root "Skills\demo\bravo") | Should -BeFalse
		Test-Path $handMade | Should -BeTrue
	}

	It "leaves the vendored copy untouched when a kind finds no item" {
		$script:Source.Kinds = [ordered]@{ agents = @("agents") }

		Update-AiArtifacts

		Test-Path (Join-Path $script:Root "Agents") | Should -BeFalse
		Should -Invoke Write-LogError -Times 2 -Exactly -Because "the empty kind and the summary are both failures"
	}

	It "checks every kind against the upstream head and writes nothing under -Check" {
		Update-AiArtifacts -Check

		Should -Invoke Invoke-RestMethod -Times 1 -Exactly
		Should -Invoke Invoke-WebRequest -Times 0
		Test-Path $script:Root | Should -BeFalse
	}

	It "counts an unknown source as a failure and still refreshes the known ones" {
		Update-AiArtifacts -Source missing, demo

		Should -Invoke Write-LogError -Times 2 -Exactly -Because "the unknown source and the summary"
		Test-Path (Join-Path $script:Root "Skills\demo\alpha") | Should -BeTrue
	}

	It "does nothing without configured sources" {
		$script:Sources = [ordered]@{}

		Update-AiArtifacts

		Should -Invoke Invoke-RestMethod -Times 0
	}

	It "authenticates both requests with GITHUB_TOKEN and downloads the API zipball" {
		$env:GITHUB_TOKEN = "env-token"

		Update-AiArtifacts

		Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter { $Uri -eq "https://api.github.com/repos/MyOrg/MyRepo/commits/main" -and $Headers.Authorization -eq "Bearer env-token" }
		Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter { $Uri -eq "https://api.github.com/repos/MyOrg/MyRepo/zipball/abc123def456" -and $Headers.Authorization -eq "Bearer env-token" }
	}

	It "stays anonymous without a token" {
		Update-AiArtifacts

		Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter { $Headers.Count -eq 0 }
		Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter { $Uri -eq "https://github.com/MyOrg/MyRepo/archive/abc123def456.zip" }
	}

	Context "manifest sources" {
		BeforeEach {
			$script:Manifests = [ordered]@{ thirdparty = @{ Name = "thirdparty"; Path = "C:\nowhere\manifest.tsv" } }
			Mock Resolve-AiArtifactsConfig { @{ Root = $script:Root; Sources = $script:Sources; Manifests = $script:Manifests } }
			$script:Sync = @{ Fetched = @("C:\cache\MyOrg\skills\ref"); Present = @(); Failed = @(); Behind = @(); Problems = @() }
			Mock Sync-AiManifestCache { $script:Sync }
		}

		It "fetches the manifest refs after vendoring, and with only manifests configured" {
			Update-AiArtifacts
			Should -Invoke Sync-AiManifestCache -Times 1 -Exactly -ParameterFilter { -not $Check -and (@($Source) -join ',') -eq 'thirdparty' }

			$script:Sources = [ordered]@{}
			Update-AiArtifacts
			Should -Invoke Sync-AiManifestCache -Times 2 -Exactly
		}

		It "sends -Source to the vendored or the manifest side by name" {
			Update-AiArtifacts -Source thirdparty

			Should -Invoke Invoke-RestMethod -Times 0
			Should -Invoke Sync-AiManifestCache -Times 1 -Exactly
			Should -Invoke Write-LogError -Times 0
		}

		It "-Check reports manifest rows behind their upstream, and counts a failed fetch" {
			$script:Sync.Behind = @(@{ Manifest = "thirdparty"; Name = "tdd"; Kind = "skills"; Source = "https://github.com/MyOrg/skills"; Ref = "0123456789abcdef0123456789abcdef01234567"; Head = "fedcba9876543210fedcba9876543210fedcba98" })
			Update-AiArtifacts -Source thirdparty -Check
			Should -Invoke Sync-AiManifestCache -Times 1 -Exactly -ParameterFilter { $Check }
			Should -Invoke Write-LogWarning -ParameterFilter { $Message -like "*skills/tdd pinned at 0123456*" }

			$script:Sync.Failed = @("https://github.com/MyOrg/skills@ref => git clone failed")
			Update-AiArtifacts -Source thirdparty
			Should -Invoke Write-LogError -ParameterFilter { $Message -like "*finished with 1 failure*" }
		}
	}
}
