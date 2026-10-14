#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	. (Join-Path $ModuleRoot "System\Functions\Repair-TerminalIconsThemeCache.ps1")
}

Describe "Repair-TerminalIconsThemeCache" {
	BeforeEach {
		Mock Write-LogDebug { }
		Mock Write-LogWarning { }
		Mock Write-LogError { }

		# $TestDrive persists across the tests of a Describe, so each test gets its own cache folder
		# holding the two files a healthy cache has: a theme and the preferences.
		$script:cache = Join-Path $TestDrive ([guid]::NewGuid().ToString("N"))
		New-Item -ItemType Directory -Path $script:cache -Force | Out-Null
		$script:theme = Join-Path $script:cache "devblackops_color.xml"
		$script:prefs = Join-Path $script:cache "prefs.xml"
		@{ Name = "devblackops"; Types = @{ Directories = @{ ".git" = "FF4500" } } } | Export-Clixml -Path $script:theme
		@{ CurrentColorTheme = "devblackops"; CurrentIconTheme = "devblackops" } | Export-Clixml -Path $script:prefs
	}

	It "leaves a cache whose files all parse alone and returns nothing" {
		$result = @(Repair-TerminalIconsThemeCache -Path $script:cache)

		$result.Count | Should -Be 0
		(Get-ChildItem -Path $script:cache).Name | Sort-Object | Should -Be @("devblackops_color.xml", "prefs.xml")
		Should -Invoke Write-LogWarning -Times 0
		Should -Invoke Write-LogError -Times 0
	}

	It "moves a file that does not parse aside under a .corrupt-<stamp> name and returns it" {
		# A torn file: the first half of a valid theme, the way a write interrupted by another
		# shell's write leaves it.
		$torn = Join-Path $script:cache "devblackops_light_color.xml"
		$text = Get-Content -Path $script:theme -Raw
		Set-Content -Path $torn -Value $text.Substring(0, [int]($text.Length / 2)) -NoNewline

		$result = @(Repair-TerminalIconsThemeCache -Path $script:cache)

		$result.Count | Should -Be 1
		$result[0] | Should -BeOfType [System.IO.FileInfo]
		$result[0].Name | Should -Match '^devblackops_light_color\.xml\.corrupt-\d{8}-\d{6}$'
		$result[0].DirectoryName | Should -Be $script:cache
		Test-Path -LiteralPath $torn | Should -BeFalse
		Test-Path -LiteralPath $result[0].FullName | Should -BeTrue
		Should -Invoke Write-LogWarning -Times 1 -Exactly
	}

	It "keeps the files that parse in place while one is moved aside" {
		Set-Content -Path (Join-Path $script:cache "devblackops_icon.xml") -Value "<Objs><Obj>never closed"

		$null = Repair-TerminalIconsThemeCache -Path $script:cache

		Test-Path -LiteralPath $script:theme | Should -BeTrue
		Test-Path -LiteralPath $script:prefs | Should -BeTrue
		(Get-ChildItem -Path $script:cache -Filter "*.xml").Name | Sort-Object | Should -Be @("devblackops_color.xml", "prefs.xml")
	}

	It "moves every unreadable file aside, not only the first" {
		Set-Content -Path (Join-Path $script:cache "devblackops_icon.xml") -Value "<Objs><Obj>never closed"
		Set-Content -Path (Join-Path $script:cache "devblackops_light_color.xml") -Value "not xml at all"

		$result = @(Repair-TerminalIconsThemeCache -Path $script:cache)

		$result.Count | Should -Be 2
		($result.Name | Sort-Object) -join "," | Should -Match '^devblackops_icon\.xml\.corrupt-[\d-]+,devblackops_light_color\.xml\.corrupt-[\d-]+$'
		Should -Invoke Write-LogWarning -Times 2 -Exactly
	}

	It "does not probe a file an earlier repair already moved aside" {
		Set-Content -Path (Join-Path $script:cache "devblackops_icon.xml.corrupt-20260101-000000") -Value "garbage"

		$result = @(Repair-TerminalIconsThemeCache -Path $script:cache)

		$result.Count | Should -Be 0
		Should -Invoke Write-LogWarning -Times 0
		Test-Path -LiteralPath (Join-Path $script:cache "devblackops_icon.xml.corrupt-20260101-000000") | Should -BeTrue
	}

	It "returns nothing and warns about nothing when the cache folder does not exist" {
		$result = @(Repair-TerminalIconsThemeCache -Path (Join-Path $TestDrive "no-such-cache"))

		$result.Count | Should -Be 0
		Should -Invoke Write-LogWarning -Times 0
		Should -Invoke Write-LogError -Times 0
	}

	It "logs an error, leaves the file and returns nothing for it when it cannot be moved" {
		$torn = Join-Path $script:cache "devblackops_icon.xml"
		Set-Content -Path $torn -Value "<Objs><Obj>never closed"
		Mock Rename-Item { throw "The process cannot access the file" }

		$result = @(Repair-TerminalIconsThemeCache -Path $script:cache)

		$result.Count | Should -Be 0
		Test-Path -LiteralPath $torn | Should -BeTrue
		Should -Invoke Write-LogError -Times 1 -Exactly
		Should -Invoke Write-LogWarning -Times 0
	}

	It "defaults to the Terminal-Icons folder under APPDATA" {
		$savedAppData = $env:APPDATA
		try {
			$env:APPDATA = Join-Path $TestDrive ([guid]::NewGuid().ToString("N"))
			$default = Join-Path $env:APPDATA "powershell\Community\Terminal-Icons"
			New-Item -ItemType Directory -Path $default -Force | Out-Null
			Set-Content -Path (Join-Path $default "devblackops_icon.xml") -Value "<Objs><Obj>never closed"

			$result = @(Repair-TerminalIconsThemeCache)

			$result.Count | Should -Be 1
			$result[0].DirectoryName | Should -Be $default
		}
		finally {
			$env:APPDATA = $savedAppData
		}
	}
}
