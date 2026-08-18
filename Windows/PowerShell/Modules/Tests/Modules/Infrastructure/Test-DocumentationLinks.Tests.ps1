#Requires -Modules Pester

Describe "Documentation Link Validity" {
	<#
	.SYNOPSIS
		Verifies that every Markdown link in _sidebar.md and all docs pages resolves to an existing file.

	.DESCRIPTION
		Parses Markdown link targets of the form (/path/to/file.md) or (../path/to/file.md)
		in every .md file under docs/. Fails if any linked file does not exist on disk.
		Only checks relative .md links - external URLs and anchor-only links are ignored.
	#>

	BeforeDiscovery {
		# -ForEach binds at discovery time, before any BeforeAll has run. This list used to be
		# built in BeforeAll, so it was still null at discovery: under Pester 5 the Context
		# silently generated zero tests and the cross-reference check never actually ran.
		# Pester 6 fails the container on a null/empty -ForEach instead of hiding it.
		$AllDocFiles = Get-ChildItem -Path (Join-Path (Get-RepositoryPath).Repo "docs") -Recurse -Filter "*.md"
	}

	BeforeAll {
		$DocsRoot = Join-Path (Get-RepositoryPath).Repo "docs"
		$DocsRoot = (Resolve-Path $DocsRoot).Path
	}

	Context "Sidebar links resolve to existing files" {
		It "All _sidebar.md links exist on disk" {
			$sidebarPath = Join-Path $DocsRoot "_sidebar.md"
			$content = Get-Content $sidebarPath -Raw
			$links = [regex]::Matches($content, '\(/([^)]+\.md)\)') |
				ForEach-Object { $_.Groups[1].Value }

			$broken = @()
			foreach ($link in $links) {
				$fullPath = Join-Path $DocsRoot ($link -replace '/', [System.IO.Path]::DirectorySeparatorChar)
				if (-not (Test-Path $fullPath)) {
					$broken += $link
				}
			}

			$broken | Should -BeNullOrEmpty -Because "All sidebar links must point to existing .md files. Broken: $($broken -join ', ')"
		}
	}

	Context "Cross-reference links in docs pages resolve" {
		It "File '<_>' has no broken relative .md links" -ForEach @(
			$AllDocFiles | Select-Object -ExpandProperty FullName
		) {
			$filePath = $_
			$fileDir = [System.IO.Path]::GetDirectoryName($filePath)
			$content = Get-Content $filePath -Raw

			# Fenced code blocks hold templates and examples, not navigable links.
			$content = $content -replace '(?s)```.*?```', ''

			# Match only real Markdown links - "](target.md)" - relative, not http or root-anchored.
			# The old pattern matched ANY parenthesized text ending in .md, which flagged prose
			# parentheticals; it went unnoticed because these tests never ran (see BeforeDiscovery).
			$relativeLinks = [regex]::Matches($content, '\]\((?!http|/)([^)\s]+\.md)(?:#[^)]*)?\)') |
				ForEach-Object { $_.Groups[1].Value }

			$broken = @()
			foreach ($link in $relativeLinks) {
				$linkPath = $link -split '#' | Select-Object -First 1
				$fullPath = [System.IO.Path]::GetFullPath((Join-Path $fileDir $linkPath))
				if (-not (Test-Path -LiteralPath $fullPath)) {
					$broken += "$link (in $([System.IO.Path]::GetFileName($filePath)))"
				}
			}

			$broken | Should -BeNullOrEmpty -Because "All relative .md links must resolve. Broken: $($broken -join '; ')"
		}
	}
}
