function Preview-LoadingSpinners {
	<#
    .SYNOPSIS
        Display all available loading spinner animations from configuration.

    .DESCRIPTION
        Iterates through all spinner styles in Configuration.LoadingSpinners and animates each
        with its configuration frames. Useful for picking preferred loading animation.

    .EXAMPLE
        Preview-LoadingSpinners
    #>
	$spinners = $global:Configuration.LoadingSpinners
	if (-not $spinners) {
		Write-Host -ForegroundColor Red "`n=> Loading spinner configuration not found in global configuration"
		return
	}

	$spinnerNames = $spinners.Keys | Sort-Object
	$spinnerCount = $spinnerNames.Count

	Write-Host -ForegroundColor DarkCyan "`n[Loading Spinners Preview]"

	$indices = @{}
	foreach ($name in $spinnerNames) {
		$indices[$name] = 0
	}

	$bufferHeight = [Console]::BufferHeight
	$neededLines = $spinnerCount * 2

	# Ensure we have enough room by positioning ourselves appropriately in the buffer
	# We need to be far enough from the bottom to fit all spinner lines
	$currentPos = [Console]::CursorTop
	$maxStartLine = $bufferHeight - $neededLines - 1

	# If we're too far down in the buffer, write newlines to scroll content up
	# and position ourselves in a safe zone
	if ($currentPos -gt $maxStartLine) {
		$linesToScroll = $currentPos - $maxStartLine + 1
		for ($i = 0; $i -lt $linesToScroll; $i++) {
			Write-Host ""
		}
	}

	Write-Host ""

	# Capture the start line and ensure it's within safe bounds
	$startLine = [Console]::CursorTop
	$startLine = [Math]::Min($startLine, $maxStartLine)

	# Write blank lines for each spinner (2 lines per spinner for spacing)
	for ($i = 0; $i -lt $neededLines; $i++) {
		Write-Host ""
	}

	$startTime = Get-Date
	$duration = 10  # seconds

	[Console]::CursorVisible = $false

	try {
		while (((Get-Date) - $startTime).TotalSeconds -lt $duration) {
			$lineIndex = 0
			foreach ($name in $spinnerNames) {
				$config = $spinners[$name]
				$symbols = $config.Symbols
				$index = $indices[$name]

				$symbol = $symbols[$index]

				$targetLine = $startLine + $lineIndex

				# Ensure the target line is within buffer bounds
				if ($targetLine -ge 0 -and $targetLine -lt $bufferHeight) {
					[Console]::SetCursorPosition(0, $targetLine)

					$line = "$symbol Displaying [$name] style ..."
					$clearLine = " " * [Math]::Min([Console]::WindowWidth - 1, 100)
					Write-Host -NoNewline "`r$clearLine`r"
					Write-Host -NoNewline $line -ForegroundColor DarkCyan
				}

				$indices[$name] = ($index + 1) % $symbols.Count
				$lineIndex += 2
			}

			Start-Sleep -Milliseconds 100
		}

		$finalLine = $startLine + $neededLines
		if ($finalLine -ge 0 -and $finalLine -lt $bufferHeight) {
			[Console]::SetCursorPosition(0, $finalLine)
		}

	}
 finally {
		[Console]::CursorVisible = $true
	}

	Write-Host -ForegroundColor Green "=> Preview complete!"
}
