function Invoke-PrivacyRequest {
	<#
	.SYNOPSIS
		Makes HTTP requests with optional Tor proxy routing for privacy checks.

	.DESCRIPTION
		Helper function that makes web requests either directly via Invoke-RestMethod
		or through the Tor SOCKS5 proxy using Invoke-TorRequest. Used by Test-PrivacyStatus
		to perform privacy verification checks in both VPN and Tor modes.

	.PARAMETER Uri
		The URI to request.

	.PARAMETER UseTor
		If specified, routes the request through the Tor proxy.

	.PARAMETER TimeoutSec
		Request timeout in seconds. Default is 3.

	.PARAMETER RetryCount
		Number of retry attempts for Tor requests. Default is 1.
	#>
	param(
		[Parameter(Mandatory)]
		[string]$Uri,

		[switch]$UseTor,

		[int]$TimeoutSec = 3,

		[int]$RetryCount = 1
	)

	if ($UseTor) {
		return Invoke-TorRequest -Uri $Uri -TimeoutSec $TimeoutSec -RetryCount $RetryCount
	}
	else {
		return Invoke-RestMethod -Uri $Uri -TimeoutSec $TimeoutSec -ErrorAction Stop
	}
}
