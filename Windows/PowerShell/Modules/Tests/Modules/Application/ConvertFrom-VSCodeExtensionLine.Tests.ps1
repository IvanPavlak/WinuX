#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$FunctionsPath\ConvertFrom-VSCodeExtensionLine.ps1"
}

Describe "ConvertFrom-VSCodeExtensionLine" {
	It "returns nothing for a blank line" {
		ConvertFrom-VSCodeExtensionLine -Line "   " | Should -BeNullOrEmpty
	}

	It "returns nothing for a comment line" {
		ConvertFrom-VSCodeExtensionLine -Line "# formatters" | Should -BeNullOrEmpty
	}

	It "parses an unpinned id" {
		$entry = ConvertFrom-VSCodeExtensionLine -Line "MyPublisher.my-extension"
		$entry.Id | Should -Be "MyPublisher.my-extension"
		$entry.Version | Should -Be ""
	}

	It "parses a pinned id and drops a trailing comment" {
		$entry = ConvertFrom-VSCodeExtensionLine -Line "  mypublisher.tool@1.2.3   # held back"
		$entry.Id | Should -Be "mypublisher.tool"
		$entry.Version | Should -Be "1.2.3"
	}

	It "parses every entry of a list through the pipeline" {
		$entries = @("a.one", "", "# note", "b.two@2.0.0") | ConvertFrom-VSCodeExtensionLine | Where-Object { $_ }
		@($entries).Count | Should -Be 2
		$entries[1].Id | Should -Be "b.two"
	}
}
