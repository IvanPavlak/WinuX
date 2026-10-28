#Requires -Modules Pester

Describe "Shared root and upstream manifest" {
	<#
	.SYNOPSIS
		Keeps the files every upstream shares at the repository root generic, and WinuX's manifest
		true to the tree.

	.DESCRIPTION
		A fork may merge several upstreams (WinuX and Foundation). The generic pointer files at the
		root and the docsify shell are byte-identical in every upstream and never edited, so they
		never conflict in such a fork - which holds only while they name no project. And
		Merge-Upstreams takes WinuX's paths by its manifest, Windows/PowerShell/Upstream.conf, so
		every path the manifest names must exist: a room that moved without its own line would
		be declined in a fork that owns its root.
	#>

	BeforeDiscovery {
		$PointerFiles = @(
			'AGENTS.md', 'CHANGELOG.md', 'CONTRIBUTING.md', 'SECURITY.md', 'VERSIONING.md', 'CONTEXT.md',
			'NOTICE', 'THIRD-PARTY-LICENSES.md', 'AI/Mods/README.md', 'AI/Skills/README.md',
			'docs/docs_overview.md', 'docs/index.html'
		)
	}

	BeforeAll {
		$RepoRoot = (Get-RepositoryPath).Repo
		. (Join-Path (Get-RepositoryPath).Modules "Git\Functions\ConvertFrom-UpstreamManifest.ps1")
		$Manifest = ConvertFrom-UpstreamManifest -Text (Get-Content -LiteralPath (Join-Path (Get-RepositoryPath).PowerShell "Upstream.conf") -Raw)
	}

	Context "Generic shared files" {
		It "'<_>' names no project" -ForEach $PointerFiles {
			$path = Join-Path $RepoRoot $_
			$path | Should -Exist -Because "every upstream ships the same generic $_"
			$content = Get-Content -LiteralPath $path -Raw
			$content | Should -Not -Match '(?i)winux|foundation' -Because "$_ is byte-identical in every upstream, so it names none of them (project text goes in Windows/ or docs/winux/)"
		}
	}

	Context "WinuX's manifest" {
		It "names WinuX, its URL, tag prefix and an existing changelog" {
			$Manifest.Name | Should -Be 'winux'
			$Manifest.Url | Should -Match '^https://github\.com/.+/WinuX(\.git)?$'
			$Manifest.TagPrefix | Should -Be 'winux'
			Join-Path $RepoRoot $Manifest.Changelog | Should -Exist
		}

		It "names only paths that exist" {
			$missing = @(@($Manifest.Own) + @($Manifest.Mirror) | Where-Object { -not (Test-Path -LiteralPath (Join-Path $RepoRoot $_.TrimEnd('/'))) })

			$missing | Should -BeNullOrEmpty -Because "a manifest line that names nothing is a room that moved without its line. Missing: $($missing -join ', ')"
		}

		It "owns the project folders and its documents' folder" {
			$Manifest.Own | Should -Contain 'Windows/'
			$Manifest.Own | Should -Contain 'docs/winux/'
		}
	}
}
