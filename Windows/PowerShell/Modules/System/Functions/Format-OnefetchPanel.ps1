function Format-OnefetchPanel {
	<#
	.SYNOPSIS
		Restyles onefetch's output as it streams past - true-color field names, and a separator
		other than the hardcoded colon.

	.DESCRIPTION
		onefetch has no configuration file. Unlike fastfetch, which reads a config.jsonc, onefetch
		takes its entire appearance from the command line, and two things cannot be said there at
		all:

		  - Color. --text-colors accepts ANSI indices 0-15 only; 16-255 is rejected outright
		    ("33 is not in 0..16") and there is no true-color form, so a palette written as
		    "38;2;30;144;255" in a fastfetch configuration cannot be matched exactly.
		  - The separator. The ":" after each field name is hardcoded. In --text-colors "colon" is
		    a COLOR slot, not a string, and --number-separator is the thousands separator inside
		    numbers - neither replaces the character.

		Both are reachable afterwards, because onefetch writes ordinary SGR escape sequences and
		keeps writing them when its output is piped. This function rewrites that stream: it maps
		the ANSI indices onefetch was told to use onto true-color codes, and swaps the colon for a
		separator of your choosing.

		It is a pure text transform - no binary, no terminal, no configuration lookup - so it is
		testable on a string and safe to put in front of any onefetch invocation, including the
		measuring one (it emits exactly one line per line it is given, so a measured panel keeps
		its height).

		Silence is the point, as with every greeting step. A line that matches nothing passes
		through unchanged, which is also what happens when colors are absent entirely - onefetch
		honors NO_COLOR, and there is no useful behavior beyond leaving such a stream alone.

		The colon is matched structurally - a color, the colon, a reset - rather than against one
		particular color code, so it is found whatever --text-colors was set to.

		Alignment. A separator wider than the ":" it replaces pushes each value right, while
		onefetch's own continuation lines - the second author, the extra churn entries, the
		language chips - are already padded and would be left behind. Those lines are re-padded by
		the difference. Two kinds of line are deliberately not: anything above the first field,
		because the title and its underline are not in the value column at all, and any line
		carrying a background color, which is the color palette row and the language bar. Both
		would only be pushed out of true.

	.PARAMETER Line
		A line of onefetch output. Takes the whole stream from the pipeline.

	.PARAMETER Separator
		Replaces the hardcoded ":" and the single space after it, so " -> " reads exactly like a
		fastfetch separator. $null or empty leaves the colon alone.

	.PARAMETER Colors
		Maps an ANSI index onefetch was told to use onto the SGR parameters to paint it with
		instead, as @{ "12" = "38;2;30;144;255" }. The index is what --text-colors takes (0-15);
		the value is the body of an SGR escape, so a true color is written the same way a
		fastfetch configuration writes one. An index outside 0-15, or an empty replacement, is
		skipped.

	.OUTPUTS
		[string] - one line out per line in.

	.EXAMPLE
		onefetch | Format-OnefetchPanel -Separator " -> "
		The panel with fastfetch's separator in place of the colon.

	.EXAMPLE
		onefetch --text-colors 12 9 9 12 9 15 | Format-OnefetchPanel -Colors @{ "12" = "38;2;30;144;255" }
		Repaints everything onefetch drew in bright blue as exact dodger blue.

	.EXAMPLE
		"$([char]27)[94mProject$([char]27)[0m$([char]27)[91m:$([char]27)[0m x" | Format-OnefetchPanel -Separator " -> "
		Shows the rewrite on a single synthetic line, without running the binary.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param(
		[Parameter(ValueFromPipeline = $true)]
		[AllowNull()]
		[AllowEmptyString()]
		[string]$Line,

		[AllowNull()]
		[AllowEmptyString()]
		[string]$Separator,

		[AllowNull()]
		[hashtable]$Colors
	)

	begin {
		$esc = [char]27

		# Every index onefetch can be given, as the SGR parameter it actually emits: 0-7 are the
		# standard foregrounds, 8-15 the bright ones. Built once, and only for the indices that
		# were asked for, so an unmapped color is not even looked at.
		$palette = @()
		foreach ($key in @(if ($Colors) { $Colors.Keys })) {
			$index = 0
			if (-not [int]::TryParse("$key", [ref]$index) -or $index -lt 0 -or $index -gt 15) {
				Write-LogDebug "[Format-OnefetchPanel] skipped color [$key] => not an ANSI index between 0 and 15"
				continue
			}

			$replacement = "$($Colors[$key])"
			if ([string]::IsNullOrWhiteSpace($replacement)) {
				Write-LogDebug "[Format-OnefetchPanel] skipped color [$key] => no replacement"
				continue
			}

			$sgr = if ($index -lt 8) { 30 + $index } else { 82 + $index }
			$palette += [pscustomobject]@{
				Pattern     = [regex]::Escape("$esc[${sgr}m")
				Replacement = "$esc[${replacement}m"
			}
		}

		# The colon onefetch writes: its color, the character, the reset, and the space that
		# follows - all four are replaced together, so the separator carries its own spacing and
		# keeps the color the "colon" slot of --text-colors gave it.
		$colonPattern = "($esc\[[0-9;]*m):($esc\[0m) "
		$rewriteSeparator = -not [string]::IsNullOrEmpty($Separator)
		$padding = if ($rewriteSeparator) { $Separator.Length - 2 } else { 0 }

		# The separator lands in a -replace replacement string, where "$" introduces a group
		# reference. Doubling it keeps a separator like "$>" literal.
		$separatorLiteral = "$Separator" -replace '\$', '$$$$'

		# A line is only a continuation once a field has been seen; above the first one there is
		# nothing in the value column to keep aligned.
		$seenField = $false

		# Where the info column starts, measured off the first field line and then used to tell a
		# continuation line from a row of the ascii logo. Both sit to the right of nothing and to
		# the left of text, but the logo occupies the columns a continuation leaves blank, so a
		# line only counts as a continuation when everything before this column is whitespace.
		# -1 until the first field line is seen.
		$infoColumn = -1

		# Any background color - the palette row, the language bar - is drawn to a width of its
		# own and must not be shifted.
		$background = "$esc\[(4[0-7]|10[0-7])m"

		$sgr = "$esc\[[0-9;]*m"

		# Insert at a VISIBLE column, counting escape sequences as the zero-width things they are.
		# Padding a continuation line at column 0 would work, but it would also shove the rows of
		# the logo that carry a language chip - so the padding goes in where the info column
		# starts, which leaves whatever is to the left of it exactly where onefetch drew it. A
		# line too short to reach that column has nothing to align and comes back untouched.
		$insertAt = {
			param([string]$Text, [int]$Column, [string]$Pad)

			$visible = 0
			$index = 0
			while ($index -lt $Text.Length -and $visible -lt $Column) {
				if ($Text[$index] -eq $esc) {
					$end = $Text.IndexOf("m", $index)
					if ($end -lt 0) { break }
					$index = $end + 1
					continue
				}
				$index++
				$visible++
			}

			if ($visible -lt $Column) { return $Text }
			return $Text.Substring(0, $index) + $Pad + $Text.Substring($index)
		}
	}

	process {
		$result = $Line

		if ($rewriteSeparator) {
			$rewritten = $result -replace $colonPattern, "`${1}$separatorLiteral`${2}"

			if ($rewritten -ne $result) {
				if (-not $seenField) {
					# Measured once, off the line that first showed where a field name begins. The
					# gap between the logo and the info column is more than one space, while the
					# words inside a field name are separated by exactly one - so the last run of
					# two spaces before the colon is the logo's right edge. With --no-art there is
					# no such run and no logo to protect, and column 0 is the right answer.
					$plain = $rewritten -replace $sgr, ""
					$colon = $plain.IndexOf($Separator)
					$gap = if ($colon -ge 0) { $plain.LastIndexOf("  ", $colon) } else { -1 }
					$infoColumn = if ($gap -lt 0) { 0 } else { $plain.Length - $plain.Substring($gap).TrimStart().Length }
					Write-LogDebug "[Format-OnefetchPanel] info column = $infoColumn"
				}

				$seenField = $true
				$result = $rewritten
			}
			elseif ($seenField -and $padding -gt 0 -and $result -notmatch $background -and $result -match '\S') {
				$result = & $insertAt $result $infoColumn (" " * $padding)
			}
		}

		foreach ($color in $palette) {
			$result = $result -replace $color.Pattern, $color.Replacement
		}

		return $result
	}
}
