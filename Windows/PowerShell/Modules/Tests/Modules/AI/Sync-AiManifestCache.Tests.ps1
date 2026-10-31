#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "AI\Functions"
	. "$FunctionsPath\Sync-AiManifestCache.ps1"
	. "$FunctionsPath\Get-AiArtifactManifest.ps1"
}

Describe "Sync-AiManifestCache" {
	BeforeEach {
		$script:Cache = Join-Path $TestDrive "cache"
		if (Test-Path -Path $script:Cache) { Remove-Item -Path $script:Cache -Recurse -Force }
		$script:Ref = "0123456789abcdef0123456789abcdef01234567"
		$script:Head = "fedcba9876543210fedcba9876543210fedcba98"
		$script:Manifest = Join-Path $TestDrive "manifest.tsv"
		Set-Content -Path $script:Manifest -Value @(
			"name`tkind`tscope`tsource`tref`tpath`tinstall",
			"tdd`tskills`t*`thttps://github.com/MyOrg/skills`t$($script:Ref)`tskills/tdd`tclone strip-invocation-guard",
			"work-only`tskills`tWork`thttps://github.com/MyOrg/work`t$($script:Ref)`tskills/work-only`tclone"
		)
		$script:Config = @{
			Manifests = [ordered]@{ thirdparty = @{ Name = "thirdparty"; Path = $script:Manifest } }
			CacheRoot = $script:Cache
			Profile   = @{ Enabled = $true; Name = "Personal" }
		}

		# A stand-in git: clone makes the folder, a checkout (of FETCH_HEAD or the pin) lays down
		# the pinned tree, ls-remote answers the upstream head. It records the prompt switches it
		# saw, so a test can tell git never waits for a credential prompt.
		$script:GitCalls = @()
		$script:GitPrompts = @()
		Mock Write-LogStep { }
		Mock git {
			$script:GitCalls += , @($args)
			$script:GitPrompts += "$($env:GIT_TERMINAL_PROMPT)/$($env:GCM_INTERACTIVE)"
			$global:LASTEXITCODE = 0
			if ($args[0] -eq 'clone') {
				New-Item -ItemType Directory -Path $args[-1] -Force | Out-Null
			}
			elseif ($args[0] -eq '-C' -and $args -contains 'checkout') {
				$skill = Join-Path $args[1] "skills\tdd"
				New-Item -ItemType Directory -Path $skill -Force | Out-Null
				Set-Content -Path (Join-Path $skill "SKILL.md") -Value @("---", "name: tdd", "disable-model-invocation: true", "description: Tests first.", "---", "Body")
			}
			elseif ($args[0] -eq 'ls-remote') {
				"$($script:Head)`tHEAD"
			}
		}
	}

	It "does nothing without a manifest source" {
		$result = Sync-AiManifestCache -Config @{ Manifests = [ordered]@{}; CacheRoot = $script:Cache }

		Should -Invoke git -Times 0
		@($result.Fetched).Count | Should -Be 0
	}

	It "clones each pinned ref the rows that apply need, into <owner>\<repo>\<ref>, and only those" {
		$result = Sync-AiManifestCache -Config $script:Config

		$folder = Join-Path $script:Cache "MyOrg\skills\$($script:Ref)"
		$result.Fetched | Should -Be @($folder)
		Test-Path -LiteralPath $folder -PathType Container | Should -BeTrue
		Test-Path -LiteralPath "$folder.partial" | Should -BeFalse
		Test-Path -LiteralPath (Join-Path $script:Cache "MyOrg\work") | Should -BeFalse -Because "a row scoped to another profile is not fetched"
	}

	It "never fetches a ref that is already in the cache" {
		Sync-AiManifestCache -Config $script:Config | Out-Null
		$script:GitCalls = @()

		$result = Sync-AiManifestCache -Config $script:Config

		$script:GitCalls.Count | Should -Be 0
		@($result.Present).Count | Should -Be 1
	}

	It "makes the derived copy of a strip-invocation-guard row without the disable-model-invocation line" {
		Sync-AiManifestCache -Config $script:Config | Out-Null

		$derived = Join-Path $script:Cache "MyOrg\skills\$($script:Ref).derived\tdd\SKILL.md"
		$lines = @(Get-Content -LiteralPath $derived)
		$lines | Should -Not -Contain "disable-model-invocation: true"
		$lines | Should -Contain "description: Tests first."
		@(Get-Content -LiteralPath (Join-Path $script:Cache "MyOrg\skills\$($script:Ref)\skills\tdd\SKILL.md")) | Should -Contain "disable-model-invocation: true" -Because "the clone itself stays as pinned"
	}

	It "makes the derived copy of a rename= row under the new name, with the frontmatter name rewritten" {
		Set-Content -Path $script:Manifest -Value @(
			"name`tkind`tscope`tsource`tref`tpath`tinstall",
			"tdd`tskills`t*`thttps://github.com/MyOrg/skills`t$($script:Ref)`tskills/tdd`tclone rename=test-first"
		)

		Sync-AiManifestCache -Config $script:Config | Out-Null

		$lines = @(Get-Content -LiteralPath (Join-Path $script:Cache "MyOrg\skills\$($script:Ref).derived\test-first\SKILL.md"))
		$lines | Should -Contain "name: test-first"
		$lines | Should -Not -Contain "name: tdd"
		$lines | Should -Contain "disable-model-invocation: true" -Because "only strip-invocation-guard removes that line"
	}

	It "fetches only the pinned commit (a shallow fetch by id), never the history, when the server allows it" {
		Sync-AiManifestCache -Config $script:Config | Out-Null

		$fetches = @($script:GitCalls | Where-Object { $_ -contains 'fetch' })
		$fetches.Count | Should -Be 1
		$fetches[0] | Should -Contain '--depth'
		$fetches[0] | Should -Contain $script:Ref
		@($script:GitCalls | Where-Object { $_[0] -eq 'clone' }).Count | Should -Be 0 -Because "the full clone is only the fallback"
	}

	It "falls back to the full clone when the shallow fetch by id is refused" {
		Mock git { $global:LASTEXITCODE = 128 } -ParameterFilter { $args -contains 'fetch' }

		$result = Sync-AiManifestCache -Config $script:Config

		$folder = Join-Path $script:Cache "MyOrg\skills\$($script:Ref)"
		$result.Fetched | Should -Be @($folder)
		@($script:GitCalls | Where-Object { $_[0] -eq 'clone' }).Count | Should -Be 1
		Test-Path -LiteralPath (Join-Path $folder "skills\tdd\SKILL.md") | Should -BeTrue
	}

	It "runs git with its credential prompts off, announces each fetch, and puts the prompt settings back" {
		$env:GIT_TERMINAL_PROMPT = $null
		$env:GCM_INTERACTIVE = $null

		Sync-AiManifestCache -Config $script:Config | Out-Null

		$script:GitPrompts | Should -Not -BeNullOrEmpty
		@($script:GitPrompts | Where-Object { $_ -ne '0/never' }).Count | Should -Be 0
		Should -Invoke Write-LogStep -Times 1 -Exactly -ParameterFilter { $Message -like "*MyOrg/skills@0123456*" }
		$env:GIT_TERMINAL_PROMPT | Should -BeNullOrEmpty
		$env:GCM_INTERACTIVE | Should -BeNullOrEmpty
	}

	It "reports a failed clone and leaves no folder that looks complete" {
		Mock git { $global:LASTEXITCODE = 128 } -ParameterFilter { $args[0] -eq 'clone' -or $args -contains 'fetch' }

		$result = Sync-AiManifestCache -Config $script:Config

		@($result.Failed).Count | Should -Be 1
		Test-Path -LiteralPath (Join-Path $script:Cache "MyOrg\skills\$($script:Ref)") | Should -BeFalse
		Test-Path -LiteralPath (Join-Path $script:Cache "MyOrg\skills\$($script:Ref).partial") | Should -BeFalse
	}

	It "-Check reports the rows whose upstream head moved past the pin, fetching nothing" {
		$result = Sync-AiManifestCache -Config $script:Config -Check

		@($result.Behind).Count | Should -Be 1
		$result.Behind[0].Name | Should -Be "tdd"
		$result.Behind[0].Head | Should -Be $script:Head
		Should -Invoke git -Times 0 -ParameterFilter { $args[0] -eq 'clone' }
		Test-Path -LiteralPath $script:Cache | Should -BeFalse
	}

	It "-Check reports nothing when the pin is the upstream head" {
		$script:Head = $script:Ref

		(Sync-AiManifestCache -Config $script:Config -Check).Behind | Should -BeNullOrEmpty
	}
}
