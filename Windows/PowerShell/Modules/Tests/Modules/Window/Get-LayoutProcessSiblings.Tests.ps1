#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Get-LayoutProcessSiblings.ps1"
}

Describe "Get-LayoutProcessSiblings" {
	Context "Entries of one process under different titles" {
		It "marks two titled entries of one process as shared siblings that name each other's title" {
			$relations = Get-LayoutProcessSiblings -LayoutConfig @(
				@{ ProcessName = 'Code'; WindowTitle = 'Alpha - Visual Studio Code$' }
				@{ ProcessName = 'Code'; WindowTitle = 'Beta - Visual Studio Code$' }
			)

			$relations.Count | Should -Be 2
			$relations[0].Shared | Should -BeTrue
			$relations[0].Titled | Should -BeTrue
			$relations[0].CatchAll | Should -BeFalse
			@($relations[0].SiblingTitles) | Should -Be @('Beta - Visual Studio Code$')
			@($relations[1].SiblingTitles) | Should -Be @('Alpha - Visual Studio Code$')
		}

		It "makes the untitled entry next to a titled sibling the catch-all that excludes the sibling's title" {
			$relations = Get-LayoutProcessSiblings -LayoutConfig @(
				@{ ProcessName = 'Code'; WindowTitle = 'Alpha - Visual Studio Code$' }
				@{ ProcessName = 'Code' }
			)

			$relations[1].Shared | Should -BeTrue
			$relations[1].Titled | Should -BeFalse
			$relations[1].CatchAll | Should -BeTrue
			@($relations[1].SiblingTitles) | Should -Be @('Alpha - Visual Studio Code$')
			# The titled entry has no titled sibling: the catch-all contributes no title.
			$relations[0].Shared | Should -BeTrue
			$relations[0].CatchAll | Should -BeFalse
			@($relations[0].SiblingTitles).Count | Should -Be 0
		}

		It "lists every distinct sibling title once and never the entry's own" {
			$relations = Get-LayoutProcessSiblings -LayoutConfig @(
				@{ ProcessName = 'Code'; WindowTitle = 'Alpha' }
				@{ ProcessName = 'Code'; WindowTitle = 'Alpha' }
				@{ ProcessName = 'Code'; WindowTitle = 'Beta' }
				@{ ProcessName = 'Code' }
			)

			@($relations[0].SiblingTitles) | Should -Be @('Beta')
			@($relations[1].SiblingTitles) | Should -Be @('Beta')
			@($relations[2].SiblingTitles) | Should -Be @('Alpha')
			@($relations[3].SiblingTitles | Sort-Object) | Should -Be @('Alpha', 'Beta')
			@($relations | Where-Object { $_.Shared }).Count | Should -Be 4
		}

		It "matches the process case-insensitively and reports the lower-cased process key" {
			$relations = Get-LayoutProcessSiblings -LayoutConfig @(
				@{ ProcessName = 'Code'; WindowTitle = 'Alpha' }
				@{ ProcessName = 'code' }
			)

			$relations[0].ProcessKey | Should -Be 'code'
			$relations[1].ProcessKey | Should -Be 'code'
			$relations[1].CatchAll | Should -BeTrue
			$relations[0].Key | Should -Be 'code|Alpha'
			$relations[1].Key | Should -Be 'code|'
		}

		It "never relates entries of different processes" {
			$relations = Get-LayoutProcessSiblings -LayoutConfig @(
				@{ ProcessName = 'Code'; WindowTitle = 'Alpha' }
				@{ ProcessName = 'Rider' }
			)

			$relations[0].Shared | Should -BeFalse
			$relations[1].Shared | Should -BeFalse
			$relations[1].CatchAll | Should -BeFalse
			@($relations[0].SiblingTitles).Count | Should -Be 0
		}
	}

	Context "Duplicates and untitled entries" {
		It "does not treat identical keys (duplicates) as shared" {
			$relations = Get-LayoutProcessSiblings -LayoutConfig @(
				@{ ProcessName = 'firefox'; WindowTitle = 'Google' }
				@{ ProcessName = 'firefox'; WindowTitle = 'Google' }
			)

			$relations[0].Shared | Should -BeFalse
			$relations[1].Shared | Should -BeFalse
			@($relations[0].SiblingTitles).Count | Should -Be 0
		}

		It "keeps a lone untitled entry, or untitled duplicates, out of the catch-all role" {
			$single = Get-LayoutProcessSiblings -LayoutConfig @(@{ ProcessName = 'Code' })
			$single[0].CatchAll | Should -BeFalse
			$single[0].Shared | Should -BeFalse

			$duplicates = Get-LayoutProcessSiblings -LayoutConfig @(@{ ProcessName = 'Code' }, @{ ProcessName = 'Code' })
			$duplicates[0].CatchAll | Should -BeFalse
			$duplicates[1].CatchAll | Should -BeFalse
		}

		It "counts the '`$null' string and an empty title as untitled" {
			$relations = Get-LayoutProcessSiblings -LayoutConfig @(
				@{ ProcessName = 'Code'; WindowTitle = '$null' }
				@{ ProcessName = 'Code'; WindowTitle = '' }
				@{ ProcessName = 'Code' }
			)

			# All three share the key "code|" - duplicates, not siblings.
			@($relations | ForEach-Object { $_.Key } | Select-Object -Unique) | Should -Be @('code|')
			@($relations | Where-Object { $_.Titled }).Count | Should -Be 0
			@($relations | Where-Object { $_.Shared }).Count | Should -Be 0
		}

		It "makes a '`$null'-titled entry the catch-all next to a titled sibling" {
			$relations = Get-LayoutProcessSiblings -LayoutConfig @(
				@{ ProcessName = 'Code'; WindowTitle = '$null' }
				@{ ProcessName = 'Code'; WindowTitle = 'Alpha' }
			)

			$relations[0].CatchAll | Should -BeTrue
			@($relations[0].SiblingTitles) | Should -Be @('Alpha')
		}
	}

	Context "BrowserLike" {
		It "flags browser processes and the browser token" -TestCases @(
			@{ Process = 'firefox' }
			@{ Process = 'chrome' }
			@{ Process = 'msedge' }
			@{ Process = 'Browser' }
			@{ Process = '(firefox|chrome|msedge|brave)' }
		) {
			param($Process)
			$relations = Get-LayoutProcessSiblings -LayoutConfig @(@{ ProcessName = $Process })

			$relations[0].BrowserLike | Should -BeTrue
		}

		It "does not flag other processes" {
			$relations = Get-LayoutProcessSiblings -LayoutConfig @(@{ ProcessName = 'Code' })

			$relations[0].BrowserLike | Should -BeFalse
		}
	}

	Context "Shape of the result" {
		It "returns a one-element array for a single entry" {
			$relations = Get-LayoutProcessSiblings -LayoutConfig @(@{ ProcessName = 'Code' })

			$relations.GetType().IsArray | Should -BeTrue
			$relations.Count | Should -Be 1
			$relations[0].Index | Should -Be 0
		}

		It "returns one record per entry in input order" {
			$relations = Get-LayoutProcessSiblings -LayoutConfig @(
				@{ ProcessName = 'Rider' }
				@{ ProcessName = 'Code'; WindowTitle = 'Alpha' }
				@{ ProcessName = 'Slack' }
			)

			@($relations | ForEach-Object { $_.Index }) | Should -Be @(0, 1, 2)
			@($relations | ForEach-Object { $_.ProcessKey }) | Should -Be @('rider', 'code', 'slack')
		}

		It "returns an empty array for an empty layout" {
			$relations = Get-LayoutProcessSiblings -LayoutConfig @()

			@($relations).Count | Should -Be 0
		}

		It "tolerates null entries and keeps the other entries' relations" {
			$relations = Get-LayoutProcessSiblings -LayoutConfig @(
				$null
				@{ ProcessName = 'Code'; WindowTitle = 'Alpha' }
				@{ ProcessName = 'Code' }
			)

			$relations.Count | Should -Be 3
			$relations[0].Index | Should -Be 0
			$relations[0].ProcessKey | Should -Be ''
			$relations[0].Shared | Should -BeFalse
			$relations[2].Index | Should -Be 2
			$relations[2].CatchAll | Should -BeTrue
			@($relations[2].SiblingTitles) | Should -Be @('Alpha')
		}
	}
}
