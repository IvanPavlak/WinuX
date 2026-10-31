#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "AI\Functions"
	. "$FunctionsPath\Get-AiArtifactRoster.ps1"
	# The manifest reader is exercised for real against the fixture manifests.
	. "$FunctionsPath\Get-AiArtifactManifest.ps1"

	function New-Item-In([string]$Relative, [string]$File = "SKILL.md") {
		$dir = Join-Path $script:Root $Relative
		New-Item -ItemType Directory -Path (Split-Path -Parent (Join-Path $dir $File)) -Force | Out-Null
		Set-Content -Path (Join-Path $dir $File) -Value "content"
	}
}

Describe "Get-AiArtifactRoster" {
	BeforeEach {
		$script:Root = Join-Path $TestDrive "AI"
		if (Test-Path -Path $script:Root) { Remove-Item -Path $script:Root -Recurse -Force }
		$script:Config = @{ Root = $script:Root; Sources = @{ mattpocock = @{} }; Exclude = @() }
	}

	It "returns an empty roster for a missing root or kind folder" {
		$roster = Get-AiArtifactRoster -Kind Skills -Config $script:Config

		$roster.Items.Count | Should -Be 0
		$roster.Duplicates | Should -BeNullOrEmpty
		$roster.Kind | Should -Be "skills"
	}

	It "reads own first, then winux, example and the configured sources in name order, and no other folder" {
		New-Item-In "Skills\winux\configurator"
		New-Item-In "Skills\mattpocock\tdd"
		New-Item-In "Skills\own\teach-me"
		New-Item-In "Skills\example\sample"
		New-Item-In "Skills\unlisted\document"

		$roster = Get-AiArtifactRoster -Kind Skills -Config $script:Config

		@($roster.Items.Keys) | Should -Be @("teach-me", "configurator", "sample", "tdd")
		@($roster.Items.Values | ForEach-Object { $_.Source }) | Should -Be @("own", "winux", "example", "mattpocock")
		@($roster.Items.Values | ForEach-Object { $_.SourceKind }) | Should -Be @("own", "product", "example", "vendored")
		$roster.Items['tdd'].Path | Should -Be (Join-Path $script:Root "Skills\mattpocock\tdd")
	}

	It "lets own win an item name another source carries, and records the loser" {
		New-Item-In "Skills\winux\document"
		New-Item-In "Skills\own\Document"

		$roster = Get-AiArtifactRoster -Kind Skills -Config $script:Config

		$roster.Items.Count | Should -Be 1
		$roster.Items['document'].Source | Should -Be "own"
		$roster.Duplicates.Count | Should -Be 1
		$roster.Duplicates[0].Source | Should -Be "winux"
		$roster.Duplicates[0].KeptFrom | Should -Be "own"
	}

	It "recognises an item by its kind: SKILL.md, plugin.json, or any file that is not hidden" {
		New-Item-In "Skills\own\real"
		New-Item -ItemType Directory -Path (Join-Path $script:Root "Skills\own\empty") -Force | Out-Null
		New-Item-In "Mods\own\band" ".claude-plugin\plugin.json"
		New-Item-In "Mods\own\no-manifest" "README.md"
		New-Item-In "Rules\own\CoreAiRules" "managed-settings.json"
		New-Item-In "Rules\own\hidden-only" ".keep"

		@((Get-AiArtifactRoster -Kind Skills -Config $script:Config).Items.Keys) | Should -Be @("real")
		@((Get-AiArtifactRoster -Kind Mods -Config $script:Config).Items.Keys) | Should -Be @("band")
		@((Get-AiArtifactRoster -Kind Rules -Config $script:Config).Items.Keys) | Should -Be @("CoreAiRules")
	}

	It "drops an item excluded for every source or for one source" {
		New-Item-In "Rules\example\CoreAiRules" "RULES.md"
		New-Item-In "Rules\own\CoreAiRules" "RULES.md"
		New-Item-In "Rules\own\Other" "RULES.md"
		New-Item-In "Skills\mattpocock\tdd"
		$script:Config.Exclude = @("rules/example/coreairules", "skills/tdd")

		$rules = Get-AiArtifactRoster -Kind Rules -Config $script:Config

		@($rules.Items.Keys) | Should -Be @("CoreAiRules", "Other")
		$rules.Duplicates | Should -BeNullOrEmpty -Because "the excluded example is never a contender"
		(Get-AiArtifactRoster -Kind Skills -Config $script:Config).Items.Count | Should -Be 0
	}

	Context "Checkout and manifest sources" {
		BeforeEach {
			$script:Checkout = Join-Path $TestDrive "MySkills"
			$script:Cache = Join-Path $TestDrive "cache"
			foreach ($stale in @($script:Checkout, $script:Cache)) {
				if (Test-Path -Path $stale) { Remove-Item -Path $stale -Recurse -Force }
			}
			$script:Ref = "0123456789abcdef0123456789abcdef01234567"
			$script:Manifest = Join-Path $TestDrive "manifest.tsv"
			$script:Config.Checkouts = [ordered]@{ myskills = @{ Name = "myskills"; Path = $script:Checkout; Kinds = [ordered]@{ skills = @("skills") } } }
			$script:Config.Manifests = [ordered]@{ thirdparty = @{ Name = "thirdparty"; Path = $script:Manifest } }
			$script:Config.CacheRoot = $script:Cache
			$script:Config.Profile = @{ Enabled = $true; Name = "Personal" }

			# A cached clone with three items, and the manifest rows that point into it.
			foreach ($name in @("tdd", "grill", "design", "own-clash")) {
				$dir = Join-Path $script:Cache "MyOrg\skills\$($script:Ref)\skills\$name"
				New-Item -ItemType Directory -Path $dir -Force | Out-Null
				Set-Content -Path (Join-Path $dir "SKILL.md") -Value $name
			}
			# The derived copy Sync-AiManifestCache makes for the rename= row.
			$renamed = Join-Path $script:Cache "MyOrg\skills\$($script:Ref).derived\grill-me"
			New-Item -ItemType Directory -Path $renamed -Force | Out-Null
			Set-Content -Path (Join-Path $renamed "SKILL.md") -Value "grill-me"
			Set-Content -Path $script:Manifest -Value @(
				"name`tkind`tscope`tsource`tref`tpath`tinstall",
				"tdd`tskills`t*`thttps://github.com/MyOrg/skills`t$($script:Ref)`tskills/tdd`tclone",
				"grill`tskills`tPersonal`thttps://github.com/MyOrg/skills`t$($script:Ref)`tskills/grill`tclone rename=grill-me",
				"own-clash`tskills`tWork`thttps://github.com/MyOrg/skills`t$($script:Ref)`tskills/own-clash`tclone",
				"design`tskills`trepo:MyProject`thttps://github.com/MyOrg/skills`t$($script:Ref)`tskills/design`tclone"
			)
		}

		It "reads own, then checkouts, the product, example, vendored and manifest sources" {
			New-Item -ItemType Directory -Path (Join-Path $script:Checkout "skills\checked") -Force | Out-Null
			Set-Content -Path (Join-Path $script:Checkout "skills\checked\SKILL.md") -Value "checked"
			New-Item-In "Skills\winux\configurator"
			New-Item-In "Skills\own\teach-me"

			$roster = Get-AiArtifactRoster -Kind Skills -Config $script:Config

			@($roster.Items.Keys) | Should -Be @("teach-me", "checked", "configurator", "tdd", "grill-me")
			$roster.Items['checked'].SourceKind | Should -Be "checkout"
			$roster.Items['checked'].Path | Should -Be (Join-Path $script:Checkout "skills\checked")
			$roster.Items['grill-me'].SourceKind | Should -Be "manifest"
			$roster.Items['grill-me'].Source | Should -Be "myorg"
			$roster.Items['grill-me'].Manifest | Should -Be "thirdparty"
			$roster.Items['checked'].Source | Should -Be "myskills" -Because "a checkout item keeps the checkout source's name"
			$roster.Items['grill-me'].Path | Should -Be (Join-Path $script:Cache "MyOrg\skills\$($script:Ref).derived\grill-me") -Because "a rename= row is linked from its derived copy, whose frontmatter carries the new name"
		}

		It "skips a manifest row whose scope names another profile, and every profile row with profiles off" {
			$personal = Get-AiArtifactRoster -Kind Skills -Config $script:Config
			$personal.Items.Contains('own-clash') | Should -BeFalse

			$script:Config.Profile = @{ Enabled = $false }
			$off = Get-AiArtifactRoster -Kind Skills -Config $script:Config
			@($off.Items.Keys) | Should -Be @("tdd")
		}

		It "keeps a repo:<name> row out of the flat roster and hands it over in Repo" {
			$roster = Get-AiArtifactRoster -Kind Skills -Config $script:Config

			$roster.Items.Contains('design') | Should -BeFalse
			@($roster.Repo).Count | Should -Be 1
			$roster.Repo[0].Repository | Should -Be "MyProject"
			$roster.Repo[0].Name | Should -Be "design"
		}

		It "reports a row whose pinned ref is not in the cache, and links the derived copy of a strip-invocation-guard row" {
			Set-Content -Path $script:Manifest -Value @(
				"name`tkind`tscope`tsource`tref`tpath`tinstall",
				"tdd`tskills`t*`thttps://github.com/MyOrg/skills`t$($script:Ref)`tskills/tdd`tclone strip-invocation-guard",
				"gone`tskills`t*`thttps://github.com/MyOrg/other`t$($script:Ref)`tskills/gone`tclone"
			)
			$derived = Join-Path $script:Cache "MyOrg\skills\$($script:Ref).derived\tdd"
			New-Item -ItemType Directory -Path $derived -Force | Out-Null
			Set-Content -Path (Join-Path $derived "SKILL.md") -Value "tdd"

			$roster = Get-AiArtifactRoster -Kind Skills -Config $script:Config

			$roster.Items['tdd'].Path | Should -Be $derived
			$roster.Items.Contains('gone') | Should -BeFalse
			@($roster.Problems | Where-Object { $_ -like "*gone*not in the manifest cache*" }).Count | Should -Be 1
		}

		It "lets an earlier source win a manifest item's name" {
			New-Item-In "Skills\own\tdd"

			$roster = Get-AiArtifactRoster -Kind Skills -Config $script:Config

			$roster.Items['tdd'].Source | Should -Be "own"
			$roster.Duplicates[0].Source | Should -Be "myorg" -Because "a manifest item is labelled by its upstream owner, lowercased"
		}

		It "matches kind/<owner>/name against the manifest's upstream owner, never against the manifest source's name" {
			$script:Config.Exclude = @("skills/myorg/tdd", "skills/thirdparty/grill-me")

			$roster = Get-AiArtifactRoster -Kind Skills -Config $script:Config

			$roster.Items.Contains('tdd') | Should -BeFalse
			$roster.Items.Contains('grill-me') | Should -BeTrue -Because "thirdparty is the manifest source's name, not the item's source"
		}

		It "limits a kind the Include list names, and applies wildcard excludes" {
			New-Item-In "Skills\own\teach-me"
			New-Item-In "Rules\own\MyRules" "RULES.md"
			$script:Config.Include = @("skills/myorg/*")
			$script:Config.Exclude = @("skills/grill-*")

			@((Get-AiArtifactRoster -Kind Skills -Config $script:Config).Items.Keys) | Should -Be @("tdd")
			@((Get-AiArtifactRoster -Kind Rules -Config $script:Config).Items.Keys) | Should -Be @("MyRules") -Because "Include limits only the kinds it names"
		}
	}
}
