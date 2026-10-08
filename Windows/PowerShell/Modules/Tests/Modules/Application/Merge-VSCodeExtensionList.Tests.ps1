#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$FunctionsPath\ConvertFrom-VSCodeExtensionLine.ps1"
	. "$FunctionsPath\Merge-VSCodeExtensionList.ps1"
}

Describe "Merge-VSCodeExtensionList" {
	It "lists every installed extension, sorted, for a profile captured for the first time" {
		$merged = @(Merge-VSCodeExtensionList -Lines @() -Installed @("z.last", "a.first@1.0.0"))
		$merged -join "|" | Should -Be "a.first|z.last"
	}

	It "keeps comments, blank lines and the lines of extensions still installed exactly as written" {
		$lines = @("# formatters", "a.fmt@1.2.3  # pinned", "", "b.lint")
		$merged = @(Merge-VSCodeExtensionList -Lines $lines -Installed @("a.fmt", "b.lint"))
		$merged -join "|" | Should -Be "# formatters|a.fmt@1.2.3  # pinned||b.lint"
	}

	It "removes extensions that are no longer installed" {
		$merged = @(Merge-VSCodeExtensionList -Lines @("a.kept", "b.gone") -Installed @("a.kept"))
		$merged -join "|" | Should -Be "a.kept"
	}

	It "appends newly installed extensions after the existing lines, sorted" {
		$merged = @(Merge-VSCodeExtensionList -Lines @("m.middle") -Installed @("m.middle", "z.new", "c.new"))
		$merged -join "|" | Should -Be "m.middle|c.new|z.new"
	}

	It "matches ids case-insensitively, so a differently cased line is neither dropped nor duplicated" {
		$merged = @(Merge-VSCodeExtensionList -Lines @("MyPublisher.Tool") -Installed @("mypublisher.tool"))
		$merged -join "|" | Should -Be "MyPublisher.Tool"
	}

	It "keeps only the first line of an extension listed twice" {
		$merged = @(Merge-VSCodeExtensionList -Lines @("a.one@1.0.0", "a.one") -Installed @("a.one"))
		$merged -join "|" | Should -Be "a.one@1.0.0"
	}

	It "returns nothing when nothing is listed and nothing is installed" {
		@(Merge-VSCodeExtensionList -Lines @() -Installed @()).Count | Should -Be 0
	}
}
