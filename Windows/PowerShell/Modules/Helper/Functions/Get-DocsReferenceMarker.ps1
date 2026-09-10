function Get-DocsReferenceMarker {
	<#
    .SYNOPSIS
        Reads the reference marker a documentation page declares about its own entries.

    .DESCRIPTION
        A page in the fork-owned sovereign docs area (docs/custom) states what its man-style
        "## [Name](url)" entries are, in an HTML comment that renders as nothing in docsify and
        on GitHub:

          <!-- reference: functions windows/Custom -->  entries are functions exported by the
                                                        windows engine's Custom manifest
          <!-- reference: skills -->                    entries are Agent Skills
          <!-- reference: guide -->                     prose page, no entries to check
          <!-- reference: none -->                      same, stated explicitly

        The marker exists because the heading shape alone used to imply "function": a page
        documenting anything else silently claimed a contract it could not keep, and nothing
        noticed until a coherence test broke. Declaring the contract also puts ownership in the
        page rather than in a path or a central configuration list, which is what lets a fork of
        more than one upstream engine take a page from either without the two engines' rules
        colliding, and lets a page keep its contract when it moves between repositories.

        A "functions" marker must carry an "<engine>/<area>" namespace; the other kinds must not
        carry one. An unrecognized kind, a malformed namespace and a missing marker are all
        reported the same way - as $null - so a typo cannot quietly opt a page out of checking.
        The caller decides what an undeclared page means; the Infrastructure coherence test
        treats it as a failure.

    .PARAMETER Path
        The Markdown page to read. A missing file yields $null.

    .EXAMPLE
        Get-DocsReferenceMarker -Path "C:\Repo\docs\custom\application.md"
        Returns @{ Kind = "functions"; Namespace = "windows/Custom" }.

    .EXAMPLE
        (Get-DocsReferenceMarker -Path "C:\Repo\docs\custom\ai.md").Kind
        Returns "skills".
    #>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		[string]$Path
	)

	if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
		return $null
	}

	# Conventionally the first line of the page, but accepted anywhere in it so a page that
	# opens with a title still declares legally. The first well-formed marker wins.
	$pattern = '^\s*<!--\s*reference:\s*(?<Kind>functions|skills|guide|none)(?:\s+(?<Namespace>[A-Za-z0-9._-]+/[A-Za-z0-9._-]+))?\s*-->\s*$'

	foreach ($line in (Get-Content -LiteralPath $Path)) {
		if ($line -notmatch $pattern) { continue }

		$kind = $Matches['Kind'].ToLower()
		$namespace = $Matches['Namespace']

		# "functions" binds to a manifest and is meaningless without one; the other kinds make no
		# function claims and a namespace on them would be a claim nobody reads.
		if ($kind -eq 'functions' -and -not $namespace) { continue }
		if ($kind -ne 'functions' -and $namespace) { continue }

		return @{
			Kind      = $kind
			Namespace = if ($namespace) { $namespace } else { $null }
		}
	}

	return $null
}
