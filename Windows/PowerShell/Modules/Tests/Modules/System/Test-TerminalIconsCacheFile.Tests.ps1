#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	. (Join-Path $ModuleRoot "System\Functions\Test-TerminalIconsCacheFile.ps1")
}

Describe "Test-TerminalIconsCacheFile" {
	BeforeEach {
		$script:file = Join-Path $TestDrive ([guid]::NewGuid().ToString("N") + ".xml")
	}

	It "returns `$true for a file that parses whole and leaves -Reason alone" {
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

	It "returns `$false for two spliced writes that still parse (an object RefId appears twice)" {
		# Two writers ordered Types differently: the head of one stream carries on into the tail of the other.
		$head = @{ Name = "devblackops_light"; Types = [ordered]@{ Directories = @{ WellKnown = @{ src = "87ECAF" } }; Files = @{ ".ps1" = "00BFFF" } } }
		$tail = @{ Name = "devblackops_light"; Types = [ordered]@{ Files = @{ ".ps1" = "00BFFF" }; Directories = @{ WellKnown = @{ src = "87ECAF" } } } }
		$headText = [System.Management.Automation.PSSerializer]::Serialize($head)
		$tailText = [System.Management.Automation.PSSerializer]::Serialize($tail)
		$cut = $headText.IndexOf('<En>', $headText.IndexOf('"Key">Files<') - 40)
		$resume = $tailText.IndexOf('<En>', $tailText.IndexOf('"Key">Directories<') - 40)
		Set-Content -Path $script:file -Value ($headText.Substring(0, $cut) + $tailText.Substring($resume)) -NoNewline
		$reason = $null

		Test-TerminalIconsCacheFile -Path $script:file -Reason ([ref]$reason) | Should -BeFalse
		$reason | Should -Match 'RefId'
	}

	It "returns `$false for a theme file that parses but has no Types.<Table> table" -ForEach @(
		@{ Table = "Directories"; Types = @{ Files = @{ ".ps1" = "00BFFF" } } }
		@{ Table = "Files"; Types = @{ Directories = @{ junction = "7373ff" } } }
	) {
		$theme = Join-Path $TestDrive "devblackops_color.xml"
		@{ Name = "devblackops"; Types = $Types } | Export-Clixml -Path $theme
		$reason = $null

		Test-TerminalIconsCacheFile -Path $theme -Reason ([ref]$reason) | Should -BeFalse
		$reason | Should -Match "Types\.$Table"
	}

	It "returns `$true for a whole theme file" {
		$theme = Join-Path $TestDrive "devblackops_icon.xml"
		@{ Name = "devblackops"; Types = @{ Directories = @{ junction = "x" }; Files = @{ ".ps1" = "y" } } } | Export-Clixml -Path $theme

		Test-TerminalIconsCacheFile -Path $theme | Should -BeTrue
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
