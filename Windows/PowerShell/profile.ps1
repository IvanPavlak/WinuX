# | ------------------------------ < All-Hosts Profile (Additive) > ------------------------------ | #
#
# CurrentUserAllHosts profile. PowerShell loads this file BEFORE the host-specific
# Microsoft.PowerShell_profile.ps1, which makes it the one place where per-terminal behavior can be
# prepared without editing the main profile. OPT-IN: nothing links it until you copy the
# PathTemplates.SymbolicLinks.PowerShell.AllHostsProfile example from Configuration.psd1 into your
# Configuration.local.psd1 and run SymbolicLinkMaker.
#
# It carries two additions, both cosmetic, both opt-in, and both inert in the base configuration.
#
# ONE. fastfetch renders the image named by
# Universal.FastFetchImageLogo instead of the text logo declared in the fastfetch configuration, in
# both terminals that can display an image - through the iTerm inline-image protocol in WezTerm, and
# through a pre-encoded sixel in Windows Terminal. The CLI flags override only the logo; every other
# part of the fastfetch configuration still comes from the config file, and the text logo remains
# the fallback for every other host (VS Code, ConHost, SSH, CI). Leaving
# Universal.FastFetchImageLogo unset - the base configuration's state - keeps the text logo
# everywhere, so this file is inert until you opt in twice.
#
# Get-FastfetchLogoArgument (System module) owns the per-terminal decision, the configuration
# lookup and the sixel pipeline - see docs/modules/system.md. The short version of why Windows
# Terminal needs one: fastfetch cannot measure a character cell in pixels on Windows, so its own
# sixel and chafa paths fail to a placeholder, and the image has to be encoded to size beforehand
# and passed through with --logo-type raw.
#
# Mechanism: a global `fastfetch` function. PowerShell resolves functions before external
# applications, so both calls inside Invoke-Fastfetch - the one the profile makes at startup
# through Show-TerminalGreeting, and the one `c` makes - pick up the logo override without either
# of those files changing.
#
# The arguments are resolved on every call, not once here, for two reasons. This file runs before
# any module is imported, so Get-FastfetchLogoArgument is not loadable yet - the function body runs
# later, once the main profile has registered the module roots and loaded the configuration. And the
# sixel has to match the CURRENT font size: Invoke-Fastfetch's auto-fit presses Ctrl+0 /
# Ctrl+Minus between measuring the panel and displaying it, which changes the cell size the image is
# encoded against. Resolution costs one escape round trip plus a cache stat; the encode itself is
# cached per font size.
#
# Invoke-Fastfetch's own panel measuring does NOT come through this function: it invokes the
# fastfetch binary directly, because a captured image payload is one enormous line and would read as
# a 50,000-column panel. That is why the image is fitted into the block the text logo occupies - the
# measured panel and the displayed one then have identical geometry.
#
# The function is only defined in a terminal that can render an image, so in every other host this
# file defines nothing and fastfetch.exe resolves exactly as before. Windows Terminal's auto-fit
# path in Invoke-Fastfetch is untouched either way - it is gated on $env:WT_SESSION.
#
# TWO. onefetch's panel is restyled by TerminalGreeting.Onefetch.Style, through the same mechanism
# and for a related reason: onefetch has no configuration file at all, and two parts of its
# appearance cannot be said on its command line either. --text-colors takes ANSI indices 0-15 and
# rejects everything above, so a true color is unreachable; and the ":" after each field name is
# hardcoded, with no flag that replaces it. Both are reachable afterwards, in the SGR stream
# onefetch writes - which is what Format-OnefetchPanel rewrites. See docs/modules/system.md.
#
# The same terminal guard covers it, for a different reason than the image: this is where a fork
# reaches for a true color, and a true color needs a terminal that renders one.
#
# Wrapping the binary rather than Invoke-Onefetch is deliberate. It means a bare `onefetch` typed
# at the prompt is styled exactly like the one in the greeting, and that Invoke-Onefetch needs no
# knowledge of any of this. Its measuring path is safe to route through: the rewrite emits one
# line per line, so a measured panel keeps the height it will occupy.
#
# $LASTEXITCODE survives the pipeline - Invoke-Onefetch reads it to recognize an empty repository
# with no commits - because a pipeline element after a native command does not reset it.

if (-not ($env:WT_SESSION -or $env:TERM_PROGRAM -eq 'WezTerm')) { return }

try {
	# Resolved once, here, so the wrapper never has to look the binary up again - and so the
	# wrapper is not defined at all on a machine without fastfetch, where `fastfetch` must keep
	# resolving to nothing rather than to a function that shadows a future install.
	$fastfetchApp = Get-Command -Name fastfetch -CommandType Application -ErrorAction SilentlyContinue |
		Select-Object -First 1

	if ($fastfetchApp) {
		$global:WinuXFastfetchExe = $fastfetchApp.Source

		function global:fastfetch {
			$logoArgs = @()

			# A cosmetic override must never break the panel: any failure here falls through to
			# fastfetch's own configuration, which still carries the text logo.
			try {
				$logoArgs = @(Get-FastfetchLogoArgument)
			}
			catch {
				Write-Debug "fastfetch image logo unavailable => $($_.Exception.Message)"
			}

			& $global:WinuXFastfetchExe @logoArgs @args
		}
	}

	$onefetchApp = Get-Command -Name onefetch -CommandType Application -ErrorAction SilentlyContinue |
		Select-Object -First 1

	if ($onefetchApp) {
		$global:WinuXOnefetchExe = $onefetchApp.Source

		function global:onefetch {
			$settings = $null

			# Resolved per call, not once here: this file runs before any module is imported, so
			# neither the configuration nor Format-OnefetchPanel is loadable yet.
			try {
				$settings = (Resolve-TerminalGreetingSettings).Onefetch
			}
			catch {
				Write-Debug "onefetch styling unavailable => $($_.Exception.Message)"
			}

			if (-not $settings -or -not $settings.Style.Enabled) {
				& $global:WinuXOnefetchExe @args
				return
			}

			# A bare `onefetch` gets the configured arguments, the way a bare `fastfetch` gets its
			# configuration file - otherwise the colors Style.Colors remaps are never the ones
			# --text-colors asked for, and typing the command yourself would look nothing like the
			# panel in the greeting. Arguments on the call replace them rather than adding to
			# them, so there is still a way to ask for something else, and Invoke-Onefetch always
			# passes its own - which is why they are never sent twice.
			$onefetchArgs = if ($args.Count -gt 0) { $args } else { $settings.Arguments }

			& $global:WinuXOnefetchExe @onefetchArgs |
				Format-OnefetchPanel -Separator $settings.Style.Separator -Colors $settings.Style.Colors
		}
	}
}
catch {
	# A cosmetic addition must never break shell startup - fall back to plain fastfetch silently.
}
