#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	. "$ModuleRoot\System\Functions\Format-OnefetchPanel.ps1"

	if (-not (Get-Command Write-LogDebug -ErrorAction SilentlyContinue)) {
		function Write-LogDebug { param([string]$Message, [string]$Style) }
	}

	$script:Esc = [char]27

	# A field line exactly as onefetch writes one under `--text-colors 12 9 9 12 9 15`: the name in
	# bright blue, the colon in bright red, the value in bright white.
	function New-FieldLine {
		param([string]$Name = "Project", [string]$Value = "WinuX")
		"$script:Esc[94m$Name$script:Esc[0m$script:Esc[91m:$script:Esc[0m $script:Esc[97m$Value$script:Esc[0m"
	}
}

Describe "Format-OnefetchPanel" {
	Context "the separator onefetch has no flag for" {
		It "replaces the colon and its trailing space with the separator" {
			$result = New-FieldLine | Format-OnefetchPanel -Separator " -> "

			$result | Should -Match "Project.*->.*WinuX"
			$result.Contains("$script:Esc[91m:$script:Esc[0m ") | Should -BeFalse -Because "the colon and its space are what the separator replaces"
		}

		It "keeps the colon's own color, so the separator is painted like the colon was" {
			# The separator has to land INSIDE the colon's color run - that run is what
			# --text-colors' "colon" slot set, and the point is to keep obeying it.
			$result = New-FieldLine | Format-OnefetchPanel -Separator " -> "

			$result.Contains("$script:Esc[91m -> $script:Esc[0m") | Should -BeTrue
		}

		It "leaves the line alone when no separator is asked for" {
			$line = New-FieldLine

			$line | Format-OnefetchPanel | Should -BeExactly $line
			$line | Format-OnefetchPanel -Separator "" | Should -BeExactly $line
		}

		It "finds the colon whatever --text-colors painted it" {
			# Matched structurally - a color, the colon, a reset - rather than against one code,
			# so a fork that reorders --text-colors is not silently left with colons.
			$line = "$script:Esc[35mProject$script:Esc[0m$script:Esc[36m:$script:Esc[0m x"

			($line | Format-OnefetchPanel -Separator " -> ").Contains("$script:Esc[36m -> $script:Esc[0m") |
				Should -BeTrue
		}

		It "keeps a literal dollar sign in the separator" {
			# "$" introduces a group reference in a replacement string; the separator must not be
			# read as one.
			(New-FieldLine | Format-OnefetchPanel -Separator ' $> ').Contains('$>') | Should -BeTrue
		}
	}

	Context "alignment, once the separator is wider than the colon" {
		It "pads a continuation line by the width the separator added" {
			# onefetch already padded this line to sit under the value; " -> " moves the value two
			# columns right and the continuation has to follow.
			$continuation = "        15% Ivan Pavlak 394"
			$lines = @((New-FieldLine -Name "Authors" -Value "85%"), $continuation)

			$result = @($lines | Format-OnefetchPanel -Separator " -> ")

			$result[1] | Should -BeExactly ("  " + $continuation)
		}

		It "does not pad anything above the first field" {
			# The title and its underline are not in the value column at all.
			$title = "$script:Esc[94mIvanPavlak$script:Esc[0m"
			$result = @(@($title, (New-FieldLine)) | Format-OnefetchPanel -Separator " -> ")

			$result[0] | Should -BeExactly $title
		}

		It "does not pad a line carrying a background color" {
			# The color palette row and the language bar are drawn to a width of their own.
			$palette = "$script:Esc[41m   $script:Esc[49m$script:Esc[42m   $script:Esc[49m"
			$result = @(@((New-FieldLine), $palette) | Format-OnefetchPanel -Separator " -> ")

			$result[1] | Should -BeExactly $palette
		}

		It "does not pad a blank line" {
			$result = @(@((New-FieldLine), "   ") | Format-OnefetchPanel -Separator " -> ")

			$result[1] | Should -BeExactly "   "
		}

		It "leaves the logo's own columns alone and pads only the info column" {
			# The logo and the language chips share a line. Padding at column 0 would slide the
			# logo two columns right and put a slant through it, so the padding goes in where the
			# info column starts instead - measured off the first field line, as the last run of
			# two spaces before the separator.
			$logo = "##########"
			$field = "$logo    $(New-FieldLine -Name 'Languages' -Value 'x')"
			$chips = "$logo         PowerShell (97.6 %)"

			$result = @(@($field, $chips) | Format-OnefetchPanel -Separator " -> ")

			$result[1] | Should -BeExactly "$logo           PowerShell (97.6 %)"
			$result[1].StartsWith($logo) | Should -BeTrue -Because "the logo keeps the columns it was drawn in"
		}

		It "leaves a line too short to reach the info column untouched" {
			# A row of logo with no info beside it has nothing to align.
			$field = "##########    $(New-FieldLine -Name 'Languages' -Value 'x')"
			$short = "####"

			$result = @(@($field, $short) | Format-OnefetchPanel -Separator " -> ")

			$result[1] | Should -BeExactly $short
		}

		It "pads nothing when the separator is no wider than the colon" {
			$continuation = "        15% Ivan Pavlak 394"
			$result = @(@((New-FieldLine), $continuation) | Format-OnefetchPanel -Separator " >")

			$result[1] | Should -BeExactly $continuation
		}
	}

	Context "the true colors --text-colors cannot take" {
		It "repaints a bright index as the true color it is mapped to" {
			# Index 12 is what onefetch emits as ESC[94m; 38;2;30;144;255 is dodger blue, which
			# --text-colors cannot express at all.
			$result = New-FieldLine | Format-OnefetchPanel -Colors @{ "12" = "38;2;30;144;255" }

			$result.Contains("$script:Esc[38;2;30;144;255mProject") | Should -BeTrue
			$result.Contains("$script:Esc[94m") | Should -BeFalse -Because "nothing bright blue should survive the remap"
		}

		It "repaints a standard index too" {
			# 0-7 map to 30-37, 8-15 to 90-97.
			"$script:Esc[34mx" | Format-OnefetchPanel -Colors @{ "4" = "38;2;1;2;3" } |
				Should -BeExactly "$script:Esc[38;2;1;2;3mx"
		}

		It "repaints every mapped index on the same line" {
			$result = New-FieldLine | Format-OnefetchPanel -Colors @{ "12" = "38;2;30;144;255"; "9" = "38;2;255;0;0" }

			$result.Contains("$script:Esc[38;2;30;144;255m") | Should -BeTrue
			$result.Contains("$script:Esc[38;2;255;0;0m") | Should -BeTrue
		}

		It "skips an index outside the 0-15 onefetch understands" {
			$line = New-FieldLine

			$line | Format-OnefetchPanel -Colors @{ "33" = "38;2;1;2;3" } | Should -BeExactly $line
			$line | Format-OnefetchPanel -Colors @{ "blue" = "38;2;1;2;3" } | Should -BeExactly $line
		}

		It "skips an empty replacement rather than erasing the color" {
			$line = New-FieldLine

			$line | Format-OnefetchPanel -Colors @{ "12" = "" } | Should -BeExactly $line
		}

		It "leaves the line alone when no colors are given" {
			$line = New-FieldLine

			$line | Format-OnefetchPanel | Should -BeExactly $line
			$line | Format-OnefetchPanel -Colors @{} | Should -BeExactly $line
		}
	}

	Context "what it must never do" {
		It "emits exactly one line per line, so a measured panel keeps its height" {
			$lines = 1..7 | ForEach-Object { New-FieldLine -Name "F$_" }

			@($lines | Format-OnefetchPanel -Separator " -> " -Colors @{ "12" = "38;2;30;144;255" }).Count |
				Should -Be 7
		}

		It "passes an uncolored stream straight through" {
			# What NO_COLOR gets you. There is nothing to rewrite and nothing to complain about.
			$plain = @("Project: WinuX", "Commits: 12")

			@($plain | Format-OnefetchPanel -Separator " -> " -Colors @{ "12" = "38;2;30;144;255" }) |
				Should -Be $plain
		}

		It "handles an empty line without throwing" {
			{ "" | Format-OnefetchPanel -Separator " -> " } | Should -Not -Throw
		}
	}
}
