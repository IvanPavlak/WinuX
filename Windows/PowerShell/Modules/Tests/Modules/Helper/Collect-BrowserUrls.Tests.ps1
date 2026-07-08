#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Collect-BrowserUrls.ps1"
}

Describe "Collect-BrowserUrls" {
	It "collects URLs and root subgroup names from nested structures" {
		$value = @(
			@{ Name = "News"; Url = "https://news.example" },
			@{ Work = @(
					@{ Name = "Repo"; Url = "https://github.com" },
					"https://docs.example"
				)
   }
		)

		$result = Collect-BrowserUrls -Value $value

		$result.Urls | Should -Contain "https://news.example"
		$result.Urls | Should -Contain "https://github.com"
		$result.Urls | Should -Contain "https://docs.example"
		$result.Subgroups | Should -Contain "News"
		$result.Subgroups | Should -Contain "Work"
	}

	It "handles direct string and direct hashtable URL input" {
		$stringResult = Collect-BrowserUrls -Value "https://single.example"
		$hashResult = Collect-BrowserUrls -Value @{ Url = "https://hash.example" }

		$stringResult.Urls | Should -Contain "https://single.example"
		$hashResult.Urls | Should -Contain "https://hash.example"
	}
}
