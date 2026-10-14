#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	. (Join-Path $ModuleRoot "System\Functions\Test-TerminalIconsCacheFile.ps1")
}

Describe "Test-TerminalIconsCacheFile" {
	BeforeEach {
		$script:file = Join-Path $TestDrive ([guid]::NewGuid().ToString("N") + ".xml")
	}

	It "returns `$true for a file that parses as Clixml and leaves -Reason alone" {
		@{ Name = "devblackops" } | Export-Clixml -Path $script:file
		$reason = "untouched"

		Test-TerminalIconsCacheFile -Path $script:file -Reason ([ref]$reason) | Should -BeTrue
		$reason | Should -Be "untouched"
	}

	It "returns `$false for a torn file and passes the parse error back" {
		@{ Name = "devblackops"; Types = @{ ".git" = "FF4500" } } | Export-Clixml -Path $script:file
		$text = Get-Content -Path $script:file -Raw
		Set-Content -Path $script:file -Value $text.Substring(0, [int]($text.Length / 2)) -NoNewline
		$reason = $null

		Test-TerminalIconsCacheFile -Path $script:file -Reason ([ref]$reason) | Should -BeFalse
		$reason | Should -Not -BeNullOrEmpty
	}

	It "returns `$false instead of throwing for a file that does not exist" {
		{ $script:result = Test-TerminalIconsCacheFile -Path (Join-Path $TestDrive "missing.xml") } | Should -Not -Throw
		$script:result | Should -BeFalse
	}

	It "works without -Reason" {
		Set-Content -Path $script:file -Value "not xml at all"

		Test-TerminalIconsCacheFile -Path $script:file | Should -BeFalse
	}
}
