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

	BeforeAll {
		$DocsRoot = Join-Path (Get-RepositoryPath).Repo "docs"
		$DocsRoot = (Resolve-Path $DocsRoot).Path
		$AllDocFiles = Get-ChildItem -Path $DocsRoot -Recurse -Filter "*.md"
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

			# Match relative links: (../path/file.md) or (path/file.md) - not starting with http or /
			$relativeLinks = [regex]::Matches($content, '\((?!http|/)([^)]+\.md)(?:#[^)]*)?\)') |
				ForEach-Object { $_.Groups[1].Value }

			$broken = @()
			foreach ($link in $relativeLinks) {
				$linkPath = $link -split '#' | Select-Object -First 1
				$fullPath = [System.IO.Path]::GetFullPath((Join-Path $fileDir $linkPath))
				if (-not (Test-Path $fullPath)) {
					$broken += "$link (in $([System.IO.Path]::GetFileName($filePath)))"
				}
			}

			$broken | Should -BeNullOrEmpty -Because "All relative .md links must resolve. Broken: $($broken -join '; ')"
		}
	}
}
