function Get-FastfetchLogoArgument {
	<#
	.SYNOPSIS
		Builds the fastfetch command-line arguments that render an image logo in the current
		terminal, or nothing when the terminal cannot show one.

	.DESCRIPTION
		Opt-in: returns nothing at all until `Universal.FastFetchImageLogo` names an image. With it
		set, the all-hosts profile (`Windows\PowerShell\profile.ps1`, itself an opt-in symbolic
		link) renders that image instead of the text logo declared in the fastfetch configuration,
		in every terminal that can display one.

		The key takes either shape. A STRING is one image for every machine. A HASHTABLE keyed by
		machine type gives each machine its own, and a machine with no entry gets no image - the
		same no-op as leaving the key unset, so adding one machine never turns the feature on for
		the others. Placeholders expand inside the map exactly as they do in a plain string,
		because Expand-Hashtable walks Universal recursively.

		fastfetch cannot render an image logo on Windows on its own. Its
		getCharacterPixelDimensions() calls GetCurrentConsoleFontEx(), which its own source notes
		"only works for ConHost", and the escape-sequence measurement is compiled only on Unix -
		so under Windows Terminal every image logo type that has to SCALE the image (`sixel`,
		`chafa`, `kitty`, `iterm`) fails with "Logo: getCharacterPixelDimensions() failed" and
		degrades to a placeholder block of slashes. The types that PASS THE IMAGE THROUGH for the
		terminal to scale (`iterm`, `kitty-direct`) need no measurement and work fine - but
		Windows Terminal implements neither of those protocols.

		This function resolves that split per terminal:

		  WezTerm          `--logo-type iterm` - the OSC 1337 inline-image protocol. WezTerm
		                   scales the image itself, so nothing is measured, converted or cached.
		  Windows Terminal `--logo-type raw` over a pre-encoded sixel. Windows Terminal renders
		                   sixel (since 1.22) and reports its cell size (since 1.22.2362.0), so
		                   Get-TerminalCellSize supplies the pixel geometry fastfetch cannot get,
		                   New-SixelImage encodes to fit, and `raw` hands the result straight
		                   through without fastfetch measuring anything. This is the workaround
		                   fastfetch's own maintainer recommends for Windows.
		  anything else    nothing, so the text logo in the fastfetch config renders as before.

		The logo occupies a FIXED block of character cells - `-CellWidth` by `-CellHeight` - and
		the image is fitted inside it with its aspect ratio preserved, so the panel has exactly
		the geometry it would have with a text logo of the same dimensions. `-ReferenceLogoPath`
		defaults to the deployed fastfetch text logo (`PathTemplates.SymbolicLinks.FastFetch.Logo`),
		so the block is measured from the very logo the image is replacing and the two are
		interchangeable by construction.

		Redirected output returns nothing on purpose: an image payload is a single enormous line,
		so anything that reads fastfetch's output as TEXT - a shell whose whole stdout is a file or
		a pipe, a CI log - gets the text logo rather than 50KB of sixel.

		That guard does NOT cover Invoke-ClearAndFastfetch's panel measuring, and cannot: when
		PowerShell captures a native command's output it redirects the CHILD process's stdout and
		leaves [Console]::IsOutputRedirected false in the parent, so this function has no way to
		see it. Invoke-ClearAndFastfetch measures with the fastfetch binary directly instead,
		bypassing the wrapper that calls this function - which is also why the image block is
		matched to the text logo's footprint: the measured panel and the displayed one then have
		the same geometry.

		Returns an empty array - never throws - whenever an image logo is not possible. The caller
		splats the result, so an empty array means "run fastfetch exactly as configured". Every
		return is cast to [string[]] so the declared OutputType is actually true - an untyped @() is
		an Object[].

	.PARAMETER ImagePath
		The image to use as the logo. Anything ImageMagick can decode. Omit it and the value comes
		from `Universal.FastFetchImageLogo` - the whole string, or this machine's entry when that
		key is a per-machine hashtable. With neither set there is nothing to render and the
		function returns an empty array.

	.PARAMETER ReferenceLogoPath
		Text logo whose dimensions define the cell block: its line count becomes the height and
		its longest line - fastfetch's `$1`-`$9` color placeholders removed - becomes the width.
		Defaults to the deployed fastfetch text logo from
		`PathTemplates.SymbolicLinks.FastFetch.Logo`. Overrides -CellWidth and -CellHeight when
		the file can be read.

	.PARAMETER CellWidth
		Width of the reserved cell block, used when -ReferenceLogoPath is absent or unreadable.
		Default 36.

	.PARAMETER CellHeight
		Height of the reserved cell block, used when -ReferenceLogoPath is absent or unreadable.
		Default 16.

	.PARAMETER PaddingRight
		Blank columns between the logo block and the module list. Default 4.

	.PARAMETER OutputRedirected
		Whether this process's own output is redirected rather than going to a terminal. Defaults
		to the real console state, which is what production callers want; it is a parameter so the
		per-terminal branches can be tested without a terminal.

	.EXAMPLE
		Get-FastfetchLogoArgument
		Returns the image-logo arguments for the current terminal using the configured image, or
		@() when nothing is configured or the terminal cannot show one.

	.EXAMPLE
		& fastfetch.exe @(Get-FastfetchLogoArgument)
		Renders the configured image logo in the exact cell block the text logo would have
		occupied. This is what the all-hosts profile's `fastfetch` wrapper does.

	.EXAMPLE
		Get-FastfetchLogoArgument -ImagePath "C:\Logos\Flag.png" -CellWidth 30 -CellHeight 15
		Overrides both the image and the cell block, ignoring the configured values.

	.EXAMPLE
		# Universal.FastFetchImageLogo = @{ PC = "...\Blue.png"; Work = "...\Green.png" }
		Get-FastfetchLogoArgument
		Renders Blue.png on the PC machine and Green.png on the Work one; on a Laptop, whose key is
		absent, it returns @() and the text logo stays.
	#>
	[CmdletBinding()]
	[OutputType([string[]])]
	param(
		[Parameter(Position = 0)]
		[string]$ImagePath,

		[string]$ReferenceLogoPath = $global:MachineSpecificPaths.SymbolicLinks.FastFetch.Logo.Path,

		[ValidateRange(1, 500)]
		[int]$CellWidth = 36,

		[ValidateRange(1, 500)]
		[int]$CellHeight = 16,

		[ValidateRange(0, 100)]
		[int]$PaddingRight = 4,

		[bool]$OutputRedirected = $(try { [Console]::IsOutputRedirected } catch { $true })
	)

	# Nothing passed: take it from configuration. One string covers every machine; a hashtable
	# keyed by machine type gives each its own. Indexing is guarded because a Hashtable throws on
	# a null key, and $global:MachineType is only set once Load-PathConfiguration has run.
	if (-not $ImagePath) {
		$configured = $Configuration.Universal.FastFetchImageLogo

		if ($configured -is [Collections.IDictionary]) {
			if ($global:MachineType) {
				$ImagePath = $configured[$global:MachineType]
				Write-LogDebug "[Get-FastfetchLogoArgument] per-machine logo for [$global:MachineType] => [$ImagePath]"
			}
			else {
				Write-LogDebug "[Get-FastfetchLogoArgument] per-machine logo configured but the machine type is unknown - keeping the text logo"
			}
		}
		else {
			$ImagePath = $configured
		}
	}

	# Opt-in: no configured image - or none for THIS machine - means the feature is off, which is
	# the base configuration's state.
	if (-not $ImagePath) {
		Write-LogDebug "[Get-FastfetchLogoArgument] no image configured for this machine - keeping the text logo"
		return [string[]]@()
	}

	if (-not (Test-Path -LiteralPath $ImagePath)) {
		Write-LogDebug "[Get-FastfetchLogoArgument] logo image not found [$ImagePath] - keeping the text logo"
		return [string[]]@()
	}

	# Captured output is measured, not displayed. See the description.
	if ($OutputRedirected) {
		Write-LogDebug "[Get-FastfetchLogoArgument] output redirected - keeping the text logo so the capture stays measurable"
		return [string[]]@()
	}

	# Match the text logo's footprint when one was given, so swapping between them changes nothing
	# about the panel's size. Color placeholders are markup, not glyphs, and must not be counted.
	if ($ReferenceLogoPath -and (Test-Path -LiteralPath $ReferenceLogoPath)) {
		try {
			$lines = @(Get-Content -LiteralPath $ReferenceLogoPath -ErrorAction Stop)
			$widest = ($lines | ForEach-Object { ($_ -replace '\$[0-9]', '').Length } |
				Measure-Object -Maximum).Maximum

			if ($lines.Count -gt 0 -and $widest -gt 0) {
				$CellWidth = [int]$widest
				$CellHeight = $lines.Count
				Write-LogDebug "[Get-FastfetchLogoArgument] cell block [${CellWidth}x${CellHeight}] measured from [$ReferenceLogoPath]"
			}
		}
		catch {
			Write-LogDebug "[Get-FastfetchLogoArgument] could not measure [$ReferenceLogoPath] => $($_.Exception.Message) - using [${CellWidth}x${CellHeight}]"
		}
	}

	# WezTerm scales the image itself, so the pass-through protocol needs no measurement at all.
	# Height follows the aspect ratio; passing it as well would letterbox rather than reserve.
	if ($env:TERM_PROGRAM -eq "WezTerm") {
		Write-LogDebug "[Get-FastfetchLogoArgument] WezTerm - iterm inline image, ${CellWidth} cells wide"
		return [string[]]@(
			"--logo-type", "iterm"
			"--logo", $ImagePath
			"--logo-width", "$CellWidth"
			"--logo-padding-right", "$PaddingRight"
		)
	}

	if (-not $env:WT_SESSION) {
		Write-LogDebug "[Get-FastfetchLogoArgument] terminal has no supported image protocol - keeping the text logo"
		return [string[]]@()
	}

	# Windows Terminal: measure the cell, encode to fit, hand the bytes through untouched. The cell
	# size is re-read on every call rather than cached because it changes with the font size, and
	# Invoke-ClearAndFastfetch's auto-fit presses Ctrl+0 / Ctrl+Minus between the measuring run and
	# the displaying one - a cached size would encode the image for the font it just stopped using.
	$cell = Get-TerminalCellSize
	if (-not $cell) {
		Write-LogDebug "[Get-FastfetchLogoArgument] terminal did not report its cell size - keeping the text logo"
		return [string[]]@()
	}

	$sixel = New-SixelImage -Path $ImagePath `
		-MaxPixelWidth ($CellWidth * $cell.Width) `
		-MaxPixelHeight ($CellHeight * $cell.Height)

	if (-not $sixel) {
		Write-LogDebug "[Get-FastfetchLogoArgument] sixel encoding unavailable - keeping the text logo"
		return [string[]]@()
	}

	Write-LogDebug "[Get-FastfetchLogoArgument] Windows Terminal - raw sixel in a ${CellWidth}x${CellHeight} cell block"
	return [string[]]@(
		"--logo-type", "raw"
		"--logo", $sixel
		"--logo-width", "$CellWidth"
		"--logo-height", "$CellHeight"
		"--logo-padding-right", "$PaddingRight"
	)
}
