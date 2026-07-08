function Invoke-TorRequest {
	<#
	.SYNOPSIS
		Make HTTP request through Tor for anonymity.

	.DESCRIPTION
		Routes Invoke-RestMethod through Tor SOCKS proxy with automatic port discovery (9150 for Tor Browser, 9050 for Tor service).
		Includes retry logic for connection failures. Used by privacy-focused queries.

	.PARAMETER Uri
		HTTP(S) URL to fetch (required).

	.PARAMETER TimeoutSec
		Request timeout in seconds (default: 15).

	.PARAMETER RetryCount
		Number of retries per port (default: 2).

	.EXAMPLE
		$response = Invoke-TorRequest -Uri "https://api.example.com/data"
		Write-Host "Response: $($response.status)"
	#>
	param(
		[Parameter(Mandatory)]
		[string]$Uri,

		[int]$TimeoutSec = 15,

		[int]$RetryCount = 2
	)

	# Try Tor Browser SOCKS proxy ports (9150 for Tor Browser, 9050 for Tor service)
	$torPorts = @(9150, 9050)

	foreach ($port in $torPorts) {
		$proxy = "socks5://127.0.0.1:$port"

		for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
			try {
				$response = Invoke-RestMethod -Uri $Uri -Proxy $proxy -TimeoutSec $TimeoutSec -ErrorAction Stop
				return $response
			}
			catch [System.Net.WebException] {
				# Connection refused or proxy not available - try next port
				if ($_.Exception.Message -match "Unable to connect|proxy|connection") {
					break  # Skip remaining retries for this port
				}
				# Other network error - retry
				if ($attempt -eq $RetryCount) { continue }
				Start-Sleep -Milliseconds 500
			}
			catch {
				# Other error - retry
				if ($attempt -eq $RetryCount) { continue }
				Start-Sleep -Milliseconds 500
			}
		}
	}

	return $null
}
