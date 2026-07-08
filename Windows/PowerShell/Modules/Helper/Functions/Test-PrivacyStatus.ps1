function Test-PrivacyStatus {
	<#
	.SYNOPSIS
		Performs comprehensive privacy verification for VPN and Tor connections.

	.DESCRIPTION
		Validates VPN adapter status, current IP visibility, Tor routing (if enabled),
		DNS leak detection, and IP geolocation. Reports SECURE status only when all
		required checks pass. Can run silently to only show output when issues are detected.

	.PARAMETER ISPIPAddress
		Your original ISP IP address for comparison. If not provided, it will be retrieved automatically.

	.PARAMETER UseTor
		If specified, enables Tor mode which routes checks through Tor and validates Tor connectivity.

	.PARAMETER Silent
		If specified, only outputs the privacy status report when the status is NOT SECURE.
		Useful for startup checks where you only want to be notified of problems.
	#>
	param(
		[string]$ISPIPAddress,
		[switch]$UseTor,
		[switch]$Silent
	)

	# Constants for speed optimization - 3 second timeout, minimal retries
	$TimeoutSec = 3
	$RetryCount = 1

	$modeLabel = if ($UseTor) { "Tor Mode" } else { "VPN Mode" }

	if (-not $Silent) {
		Write-Host -ForegroundColor DarkCyan "`n[Privacy Verification - $modeLabel]`n"
	}

	# Initialize result hashtable
	$PrivacyCheck = @{
		ISPOriginalIP   = $ISPIPAddress
		CurrentIP       = $null
		VPNDNS          = @()
		DNSInfo         = $null
		IsUsingTor      = $false
		IPHidden        = $false
		DNSSecure       = $false
		GeoLocation     = $null
		VPNConnected    = $false
		VPNAdapter      = $null
		VPNProcess      = $false
		VPNRouting      = $false
		VPNDefaultRoute = $null
		Errors          = @()
	}

	# Get ISP IP if not provided
	if (-not $ISPIPAddress) {
		if (-not $Silent) {
			Write-Host -ForegroundColor DarkCyan " • Retrieving ISP IP =>" -NoNewline
		}
		try {
			$ISPIPAddress = (Invoke-RestMethod -Uri "https://api.ipify.org?format=json" -TimeoutSec $TimeoutSec -ErrorAction Stop).ip
		}
		catch {
			try {
				$ISPIPAddress = (Invoke-RestMethod -Uri "https://ifconfig.me/ip" -TimeoutSec $TimeoutSec -ErrorAction Stop).Trim()
			}
			catch {
				$ISPIPAddress = "Unable to retrieve"
			}
		}
		$PrivacyCheck.ISPOriginalIP = $ISPIPAddress
		if (-not $Silent) {
			Write-Host -ForegroundColor Green " ✓"
		}
	}

	# Check 0: VPN Connection Status (local check - fast)
	if (-not $Silent) {
		Write-Host -ForegroundColor DarkCyan " • Checking VPN connection =>" -NoNewline
	}
	try {
		$vpnProcess = Get-Process -Name "riseup-vpn" -ErrorAction SilentlyContinue
		if ($vpnProcess) {
			$PrivacyCheck.VPNProcess = $true
		}

		$vpnAdapters = Get-NetAdapter | Where-Object {
			$_.Status -eq 'Up' -and (
				$_.InterfaceDescription -match 'TAP-Windows|OpenVPN|WireGuard|VPN|TUN|Tailscale' -or
				$_.Name -match 'VPN|TAP|TUN|Tailscale'
			)
		}

		if ($vpnAdapters) {
			$PrivacyCheck.VPNAdapter = $vpnAdapters[0].Name
			$PrivacyCheck.VPNConnected = $true
			if (-not $Silent) {
				Write-Host -ForegroundColor Green " ✓ $($PrivacyCheck.VPNAdapter)"
			}
		}
		elseif ($PrivacyCheck.VPNProcess) {
			if (-not $Silent) {
				Write-Host -ForegroundColor Yellow " ⚠ Process running, no adapter"
			}
			$PrivacyCheck.Errors += "VPN process running but no active adapter"
		}
		else {
			if (-not $Silent) {
				Write-Host -ForegroundColor Red " ✗ Not connected"
			}
			$PrivacyCheck.Errors += "VPN not connected"
		}
	}
	catch {
		if (-not $Silent) {
			Write-Host -ForegroundColor Red " ✗ Error"
		}
		$PrivacyCheck.Errors += "VPN check failed: $($_.Exception.Message)"
	}

	# Check 0.5: VPN Default Route (verify VPN is routing traffic)
	if ($PrivacyCheck.VPNConnected -and $PrivacyCheck.VPNAdapter) {
		if (-not $Silent) {
			Write-Host -ForegroundColor DarkCyan " • Checking VPN routing =>" -NoNewline
		}
		try {
			$vpnIfIndex = $vpnAdapters[0].ifIndex
			$vpnAdapterName = $PrivacyCheck.VPNAdapter

			# Check OpenVPN-style split routes (0.0.0.0/1 + 128.0.0.0/1)
			# OpenVPN creates two half-space routes instead of a 0.0.0.0/0 default route
			# These are more specific than the default route and capture all traffic
			$splitRouteA = Get-NetRoute -DestinationPrefix '0.0.0.0/1' -ErrorAction SilentlyContinue |
				Where-Object { $_.InterfaceIndex -eq $vpnIfIndex }
			$splitRouteB = Get-NetRoute -DestinationPrefix '128.0.0.0/1' -ErrorAction SilentlyContinue |
				Where-Object { $_.InterfaceIndex -eq $vpnIfIndex }

			if ($splitRouteA -and $splitRouteB) {
				# OpenVPN split routing detected - all traffic goes through VPN
				$PrivacyCheck.VPNRouting = $true
				$PrivacyCheck.VPNDefaultRoute = "Split routes via $vpnAdapterName (0.0.0.0/1 + 128.0.0.0/1)"
				if (-not $Silent) {
					Write-Host -ForegroundColor Green " ✓ Split routing via $vpnAdapterName"
				}
			}
			else {
				# Fallback: Check standard default routes (0.0.0.0/0)
				$defaultRoutes = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
					Sort-Object RouteMetric

				if ($defaultRoutes) {
					$topRoute = $defaultRoutes[0]

					# Check if the VPN adapter has the highest-priority (lowest metric) default route
					if ($topRoute.InterfaceIndex -eq $vpnIfIndex) {
						$PrivacyCheck.VPNRouting = $true
						$PrivacyCheck.VPNDefaultRoute = "$($topRoute.NextHop) via $vpnAdapterName (metric $($topRoute.RouteMetric))"
						if (-not $Silent) {
							Write-Host -ForegroundColor Green " ✓ Default route via $vpnAdapterName"
						}
					}
					else {
						# Check if VPN adapter appears in any default route
						$vpnRoute = $defaultRoutes | Where-Object { $_.InterfaceIndex -eq $vpnIfIndex }
						if ($vpnRoute) {
							$PrivacyCheck.VPNDefaultRoute = "$($vpnRoute.NextHop) via $vpnAdapterName (metric $($vpnRoute.RouteMetric))"
							if (-not $Silent) {
								Write-Host -ForegroundColor Yellow " ⚠ Not primary route (metric $($vpnRoute.RouteMetric) > $($topRoute.RouteMetric))"
							}
							$PrivacyCheck.Errors += "VPN adapter has default route but not highest priority"
						}
						else {
							if (-not $Silent) {
								Write-Host -ForegroundColor Red " ✗ No default route through VPN"
							}
							$PrivacyCheck.Errors += "VPN connected but not routing traffic (no default route)"
						}
					}
				}
				else {
					if (-not $Silent) {
						Write-Host -ForegroundColor Yellow " ⚠ No default routes found"
					}
				}
			}
		}
		catch {
			if (-not $Silent) {
				Write-Host -ForegroundColor Yellow " ⚠ Could not check"
			}
		}
	}

	# Check 1: Current Public IP
	if (-not $Silent) {
		Write-Host -ForegroundColor DarkCyan " • Checking current IP =>" -NoNewline
	}
	$ipServices = @(
		@{ Uri = "https://api.ipify.org?format=json"; Field = "ip" },
		@{ Uri = "https://api.myip.com"; Field = "ip" }
	)
	foreach ($service in $ipServices) {
		try {
			$ipCheck = Invoke-PrivacyRequest -Uri $service.Uri -UseTor:$UseTor -TimeoutSec $TimeoutSec -RetryCount $RetryCount
			if ($ipCheck) {
				$PrivacyCheck.CurrentIP = $ipCheck.($service.Field)
				if ($PrivacyCheck.CurrentIP) { break }
			}
		}
		catch { continue }
	}

	if ($PrivacyCheck.CurrentIP) {
		if ($PrivacyCheck.CurrentIP -eq $ISPIPAddress) {
			if ($PrivacyCheck.VPNRouting) {
				# VPN is routing traffic but exit node has same public IP as ISP
				if (-not $Silent) {
					Write-Host -ForegroundColor Yellow " ⚠ Same as ISP (exit node shares IP)"
				}
			}
			else {
				if (-not $Silent) {
					Write-Host -ForegroundColor Red " ✗ Matches ISP IP!"
				}
				$PrivacyCheck.Errors += "IP not hidden - matches ISP IP"
			}
		}
		else {
			if (-not $Silent) {
				Write-Host -ForegroundColor Green " ✓ $($PrivacyCheck.CurrentIP)"
			}
			$PrivacyCheck.IPHidden = $true
		}
	}
	else {
		if (-not $Silent) {
			Write-Host -ForegroundColor Yellow " ⚠ Timeout"
		}
		$PrivacyCheck.Errors += "Could not verify current IP"
	}

	# Check 2: Tor Status (only if UseTor mode)
	if ($UseTor) {
		if (-not $Silent) {
			Write-Host -ForegroundColor DarkCyan " • Checking Tor status =>" -NoNewline
		}
		try {
			$torStatus = Invoke-PrivacyRequest -Uri "https://check.torproject.org/api/ip" -UseTor:$UseTor -TimeoutSec $TimeoutSec -RetryCount $RetryCount
			if ($torStatus -and $torStatus.IsTor) {
				$PrivacyCheck.IsUsingTor = $true
				if (-not $Silent) {
					Write-Host -ForegroundColor Green " ✓ Active"
				}
			}
			else {
				if (-not $Silent) {
					Write-Host -ForegroundColor Yellow " ✗ Not detected"
				}
				$PrivacyCheck.Errors += "Tor not active"
			}
		}
		catch {
			if (-not $Silent) {
				Write-Host -ForegroundColor Yellow " ✗ Timeout"
			}
			$PrivacyCheck.Errors += "Tor not active"
		}
	}

	# Check 3: DNS Leak Detection
	if (-not $Silent) {
		Write-Host -ForegroundColor DarkCyan " • Checking DNS security =>" -NoNewline
	}
	try {
		$dnsResolver = Invoke-PrivacyRequest -Uri "https://edns.ip-api.com/json" -UseTor:$UseTor -TimeoutSec $TimeoutSec -RetryCount $RetryCount
		if ($dnsResolver -and $dnsResolver.dns) {
			$PrivacyCheck.VPNDNS = @($dnsResolver.dns.ip)
			$PrivacyCheck.DNSInfo = $dnsResolver.dns

			if ($PrivacyCheck.VPNDNS -contains $ISPIPAddress) {
				if (-not $Silent) {
					Write-Host -ForegroundColor Red " ✗ LEAK DETECTED!"
				}
				$PrivacyCheck.Errors += "DNS leak detected"
			}
			else {
				if (-not $Silent) {
					Write-Host -ForegroundColor Green " ✓ $($PrivacyCheck.VPNDNS -join ', ')"
				}
				$PrivacyCheck.DNSSecure = $true
			}
		}
		else {
			if (-not $Silent) {
				Write-Host -ForegroundColor Yellow " ⚠ Timeout"
			}
			$PrivacyCheck.Errors += "DNS verification service unavailable"
		}
	}
	catch {
		if (-not $Silent) {
			Write-Host -ForegroundColor Yellow " ⚠ Timeout"
		}
		$PrivacyCheck.Errors += "DNS verification service unavailable"
	}

	# Check 4: GeoIP Location
	if (-not $Silent) {
		Write-Host -ForegroundColor DarkCyan " • Checking IP geolocation =>" -NoNewline
	}
	$geoServices = @(
		@{ Uri = "https://ipwho.is/"; City = "city"; Country = "country"; Org = "connection.isp" },
		@{ Uri = "https://ipapi.co/json/"; City = "city"; Country = "country_name"; Org = "org" }
	)
	foreach ($geoService in $geoServices) {
		try {
			$geoCheck = Invoke-PrivacyRequest -Uri $geoService.Uri -UseTor:$UseTor -TimeoutSec $TimeoutSec -RetryCount $RetryCount
			if ($geoCheck -and ($geoCheck.city -or $geoCheck.country)) {
				$orgValue = if ($geoService.Org -match '\.') {
					$parts = $geoService.Org -split '\.'
					$geoCheck.($parts[0]).($parts[1])
				}
				elseif ($geoService.Org) { $geoCheck.($geoService.Org) }
				else { "Unknown" }

				$PrivacyCheck.GeoLocation = [PSCustomObject]@{
					city         = $geoCheck.($geoService.City)
					country_name = $geoCheck.($geoService.Country)
					org          = $orgValue
				}
				break
			}
		}
		catch { continue }
	}

	if ($PrivacyCheck.GeoLocation) {
		if (-not $Silent) {
			Write-Host -ForegroundColor Green " ✓ $($PrivacyCheck.GeoLocation.city), $($PrivacyCheck.GeoLocation.country_name)"
		}
	}
	else {
		if (-not $Silent) {
			Write-Host -ForegroundColor Yellow " ⚠ Skipped"
		}
	}

	# Generate Privacy Status Report data
	$geoLocation = if ($PrivacyCheck.GeoLocation) {
		"$($PrivacyCheck.GeoLocation.city), $($PrivacyCheck.GeoLocation.country_name)"
	}
	else {
		"Not verified"
	}

	$geoISP = if ($PrivacyCheck.GeoLocation) {
		$PrivacyCheck.GeoLocation.org
	}
	else {
		"Not verified"
	}

	$dnsGeo = if ($PrivacyCheck.DNSInfo -and $PrivacyCheck.DNSInfo.geo) {
		$PrivacyCheck.DNSInfo.geo
	}
	else {
		"Not verified"
	}

	# Core security checks (geolocation is informational only)
	# For Tor mode: require VPN + Tor + IP hidden + DNS secure
	# For VPN mode: require VPN + (IP hidden OR VPN routing) + DNS secure
	# When VPN is routing but IP matches ISP (exit node shares IP), traffic IS secured
	$ipProtected = $PrivacyCheck.IPHidden -or $PrivacyCheck.VPNRouting
	$isSecure = if ($UseTor) {
		$PrivacyCheck.Errors.Count -eq 0 -and
		$PrivacyCheck.VPNConnected -and
		$PrivacyCheck.IsUsingTor -and
		$PrivacyCheck.IPHidden -and
		$PrivacyCheck.DNSSecure
	}
	else {
		$PrivacyCheck.Errors.Count -eq 0 -and
		$PrivacyCheck.VPNConnected -and
		$ipProtected -and
		$PrivacyCheck.DNSSecure
	}

	# In Silent mode, only show output if not secure
	if ($Silent -and $isSecure) {
		return
	}

	# Display Status Summary with color-coded results
	Write-Host -ForegroundColor DarkCyan "`n [Privacy Status Report]"

	Write-Host -ForegroundColor DarkCyan "  ├─ VPN Connected => " -NoNewline
	if ($PrivacyCheck.VPNConnected) {
		Write-Host -ForegroundColor Green "✓ YES"
	}
	else {
		Write-Host -ForegroundColor Red "✗ NO"
	}

	if ($PrivacyCheck.VPNAdapter) {
		Write-Host -ForegroundColor DarkCyan "  ├─ VPN Adapter => " -NoNewline
		Write-Host -ForegroundColor Green "$($PrivacyCheck.VPNAdapter)"
	}

	Write-Host -ForegroundColor DarkCyan "  ├─ VPN Routing => " -NoNewline
	if ($PrivacyCheck.VPNRouting) {
		Write-Host -ForegroundColor Green "✓ YES ($($PrivacyCheck.VPNDefaultRoute))"
	}
	elseif ($PrivacyCheck.VPNDefaultRoute) {
		Write-Host -ForegroundColor Yellow "⚠ $($PrivacyCheck.VPNDefaultRoute)"
	}
	elseif ($PrivacyCheck.VPNConnected) {
		Write-Host -ForegroundColor Red "✗ NO (no default route through VPN)"
	}
	else {
		Write-Host -ForegroundColor Yellow "N/A"
	}

	Write-Host -ForegroundColor DarkCyan "  ├─ Original ISP IP => " -NoNewline
	Write-Host -ForegroundColor White "$($PrivacyCheck.ISPOriginalIP)"

	if ($PrivacyCheck.CurrentIP) {
		Write-Host -ForegroundColor DarkCyan "  ├─ Current IP => " -NoNewline
		Write-Host -ForegroundColor Green "$($PrivacyCheck.CurrentIP)"
	}
	else {
		Write-Host -ForegroundColor DarkCyan "  ├─ Current IP => " -NoNewline
		Write-Host -ForegroundColor Yellow "Not verified"
	}

	Write-Host -ForegroundColor DarkCyan "  ├─ IPs Match => " -NoNewline
	if (-not $PrivacyCheck.CurrentIP) {
		Write-Host -ForegroundColor Yellow "Not verified"
	}
	elseif ($PrivacyCheck.ISPOriginalIP -eq $PrivacyCheck.CurrentIP) {
		if ($PrivacyCheck.VPNRouting) {
			Write-Host -ForegroundColor Yellow "⚠ YES (exit node shares ISP IP)"
		}
		else {
			Write-Host -ForegroundColor Red "⚠ YES (BAD)"
		}
	}
	else {
		Write-Host -ForegroundColor Green "✓ NO (GOOD)"
	}

	if ($UseTor) {
		Write-Host -ForegroundColor DarkCyan "  ├─ Using Tor => " -NoNewline
		if ($PrivacyCheck.IsUsingTor) {
			Write-Host -ForegroundColor Green "✓ YES"
		}
		else {
			Write-Host -ForegroundColor Red "✗ NO"
		}
	}

	Write-Host -ForegroundColor DarkCyan "  ├─ IP Hidden => " -NoNewline
	if ($PrivacyCheck.IPHidden) {
		Write-Host -ForegroundColor Green "✓ YES"
	}
	elseif ($PrivacyCheck.VPNRouting -and -not $PrivacyCheck.IPHidden) {
		Write-Host -ForegroundColor Yellow "⚠ NO (traffic routed via VPN, exit node shares IP)"
	}
	else {
		Write-Host -ForegroundColor Red "✗ NO"
	}

	Write-Host -ForegroundColor DarkCyan "  ├─ DNS Secure => " -NoNewline
	if ($PrivacyCheck.DNSSecure) {
		Write-Host -ForegroundColor Green "✓ YES"
	}
	else {
		Write-Host -ForegroundColor Yellow "⚠ CHECK REQUIRED"
	}

	Write-Host -ForegroundColor DarkCyan "  ├─ DNS Servers => " -NoNewline
	if ($PrivacyCheck.VPNDNS.Count -gt 0) {
		Write-Host -ForegroundColor Green "$($PrivacyCheck.VPNDNS -join ', ')"
	}
	else {
		Write-Host -ForegroundColor Yellow "Not verified"
	}

	Write-Host -ForegroundColor DarkCyan "  ├─ DNS Geo => " -NoNewline
	if ($dnsGeo -ne "Not verified") {
		Write-Host -ForegroundColor Green "$dnsGeo"
	}
	else {
		Write-Host -ForegroundColor Yellow "$dnsGeo"
	}

	Write-Host -ForegroundColor DarkCyan "  ├─ Exit Location => " -NoNewline
	if ($geoLocation -ne "Not verified") {
		Write-Host -ForegroundColor Green "$geoLocation"
	}
	else {
		Write-Host -ForegroundColor Yellow "$geoLocation"
	}

	Write-Host -ForegroundColor DarkCyan "  └─ Exit ISP => " -NoNewline
	if ($geoISP -ne "Not verified") {
		Write-Host -ForegroundColor Green "$geoISP"
	}
	else {
		Write-Host -ForegroundColor Yellow "$geoISP"
	}

	Write-Host -ForegroundColor DarkCyan "`n[Overall Privacy Status] =>" -NoNewline

	if ($isSecure) {
		Write-Host -ForegroundColor Green " [SECURE]"
		Write-LogSuccess "  ✓ All security checks passed!"
		if ($PrivacyCheck.VPNRouting -and -not $PrivacyCheck.IPHidden) {
			Write-Host -ForegroundColor Yellow "  ⓘ VPN is routing all traffic, but exit node shares your ISP IP"
			Write-Host -ForegroundColor Yellow "  ⓘ To hide your IP, use an exit node on a different network"
		}
		if (-not $PrivacyCheck.GeoLocation) {
			Write-Host -ForegroundColor Yellow "  ⓘ Geolocation unavailable (informational only)"
		}
	}
	else {
		Write-Host -ForegroundColor Red " [NOT SECURE]`n"

		if ($PrivacyCheck.Errors.Count -gt 0) {
			$PrivacyCheck.Errors | ForEach-Object { Write-Host -ForegroundColor Red "  => $_" }
		}

		# Provide specific guidance for failed checks
		if (-not $PrivacyCheck.VPNConnected) {
			Write-Host -ForegroundColor Red "  => VPN is not connected - connect your VPN first"
		}
		if ($UseTor -and -not $PrivacyCheck.IsUsingTor) {
			Write-Host -ForegroundColor Red "  => Tor is not active - ensure Tor Browser is running"
		}
		if (-not $PrivacyCheck.IPHidden -and -not $PrivacyCheck.VPNRouting) {
			Write-Host -ForegroundColor Red "  => IP not hidden - verify VPN is routing traffic"
		}
		if (-not $PrivacyCheck.DNSSecure) {
			Write-Host -ForegroundColor Red "  => DNS may be leaking - check DNS configuration"
		}
	}
}
