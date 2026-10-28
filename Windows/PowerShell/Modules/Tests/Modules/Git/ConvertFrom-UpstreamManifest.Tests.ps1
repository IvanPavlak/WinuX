#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	. (Join-Path $ModuleRoot "Git\Functions\ConvertFrom-UpstreamManifest.ps1")
}

Describe "ConvertFrom-UpstreamManifest" {
	It "reads the single-value keys and collects repeated own and mirror lines in order" {
		$text = @"
# a comment
name        winux
url         https://example.com/acme/WinuX.git
tag-prefix  winux
changelog   Windows/CHANGELOG.md

own         Windows/
own         docs/winux/
mirror      LICENSE
mirror      Git/.gitconfig
"@
		$manifest = ConvertFrom-UpstreamManifest -Text $text

		$manifest.Name | Should -Be 'winux'
		$manifest.Url | Should -Be 'https://example.com/acme/WinuX.git'
		$manifest.TagPrefix | Should -Be 'winux'
		$manifest.Changelog | Should -Be 'Windows/CHANGELOG.md'
		$manifest.Own | Should -Be @('Windows/', 'docs/winux/')
		$manifest.Mirror | Should -Be @('LICENSE', 'Git/.gitconfig')
	}

	It "reads a fork's root-owner and take lines" {
		$settings = ConvertFrom-UpstreamManifest -Text "root-owner fork`r`ntake winux .github/ISSUE_TEMPLATE/`r`ntake foundation README.md"

		$settings.RootOwner | Should -Be 'fork'
		$settings.Take.Count | Should -Be 2
		$settings.Take[0].Upstream | Should -Be 'winux'
		$settings.Take[0].Path | Should -Be '.github/ISSUE_TEMPLATE/'
		$settings.Take[1].Upstream | Should -Be 'foundation'
	}

	It "ignores unknown keys, keys without a value and a take line without a path" {
		$manifest = ConvertFrom-UpstreamManifest -Text "owned-only macupstream`nname`ntake winux`n@PC own Windows/"

		$manifest.Name | Should -BeNullOrEmpty
		$manifest.Own.Count | Should -Be 0
		$manifest.Take.Count | Should -Be 0
	}

	It "returns an empty manifest for empty text" {
		$manifest = ConvertFrom-UpstreamManifest -Text ''

		$manifest.Name | Should -BeNullOrEmpty
		$manifest.Own.Count | Should -Be 0
		$manifest.Mirror.Count | Should -Be 0
	}

	It "parses the manifest WinuX ships" {
		$path = Join-Path (Get-RepositoryPath).PowerShell "Upstream.conf"
		$manifest = ConvertFrom-UpstreamManifest -Text (Get-Content -LiteralPath $path -Raw)

		$manifest.Name | Should -Be 'winux'
		$manifest.Own | Should -Contain 'Windows/'
		$manifest.Changelog | Should -Be 'Windows/CHANGELOG.md'
		(Join-Path (Get-RepositoryPath).Repo $manifest.Changelog) | Should -Exist -Because "Merge-Upstreams reads the commit message's version from it"
	}
}
