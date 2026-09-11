function Invoke-ObsidianCli {
	<#
	.SYNOPSIS
		Runs one Obsidian CLI command. Isolated so tests can observe the exact invocation.
	#>
	[CmdletBinding()]
	[OutputType([object[]])]
	param (
		[Parameter(Mandatory = $true)]
		[string]$CliPath,

		[Parameter(Mandatory = $true)]
		[string[]]$Arguments
	)

	Write-LogDebug " [Open-Obsidian] obsidian $($Arguments -join ' ')" -Style Success

	# Obsidian.com writes its chatter (argv echo, callback URL, update check) straight to the
	# console it is attached to, past any stream redirection - so give it a hidden console of
	# its own and read the answer back from files.
	$stdoutFile = [System.IO.Path]::GetTempFileName()
	$stderrFile = [System.IO.Path]::GetTempFileName()
	try {
		Start-Process -FilePath $CliPath -ArgumentList $Arguments -WindowStyle Hidden -Wait `
			-RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile -ErrorAction Stop
		$output = @(
			foreach ($file in @($stdoutFile, $stderrFile)) {
				if (Test-Path -LiteralPath $file) { Get-Content -LiteralPath $file | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } }
			}
		)
	}
	catch {
		Write-LogDebug " [Open-Obsidian] CLI call failed => $($_.Exception.Message)" -Style Warning
		$output = @("CLI call failed: $($_.Exception.Message)")
	}
	finally {
		Remove-Item -LiteralPath $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
	}

	foreach ($line in $output) { Write-LogDebug " [Open-Obsidian] $line" }
	return $output
}
