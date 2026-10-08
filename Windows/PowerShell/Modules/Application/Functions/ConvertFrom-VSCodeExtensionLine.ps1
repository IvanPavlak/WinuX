function ConvertFrom-VSCodeExtensionLine {
	<#
	.SYNOPSIS
		Parses one line of a VS Code profile's extensions.txt into its extension id and optional version pin.

	.DESCRIPTION
		extensions.txt lists one extension per line as `publisher.name`, optionally pinned as
		`publisher.name@1.2.3` (the form `code --install-extension` accepts). A `#` starts a
		comment, on its own line or after an entry; blank lines are allowed. Returns
		@{ Id; Version } for an entry - Version is "" when unpinned - and $null for a blank or
		comment-only line. The id keeps its spelling; callers compare ids case-insensitively,
		as VS Code does.

	.PARAMETER Line
		One line of extensions.txt.

	.EXAMPLE
		ConvertFrom-VSCodeExtensionLine "ms-python.python@2024.2.1  # pinned until the next release"
		Returns @{ Id = "ms-python.python"; Version = "2024.2.1" }.

	.EXAMPLE
		Get-Content extensions.txt | ForEach-Object { ConvertFrom-VSCodeExtensionLine $_ } | Where-Object { $_ }
		Returns every entry of the list.
	#>
	[CmdletBinding()]
	[OutputType([hashtable])]
	param(
		[Parameter(Mandatory, Position = 0, ValueFromPipeline)]
		[AllowEmptyString()]
		[string]$Line
	)

	process {
		$entry = ($Line -split '#', 2)[0].Trim()
		if (-not $entry) {
			return $null
		}

		$parts = $entry -split '@', 2
		$version = if ($parts.Count -gt 1) { $parts[1].Trim() } else { "" }
		return @{ Id = $parts[0].Trim(); Version = $version }
	}
}
