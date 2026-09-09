#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "AI\Functions"
	. "$FunctionsPath\Get-AiSkillManifest.ps1"
	. "$FunctionsPath\Get-AiSkillDescription.ps1"
	. "$FunctionsPath\Update-AiSkills.ps1"
}

Describe "Update-AiSkills" {
	BeforeEach {
		Mock Write-LogTitle { }
		Mock Write-LogStep { }
		Mock Write-LogSuccess { }
		Mock Write-LogWarning { }
		Mock Write-LogError { }

		# TestDrive is shared by every It in this Describe, so start each test from a clean slate.
		$script:Root = Join-Path $TestDrive "Skills"
		$script:Fixture = Join-Path $TestDrive "fixture\skills-abc123"
		foreach ($stale in @($script:Root, (Join-Path $TestDrive "fixture"))) {
			if (Test-Path -Path $stale) { Remove-Item -Path $stale -Recurse -Force }
		}

		# The "archive": a fixture tree shaped like a GitHub zipball, laid down by the
		# Expand-Archive mock so no network or zip handling is involved.
		foreach ($skill in @("engineering\alpha", "engineering\bravo", "productivity\charlie")) {
			$dir = Join-Path $script:Fixture "skills\$skill"
			New-Item -ItemType Directory -Path $dir -Force | Out-Null
			$name = Split-Path $skill -Leaf
			Set-Content -Path (Join-Path $dir "SKILL.md") -Value @("---", "name: $name", "description: Does $name things.", "---", "Body of $name.")
		}
		Set-Content -Path (Join-Path $script:Fixture "skills\engineering\alpha\FORMAT.md") -Value "format"
		New-Item -ItemType Directory -Path (Join-Path $script:Fixture "skills\engineering\alpha\scripts") -Force | Out-Null
		Set-Content -Path (Join-Path $script:Fixture "skills\engineering\alpha\scripts\loop.sh") -Value "#!/bin/sh"
		New-Item -ItemType Directory -Path (Join-Path $script:Fixture "skills\engineering\not-a-skill") -Force | Out-Null
		Set-Content -Path (Join-Path $script:Fixture "LICENSE") -Value "MIT License"

		$script:Sources = @{
			demo = @{
				Repository = "someone/skills"
				Ref        = "main"
				Folders    = @("skills/engineering", "skills/productivity")
				Exclude    = @()
			}
		}
		Mock Resolve-AiSkillsConfig { @{ Root = $script:Root; Harnesses = @(); WSLHarnesses = @(); Sources = $script:Sources } }

		Mock Invoke-RestMethod { [pscustomobject]@{ sha = "abc123def456" } }
		Mock Invoke-WebRequest { }
		Mock Expand-Archive {
			New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
			Copy-Item -Path $script:Fixture -Destination $DestinationPath -Recurse -Force
		}
	}

	It "vendors every skill of a source flat into Root\<source>, with supporting files" {
		Update-AiSkills

		$dest = Join-Path $script:Root "demo"
		(Get-ChildItem -Path $dest -Directory).Name | Sort-Object | Should -Be @("alpha", "bravo", "charlie")
		Test-Path (Join-Path $dest "alpha\FORMAT.md") | Should -BeTrue
		Test-Path (Join-Path $dest "alpha\scripts\loop.sh") | Should -BeTrue
		Test-Path (Join-Path $dest "engineering") | Should -BeFalse
		Test-Path (Join-Path $dest "not-a-skill") | Should -BeFalse
		Should -Invoke Write-LogError -Times 0
	}

	It "resolves the ref through the commits API and downloads that exact commit" {
		Update-AiSkills

		Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter { $Uri -eq "https://api.github.com/repos/someone/skills/commits/main" }
		Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter { $Uri -eq "https://github.com/someone/skills/archive/abc123def456.zip" }
	}

	It "writes UPSTREAM.md with the pinned commit and every skill, and copies the license" {
		Update-AiSkills

		$manifest = Get-Content -Path (Join-Path $script:Root "demo\UPSTREAM.md") -Raw
		$manifest | Should -Match 'https://github.com/someone/skills'
		$manifest | Should -Match '\*\*Commit:\*\* `abc123def456`'
		$manifest | Should -Match '\| `alpha` \| `skills/engineering` \| Does alpha things\. \|'
		$manifest | Should -Match '\| `charlie` \| `skills/productivity` \|'
		$manifest | Should -Match '\*\*Excluded:\*\* none'
		Get-Content -Path (Join-Path $script:Root "demo\LICENSE.someone-skills.txt") -Raw | Should -Match 'MIT License'
	}

	It "skips excluded skills and records the exclusion" {
		$script:Sources.demo.Exclude = @("bravo")

		Update-AiSkills

		Test-Path (Join-Path $script:Root "demo\bravo") | Should -BeFalse
		Test-Path (Join-Path $script:Root "demo\alpha") | Should -BeTrue
		Get-Content -Path (Join-Path $script:Root "demo\UPSTREAM.md") -Raw | Should -Match '\*\*Excluded:\*\* `bravo`'
	}

	It "leaves hand-made folders alone and removes only previously vendored skills that vanished upstream" {
		Update-AiSkills

		$own = Join-Path $script:Root "demo\my-own-skill"
		New-Item -ItemType Directory -Path $own -Force | Out-Null
		Set-Content -Path (Join-Path $own "SKILL.md") -Value "mine"

		Remove-Item -Path (Join-Path $script:Fixture "skills\engineering\bravo") -Recurse -Force
		$delta = Join-Path $script:Fixture "skills\engineering\delta"
		New-Item -ItemType Directory -Path $delta -Force | Out-Null
		Set-Content -Path (Join-Path $delta "SKILL.md") -Value @("---", "name: delta", "description: >", "  Folded", "  description.", "---")

		Update-AiSkills

		(Get-ChildItem -Path (Join-Path $script:Root "demo") -Directory).Name | Sort-Object | Should -Be @("alpha", "charlie", "delta", "my-own-skill")
		Get-Content -Path (Join-Path $own "SKILL.md") -Raw | Should -Match 'mine'
		Get-Content -Path (Join-Path $script:Root "demo\UPSTREAM.md") -Raw | Should -Match '\| `delta` \| `skills/engineering` \| Folded description\. \|'
		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -like "*bravo*" }
	}

	It "refreshes only the named source and rejects unknown names" {
		$script:Sources.other = @{ Repository = "someone/other"; Ref = "v1"; Folders = @("skills/productivity") }

		Update-AiSkills -Source other

		Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $Uri -eq "https://api.github.com/repos/someone/other/commits/v1" }
		Test-Path (Join-Path $script:Root "other\charlie") | Should -BeTrue
		Test-Path (Join-Path $script:Root "demo") | Should -BeFalse

		Update-AiSkills -Source nope
		Should -Invoke Write-LogError -Times 1 -ParameterFilter { $Message -like "*Unknown AI skill source*" }
	}

	It "reports staleness with -Check without downloading or writing" {
		Update-AiSkills
		Mock Invoke-RestMethod { [pscustomobject]@{ sha = "ffff000011112222" } }

		Update-AiSkills -Check

		Should -Invoke Invoke-WebRequest -Times 1 -Exactly
		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -like "*Behind upstream*" }
		(Get-AiSkillManifest -Path (Join-Path $script:Root "demo\UPSTREAM.md")).Commit | Should -Be "abc123def456"
	}

	It "reports up to date with -Check when the pinned commit matches" {
		Update-AiSkills

		Update-AiSkills -Check

		Should -Invoke Write-LogSuccess -Times 1 -ParameterFilter { $Message -like "*Up to date*" }
	}

	It "reports a failed download and leaves the existing vendored copy untouched" {
		Update-AiSkills
		Mock Invoke-WebRequest { throw "offline" }

		Update-AiSkills

		Should -Invoke Write-LogError -Times 1 -ParameterFilter { $Message -like "*offline*" }
		(Get-ChildItem -Path (Join-Path $script:Root "demo") -Directory).Name | Sort-Object | Should -Be @("alpha", "bravo", "charlie")
	}

	It "does nothing when no sources are configured" {
		$script:Sources = @{}

		Update-AiSkills

		Should -Invoke Invoke-RestMethod -Times 0
		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -like "*No AI skill sources*" }
	}

	It "rejects a repository that is not owner/name" {
		$script:Sources.demo.Repository = "not-a-repo"

		Update-AiSkills

		Should -Invoke Write-LogError -Times 1 -ParameterFilter { $Message -like "*owner/name*" }
		Should -Invoke Invoke-RestMethod -Times 0
	}
}
