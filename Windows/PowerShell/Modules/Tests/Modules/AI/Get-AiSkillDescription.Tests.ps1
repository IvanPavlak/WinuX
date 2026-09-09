#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "AI\Functions"
	. "$FunctionsPath\Get-AiSkillDescription.ps1"

	function New-SkillFile {
		param([string[]]$Lines)
		$path = Join-Path $TestDrive ("SKILL-{0}.md" -f [guid]::NewGuid().ToString("N"))
		Set-Content -Path $path -Value $Lines
		return $path
	}
}

Describe "Get-AiSkillDescription" {
	It "returns a single-line description" {
		$file = New-SkillFile @("---", "name: alpha", "description: Does alpha things.", "---", "Body.")

		Get-AiSkillDescription -SkillFile $file | Should -Be "Does alpha things."
	}

	It "strips surrounding quotes and unescapes inner quotes" {
		$file = New-SkillFile @("---", "description: `"Use when the user says \`"review since X\`".`"", "---")

		Get-AiSkillDescription -SkillFile $file | Should -Be 'Use when the user says "review since X".'
	}

	It "flattens folded and literal block scalars" {
		$folded = New-SkillFile @("---", "description: >", "  First line", "  second line.", "name: x", "---")
		$literal = New-SkillFile @("---", "description: |-", "  One", "  two", "---")

		Get-AiSkillDescription -SkillFile $folded | Should -Be "First line second line."
		Get-AiSkillDescription -SkillFile $literal | Should -Be "One two"
	}

	It "escapes pipes for Markdown tables" {
		$file = New-SkillFile @("---", "description: a | b", "---")

		Get-AiSkillDescription -SkillFile $file | Should -Be 'a \| b'
	}

	It "returns an empty string without frontmatter or without a description" {
		$noFrontmatter = New-SkillFile @("# Title", "description: not frontmatter")
		$noDescription = New-SkillFile @("---", "name: alpha", "---")

		Get-AiSkillDescription -SkillFile $noFrontmatter | Should -Be ""
		Get-AiSkillDescription -SkillFile $noDescription | Should -Be ""
	}
}
