#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "AI\Functions"
	. "$FunctionsPath\Get-AiArtifactManifest.ps1"

	$script:Ref = "0123456789abcdef0123456789abcdef01234567"
	function Set-Manifest([string[]]$Rows) {
		$script:Path = Join-Path $TestDrive "manifest.tsv"
		Set-Content -Path $script:Path -Value (@("# A comment", "", "name`tkind`tscope`tsource`tref`tpath`tinstall") + $Rows)
	}
}

Describe "Get-AiArtifactManifest" {
	It "reports a missing file and returns no rows" {
		$result = Get-AiArtifactManifest -Path (Join-Path $TestDrive "missing.tsv")

		@($result.Rows).Count | Should -Be 0
		@($result.Problems).Count | Should -Be 1
	}

	It "reads a row with every column, skipping the header, comments and blank lines" {
		Set-Manifest @("tdd`tskills`t*`thttps://github.com/MyOrg/skills`t$($script:Ref)`tskills/engineering/tdd`tclone")

		$result = Get-AiArtifactManifest -Path $script:Path

		$result.Problems | Should -BeNullOrEmpty
		@($result.Rows).Count | Should -Be 1
		$row = $result.Rows[0]
		$row.Name | Should -Be "tdd"
		$row.LinkName | Should -Be "tdd"
		$row.Kind | Should -Be "skills"
		$row.Scope | Should -Be @("*")
		$row.Owner | Should -Be "MyOrg"
		$row.Repo | Should -Be "skills"
		$row.Ref | Should -Be $script:Ref
		$row.Path | Should -Be "skills/engineering/tdd"
		$row.Repository | Should -BeNullOrEmpty
		$row.StripInvocationGuard | Should -BeFalse
	}

	It "reads profile lists, repo: scopes, rename= and strip-invocation-guard" {
		Set-Manifest @(
			"grill`tskills`tPersonal, Work`thttps://github.com/MyOrg/skills.git`t$($script:Ref)`tskills/grill`tclone rename=grill-me strip-invocation-guard",
			"design`tskills`trepo:MyProject`thttps://github.com/MyOrg/skills`t$($script:Ref)`tskills/design`tclone,strip-invocation-guard"
		)

		$rows = (Get-AiArtifactManifest -Path $script:Path).Rows

		$rows[0].Scope | Should -Be @("Personal", "Work")
		$rows[0].LinkName | Should -Be "grill-me"
		$rows[0].StripInvocationGuard | Should -BeTrue
		$rows[0].Repo | Should -Be "skills" -Because "a trailing .git is not part of the repository name"
		$rows[1].Repository | Should -Be "MyProject"
		$rows[1].StripInvocationGuard | Should -BeTrue
	}

	It "skips a row that breaks the format with a problem naming its line, and keeps the others" {
		Set-Manifest @(
			"branch`tskills`t*`thttps://github.com/MyOrg/skills`tmain`tskills/branch`tclone",
			"escape`tskills`t*`thttps://github.com/MyOrg/skills`t$($script:Ref)`t../outside`tclone",
			"host`tskills`t*`thttps://gitlab.com/MyOrg/skills`t$($script:Ref)`tskills/host`tclone",
			"kind`tthemes`t*`thttps://github.com/MyOrg/skills`t$($script:Ref)`tskills/kind`tclone",
			"short`tskills`t*",
			"mixed`tskills`trepo:MyProject,Personal`thttps://github.com/MyOrg/skills`t$($script:Ref)`tskills/mixed`tclone",
			"option`tskills`t*`thttps://github.com/MyOrg/skills`t$($script:Ref)`tskills/option`tclone --depth=1",
			"good`tskills`t*`thttps://github.com/MyOrg/skills`t$($script:Ref)`tskills/good`tclone"
		)

		$result = Get-AiArtifactManifest -Path $script:Path

		@($result.Rows | ForEach-Object { $_.Name }) | Should -Be @("good")
		@($result.Problems).Count | Should -Be 7
		$result.Problems[0] | Should -BeLike "Line 4:*"
	}

	It "skips a second row installing the same name for the same scope" {
		Set-Manifest @(
			"tdd`tskills`t*`thttps://github.com/MyOrg/skills`t$($script:Ref)`tskills/tdd`tclone",
			"other`tskills`t*`thttps://github.com/MyOrg/other`t$($script:Ref)`tskills/other`tclone rename=tdd"
		)

		$result = Get-AiArtifactManifest -Path $script:Path

		@($result.Rows).Count | Should -Be 1
		@($result.Problems).Count | Should -Be 1
	}
}
