#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "AI\Functions"
	. "$FunctionsPath\Get-AiSkillManifest.ps1"
}

Describe "Get-AiSkillManifest" {
	It "returns an empty commit and no skills when the manifest does not exist" {
		$result = Get-AiSkillManifest -Path (Join-Path $TestDrive "missing\UPSTREAM.md")

		$result.Commit | Should -Be ""
		$result.Skills | Should -BeNullOrEmpty
	}

	It "reads the pinned commit and every skill row" {
		$path = Join-Path $TestDrive "UPSTREAM.md"
		Set-Content -Path $path -Value @(
			"# Vendored AI skills: demo",
			"",
			"- **Source:** https://github.com/someone/skills",
			"- **Commit:** ``abc123def456`` (ref ``main``)",
			"- **Fetched:** 2026-09-09T12:00:00",
			"",
			"| Skill | Upstream folder | Description |",
			"| ----- | --------------- | ----------- |",
			"| ``alpha`` | ``skills/engineering`` | Does alpha things. |",
			"| ``bravo`` | ``skills/productivity`` | Does bravo things \| with a pipe. |"
		)

		$result = Get-AiSkillManifest -Path $path

		$result.Commit | Should -Be "abc123def456"
		$result.Skills | Should -Be @("alpha", "bravo")
	}

	It "ignores table rows whose first cell is not a backticked name" {
		$path = Join-Path $TestDrive "UPSTREAM.md"
		Set-Content -Path $path -Value @(
			"| Skill | Upstream folder | Description |",
			"| ----- | --------------- | ----------- |",
			"| ``only`` | ``skills`` | x |"
		)

		(Get-AiSkillManifest -Path $path).Skills | Should -Be @("only")
	}
}
