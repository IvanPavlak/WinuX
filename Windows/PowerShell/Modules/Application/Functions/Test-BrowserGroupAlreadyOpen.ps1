function Test-BrowserGroupAlreadyOpen {
	<#
	.SYNOPSIS
		Checks whether a browser URL group is already open by matching window titles.

	.DESCRIPTION
		Used internally by Open-Browser for idempotency checks. Inspects window titles of
		running browser processes and matches them against keywords extracted from the provided
		URLs. Keyword extraction rules (localhost patterns, domain simplification) are read
		from the `BrowserGroupMatching` section of Configuration.psd1.

		With `-ReturnCount`, returns the number of matching windows instead of a boolean.

	.PARAMETER Urls
		Array of URL strings to check. Keywords are extracted from these URLs for matching.

	.PARAMETER Browser
		Browser name used to determine which process names to inspect.

	.PARAMETER GroupDisplayName
		Human-readable group name shown in debug output.

	.PARAMETER CachedBrowserWindows
		Pre-fetched window handle list. When provided, skips the window enumeration call
		for performance (Open-Browser caches windows once for all groups).

	.PARAMETER ReturnCount
		Returns an integer count of matching windows instead of a boolean.

	.EXAMPLE
		Test-BrowserGroupAlreadyOpen -Urls @("https://github.com") -Browser "Firefox" -GroupDisplayName "GitHub"
		Returns `$true` if a Firefox window with "github" in its title is open.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		[string[]]$Urls,

		[Parameter(Mandatory)]
		[string]$Browser,

		[Parameter(Mandatory)]
		[string]$GroupDisplayName,

		[Parameter()]
		[array]$CachedBrowserWindows,

		[Parameter()]
		[switch]$ReturnCount
	)

	Write-LogDebug "[Test-BrowserGroupAlreadyOpen$(if ($ReturnCount) { ' - ReturnCount mode' })]"

	try {
		if (Test-LogVerbose) {

			Write-LogDebug "Checking if group [$GroupDisplayName] is already open..."
			Write-LogDebug "Browser => $Browser"
			Write-LogDebug "URLs to check ($($Urls.Count)) =>" -Style Step
			foreach ($url in $Urls) {
				Write-LogDebug "- $url" -Style Step
			}
		}

		$browserGroupMatchingConfig = $Configuration.BrowserGroupMatching
		if (-not $browserGroupMatchingConfig) {
			Write-LogError "Error: BrowserGroupMatching configuration not found!"
			return $false
		}

		$browserProcessNames = $browserGroupMatchingConfig.BrowserProcessNames
		$keywordExtractionConfig = $browserGroupMatchingConfig.KeywordExtraction
		$exactTitleConfig = $browserGroupMatchingConfig.ExactTitle
		$negativeMatchingConfig = $browserGroupMatchingConfig.NegativeMatching
		$matchingConfig = $browserGroupMatchingConfig.Matching

		$localhostHosts = @($keywordExtractionConfig.LocalhostHosts)
		$genericWords = @($keywordExtractionConfig.GenericWords)
		$genericSubdomains = @($keywordExtractionConfig.GenericSubdomains)
		$ignoredPathSegments = @($keywordExtractionConfig.IgnoredPathSegments)
		$specialKeywords = $keywordExtractionConfig.SpecialHostKeywords
		$homepageIndicatorSubdomains = @($exactTitleConfig.HomepageIndicatorSubdomains)
		$simpleHomepagePaths = @($exactTitleConfig.SimpleHomepagePaths)
		$browserTitleSuffixPatterns = @($exactTitleConfig.BrowserTitleSuffixPatterns)
		$knownServiceSubdomains = $negativeMatchingConfig.KnownServiceSubdomains
		$problemLoadingPagePattern = $matchingConfig.ProblemLoadingPagePattern
		$minKeywordLength = [int]$keywordExtractionConfig.MinimumKeywordLength
		$minimumAcceptedScore = [int]$matchingConfig.MinimumAcceptedScore
		$wordBoundaryScoreMultiplier = [int]$matchingConfig.WordBoundaryScoreMultiplier
		$slugScoreMultiplier = [int]$matchingConfig.SlugScoreMultiplier
		$highConfidencePrimaryKeywordLength = [int]$matchingConfig.HighConfidencePrimaryKeywordLength
		$multiUrlSecondaryOnlyThreshold = [int]$matchingConfig.MultiUrlSecondaryOnlyThreshold

		$processName = if ($browserProcessNames.ContainsKey($Browser)) {
			$browserProcessNames[$Browser]
		}
		else {
			$Browser.ToLower()
		}

		Write-LogDebug " Process name to search => [$processName]" -Style Step

		# Use cached windows if provided, otherwise fetch fresh
		if ($CachedBrowserWindows) {
			$browserWindows = $CachedBrowserWindows
			Write-LogDebug "=> Using $($browserWindows.Count) cached browser window(s)!" -Style Success
		}
		else {
			$browserWindows = Get-WindowHandle -ProcessName $processName -ErrorAction SilentlyContinue
		}

		if (-not $browserWindows) {
			Write-LogDebug " No browser windows found!" -Style Warning
			return $false
		}

		if ($browserWindows -is [array]) {
			if ((Test-LogVerbose) -and -not $CachedBrowserWindows) {
				Write-LogDebug "Found $($browserWindows.Count) browser window(s)!" -Style Success
			}
		}
		else {
			if ((Test-LogVerbose) -and -not $CachedBrowserWindows) {
				Write-LogDebug "Found 1 browser window!" -Style Success
			}
			$browserWindows = @($browserWindows)
		}

		if (Test-LogVerbose) {
			foreach ($window in $browserWindows) {
				Write-LogDebug "Window => [$($window.Title)]"
			}
		}

		# Detect if we're checking for a "main" homepage (e.g., google.com vs gemini.google.com)
		$isMainHomepage = $false
		$mainDomain = $null
		$urlSubdomains = @()

		foreach ($url in $Urls) {
			try {
				$uri = [System.Uri]$url
				$hostParts = $uri.Host -split '\.'
				$hostLower = $uri.Host.ToLower()
				$firstHostPartLower = if ($hostParts.Count -gt 0) { $hostParts[0].ToLower() } else { $null }
				if ($hostParts.Count -ge 2) {
					$domain = $hostParts[-2].ToLower()
					$mainDomain = $domain

					# Check if this is a main homepage (www.google.com or google.com with minimal path)
					$pathTrimmed = $uri.AbsolutePath.Trim('/')
					$isSimplePath = $simpleHomepagePaths -contains $pathTrimmed
					$isWwwOrNaked = ($homepageIndicatorSubdomains -contains $firstHostPartLower) -or ($hostParts.Count -eq 2)

					if ($isWwwOrNaked -and $isSimplePath -and $knownServiceSubdomains.ContainsKey($domain)) {
						$isMainHomepage = $true
					}

					# Track subdomains from our URLs (to allow those services)
					if ($hostParts.Count -gt 2 -and $homepageIndicatorSubdomains -notcontains $firstHostPartLower) {
						$urlSubdomains += $firstHostPartLower
					}
				}
			}
			catch {
				# Skip invalid URLs
			}
		}

		if ((Test-LogVerbose) -and $isMainHomepage) {
			Write-LogDebug "Detected main homepage check for domain: [$mainDomain]"
			Write-LogDebug "Will use negative matching to exclude other [$mainDomain] services"
		}

		# Extract multiple keywords per URL for more robust matching
		$allKeywords = @()
		$useExactTitleMatch = $false

		foreach ($url in $Urls) {
			try {
				$uri = [System.Uri]$url
				$urlKeywords = @()

				# 1. Extract domain keyword (e.g., "youtube" from "www.youtube.com")
				$hostParts = $uri.Host -split '\.'
				$hostLower = $uri.Host.ToLower()
				$firstHostPartLower = if ($hostParts.Count -gt 0) { $hostParts[0].ToLower() } else { $null }
				$domainKeyword = $null
				$hasMeaningfulSubdomain = ($hostParts.Count -gt 2 -and $genericSubdomains -notcontains $firstHostPartLower)
				if ($localhostHosts -contains $hostLower) {
					$domainKeyword = "localhost"
				}
				elseif ($hostParts.Count -ge 2) {
					# Get main domain name (e.g., "youtube" from "www.youtube.com" or "google" from "gemini.google.com")
					$domainKeyword = $hostParts[-2]
				}
				else {
					$domainKeyword = $uri.Host
				}

				# Add domain keyword if it meets criteria
				# Domain is Secondary when URL has a meaningful subdomain (e.g., "google" from "gemini.google.com")
				if ($domainKeyword -and
					$domainKeyword.Length -ge $minKeywordLength -and
					$genericWords -notcontains $domainKeyword.ToLower()) {
					$domainTier = if ($hasMeaningfulSubdomain) { 'Secondary' } else { 'Primary' }
					$urlKeywords += @{ Word = $domainKeyword; Tier = $domainTier }
				}

				# 2. Extract subdomain keyword if meaningful (e.g., "gemini" from "gemini.google.com")
				if ($hostParts.Count -gt 2) {
					$subdomain = $hostParts[0]
					if ($homepageIndicatorSubdomains -notcontains $subdomain.ToLower() -and
						$subdomain.Length -ge $minKeywordLength -and
						$genericWords -notcontains $subdomain.ToLower()) {
						$urlKeywords += @{ Word = $subdomain; Tier = 'Primary' }
					}
				}

				# Special handling for common patterns:
				# - AI tools: "chat", "claude", "gemini", "perplexity", "chatgpt"
				# - Add specific well-known identifiers
				if ($specialKeywords.ContainsKey($hostLower)) {
					foreach ($sw in $specialKeywords[$hostLower]) {
						$urlKeywords += @{ Word = $sw; Tier = 'Primary' }
					}
				}

				# 3. Extract path keywords
				$pathParts = $uri.AbsolutePath.Trim('/').Split('/') | Where-Object {
					-not [string]::IsNullOrWhiteSpace($_) -and $ignoredPathSegments -notcontains $_.ToLower()
				}

				foreach ($part in $pathParts) {
					# Handle special cases like "spell:minor-illusion"
					if ($part -match ':(.+)$') {
						$pathKeyword = $matches[1]
					}
					else {
						$pathKeyword = $part
					}

					# Split on underscores and dashes to get individual words
					$words = $pathKeyword -split '[_\-]' | Where-Object {
						-not [string]::IsNullOrWhiteSpace($_)
					}

					foreach ($word in $words) {
						if ($word.Length -ge $minKeywordLength -and
							$genericWords -notcontains $word.ToLower()) {
							$urlKeywords += @{ Word = $word; Tier = 'Primary' }
						}
					}

					# Also add the full path part if it's long enough
					if ($pathKeyword.Length -ge $minKeywordLength -and
						$genericWords -notcontains $pathKeyword.ToLower()) {
						$urlKeywords += @{ Word = $pathKeyword; Tier = 'Primary' }
					}
				}

				# 4. Extract fragment keywords for SPA-style routes (e.g. #inbox)
				$fragmentParts = $uri.Fragment.TrimStart('#').Split('/') | Where-Object {
					-not [string]::IsNullOrWhiteSpace($_)
				}

				foreach ($fragmentPart in $fragmentParts) {
					$fragmentWords = $fragmentPart -split '[_\-]' | Where-Object {
						-not [string]::IsNullOrWhiteSpace($_)
					}

					foreach ($word in $fragmentWords) {
						if ($word.Length -ge $minKeywordLength -and
							$genericWords -notcontains $word.ToLower()) {
							$urlKeywords += @{ Word = $word; Tier = 'Primary' }
						}
					}

					if ($fragmentPart.Length -ge $minKeywordLength -and
						$genericWords -notcontains $fragmentPart.ToLower()) {
						$urlKeywords += @{ Word = $fragmentPart; Tier = 'Primary' }
					}
				}

				# 5. Special handling for port numbers (for localhost URLs)
				if ($localhostHosts -contains $hostLower -and -not $uri.IsDefaultPort) {
					# Add port as a keyword for localhost URLs
					$urlKeywords += @{ Word = $uri.Port.ToString(); Tier = 'Primary' }
				}

				# Add all extracted keywords for this URL
				if ($urlKeywords.Count -gt 0) {
					$allKeywords += $urlKeywords
				}
				else {
					# For main homepages of known service providers, use exact title matching
					# instead of generic keyword matching (to avoid false positives)
					if ($isMainHomepage) {
						$useExactTitleMatch = $true
						# Use the GroupDisplayName as the primary keyword for exact matching
						$allKeywords += @{ Word = $GroupDisplayName; Tier = 'Primary' }
						if (Test-LogVerbose) {
							Write-LogDebug "Using exact title match mode with GroupDisplayName: [$GroupDisplayName]"
						}
					}
					elseif ($domainKeyword) {
						# Fallback: if no keywords extracted, use domain even if short
						$allKeywords += @{ Word = $domainKeyword; Tier = 'Primary' }
					}
				}
			}
			catch {
				# If not a valid URL, skip it
				if (Test-LogVerbose) {
					Write-LogDebug "Failed to parse URL: $url" -Style Warning
				}
			}
		}

		# Remove duplicates by word and sort by length (longer = more specific)
		# When a keyword appears as both Primary and Secondary, keep Primary (higher confidence)
		$keywordMap = [ordered]@{}
		foreach ($kw in $allKeywords) {
			$wordLower = $kw.Word.ToLower()
			if (-not $keywordMap.Contains($wordLower)) {
				$keywordMap[$wordLower] = $kw
			}
			elseif ($kw.Tier -eq 'Primary' -and $keywordMap[$wordLower].Tier -eq 'Secondary') {
				$keywordMap[$wordLower] = $kw
			}
		}
		$keywords = @($keywordMap.Values | Sort-Object -Property { $_.Word.Length } -Descending)

		# Collect primary keywords for reverse-check validation
		$primaryKeywords = @($keywords | Where-Object { $_.Tier -eq 'Primary' } | ForEach-Object { $_.Word })

		if (Test-LogVerbose) {
			Write-LogDebug "Extracted keywords ($($keywords.Count)):" -Style Step
			foreach ($keyword in $keywords) {
				$tierLabel = if ($keyword.Tier -eq 'Primary') { 'P' } else { 'S' }
				Write-LogDebug "- $($keyword.Word) [$tierLabel]" -Style Step
			}
		}

		# Check if any URLs are localhost URLs (for special handling of failed loads)
		$hasLocalhostUrls = $Urls | Where-Object {
			try {
				$uri = [System.Uri]$_
				$localhostHosts -contains $uri.Host.ToLower()
			}
			catch {
				$false
			}
		}

		# Build list of service words to exclude (for negative matching)
		$excludeServiceWords = @()
		if ($isMainHomepage -and $mainDomain -and $knownServiceSubdomains.ContainsKey($mainDomain)) {
			# Get all known services for this domain, except ones we're explicitly checking for
			$excludeServiceWords = $knownServiceSubdomains[$mainDomain] | Where-Object {
				$urlSubdomains -notcontains $_
			}
			if ((Test-LogVerbose) -and $excludeServiceWords.Count -gt 0) {
				Write-LogDebug "Excluding service words: [$($excludeServiceWords -join ', ')]"
			}
		}

		# Check if any browser window title contains any of our keywords
		$foundProblemLoadingPage = $false
		$bestMatchScore = 0
		$foundMatch = $false
		$bestMatchTitle = $null
		$bestMatchTier = $null
		$matchedWindowCount = 0

		foreach ($window in $browserWindows) {
			$title = $window.Title
			if ([string]::IsNullOrWhiteSpace($title)) {
				Write-LogDebug " Skipping window with empty title!" -Style Warning
				continue
			}

			# Track if we find any "Problem loading page" windows (for localhost URL handling)
			if ($title -match $problemLoadingPagePattern) {
				$foundProblemLoadingPage = $true
				Write-LogDebug " Found 'Problem loading page' window => [$title]"
			}

			# Negative matching: Skip windows that contain service-specific words
			# (e.g., skip "Google Gemini" when looking for "Google Search")
			$skipDueToServiceWord = $false
			if ($excludeServiceWords.Count -gt 0) {
				foreach ($serviceWord in $excludeServiceWords) {
					if ($title -match "(?i)\b$([regex]::Escape($serviceWord))\b") {
						$skipDueToServiceWord = $true
						if (Test-LogVerbose) {
							Write-LogDebug "Skipping [$title] - contains service word [$serviceWord]" -Style Warning
						}
						break
					}
				}
			}
			if ($skipDueToServiceWord) { continue }

			# Special handling for exact title match mode (main homepages)
			if ($useExactTitleMatch) {
				# For main homepages like google.com, the browser title is usually just "Google"
				# Firefox adds " - Mozilla Firefox", Chrome adds " - Google Chrome", etc.
				$titleWithoutBrowser = $title
				foreach ($titleSuffixPattern in $browserTitleSuffixPatterns) {
					$titleWithoutBrowser = $titleWithoutBrowser -replace $titleSuffixPattern, ''
				}
				$titleWithoutBrowser = $titleWithoutBrowser.Trim()

				# Check for exact or near-exact match with GroupDisplayName
				if ($titleWithoutBrowser -eq $GroupDisplayName -or
					$titleWithoutBrowser -match "^$([regex]::Escape($GroupDisplayName))$") {
					Write-LogDebug " EXACT MATCH! Title [$titleWithoutBrowser] matches GroupDisplayName [$GroupDisplayName]" -Style Success
					if ($ReturnCount) {
						$matchedWindowCount++
						continue  # Continue to next window to count all matches
					}
					Write-LogWarning "[$GroupDisplayName] is already opened!"
					return $true
				}
				elseif (Test-LogVerbose) {
					Write-LogDebug "No exact match: [$titleWithoutBrowser] vs [$GroupDisplayName]" -Style Warning
				}
			}

			foreach ($keyword in $keywords) {
				$kw = $keyword.Word
				$kwTier = $keyword.Tier

				# Skip empty keywords to prevent false positive matches
				if ([string]::IsNullOrWhiteSpace($kw)) {
					Write-LogDebug " Skipping empty keyword!" -Style Warning
					continue
				}

				# Build regex pattern with multiple matching strategies:
				# 1. Word boundary match (most precise): \bkeyword\b
				# 2. Dash/underscore separated match: [\s\-_]keyword[\s\-_]
				# 3. URL slug format match (e.g., "minor-illusion" matches "Minor Illusion")
				$keywordEscaped = [regex]::Escape($kw)
				$keywordSlugPattern = $keywordEscaped -replace '-', '[\s\-_]'
				$keywordSlugPattern = $keywordSlugPattern -replace '_', '[\s\-_]'

				# Try word boundary match first (highest confidence)
				$isWordBoundaryMatch = $title -match "(?i)\b$keywordEscaped\b"

				# Try normalized slug match next, but keep whole-token boundaries so
				# profile/user slugs do not match inside longer identifiers.
				$isSlugMatch = $title -match "(?i)(?<![\p{L}\p{N}])$keywordSlugPattern(?![\p{L}\p{N}])"

				# Calculate match score (longer keyword = higher confidence)
				$matchScore = 0
				if ($isWordBoundaryMatch) {
					$matchScore = $kw.Length * $wordBoundaryScoreMultiplier  # Word boundary matches are worth more
					Write-LogDebug " MATCH! [$title] contains [$kw] (word boundary match, score: $matchScore, tier: $kwTier)" -Style Success
				}
				elseif ($isSlugMatch) {
					$matchScore = $kw.Length * $slugScoreMultiplier
					Write-LogDebug " MATCH! [$title] contains [$kw] (slug pattern match, score: $matchScore, tier: $kwTier)" -Style Success
				}
				elseif (Test-LogVerbose) {
					Write-LogDebug "No match => [$title] vs [$kw]" -Style Step
				}

				# Phase 2: Bidirectional negative matching for Secondary keywords
				# If a Secondary (parent domain) keyword matches, verify the window title
				# also contains at least one Primary keyword from this group.
				# E.g., "Google - Mozilla Firefox" matches Secondary keyword "google" from the AI group,
				# but contains none of the AI group's Primary keywords (gemini, claude, etc.) -> false positive
				if ($matchScore -gt 0 -and $kwTier -eq 'Secondary' -and $primaryKeywords.Count -gt 0) {
					$hasPrimaryInTitle = $false
					$titleCollapsed = $title -replace '\s+', ''
					foreach ($pk in $primaryKeywords) {
						$pkEscaped = [regex]::Escape($pk)
						# Try word boundary match first, then collapsed match for joined words (e.g., "aistudio" vs "AI Studio")
						if ($title -match "(?i)\b$pkEscaped\b" -or $titleCollapsed -match "(?i)$pkEscaped") {
							$hasPrimaryInTitle = $true
							break
						}
					}
					if (-not $hasPrimaryInTitle) {
						if (Test-LogVerbose) {
							Write-LogDebug "Demoted Secondary match [$kw] in [$title] - no Primary keywords found in title" -Style Warning
						}
						$matchScore = 0
					}
				}

				# Track best match
				if ($matchScore -gt $bestMatchScore) {
					$bestMatchScore = $matchScore
					$bestMatchTitle = $title
					$bestMatchTier = $kwTier
					$foundMatch = $true
				}

				# For very high confidence matches (long word boundary match), return immediately
				# Only for Primary keywords - Secondary keywords need full evaluation
				# Skip this fast-path for main homepage checks (need negative matching validation)
				if ($isWordBoundaryMatch -and $matchScore -gt 0 -and $kw.Length -ge $highConfidencePrimaryKeywordLength -and $kwTier -eq 'Primary' -and -not $isMainHomepage) {
					Write-LogDebug " HIGH CONFIDENCE MATCH! Keyword [$kw] found in window title [$title]" -Style Success
					if ($ReturnCount) {
						$matchedWindowCount++
						break  # Break keyword loop, continue to next window
					}
					Write-LogWarning "[$GroupDisplayName] is already opened!"
					return $true
				}
			}

			# In ReturnCount mode, check if this window had a reasonable match score
			if ($ReturnCount -and $foundMatch -and $bestMatchScore -ge $minimumAcceptedScore) {
				# Check if this window contributed to the best match (per-window scoring)
				# bestMatchTitle tracks which window had the best score
				if ($bestMatchTitle -eq $title) {
					$matchedWindowCount++
					# Reset for next window
					$bestMatchScore = 0
					$foundMatch = $false
					$bestMatchTitle = $null
					$bestMatchTier = $null
				}
			}
		}

		# If we found any match with reasonable confidence, consider it a match
		# Phase 3: For multi-URL groups (>3 URLs), require a Primary keyword match
		# A Secondary-only match (e.g., shared parent domain) is insufficient evidence
		if ($foundMatch -and $bestMatchScore -ge $minimumAcceptedScore) {
			$isSecondaryOnly = ($bestMatchTier -eq 'Secondary')
			if ($isSecondaryOnly -and $Urls.Count -gt $multiUrlSecondaryOnlyThreshold) {
				Write-LogDebug " Secondary-only match rejected for multi-URL group ($($Urls.Count) URLs, score: $bestMatchScore in [$bestMatchTitle])" -Style Warning
			}
			elseif ($ReturnCount) {
				$matchedWindowCount++
			}
			else {
				Write-LogDebug " Match found with score: $bestMatchScore in window: [$bestMatchTitle]" -Style Success
				Write-LogWarning "[$GroupDisplayName] is already opened!"
				return $true
			}
		}

		# Special handling for localhost URLs: if we found a "Problem loading page" window,
		# assume it might be the localhost URL we're looking for (since failed loads don't show the URL in the title)
		if ($hasLocalhostUrls -and $foundProblemLoadingPage) {
			if ($ReturnCount) {
				$matchedWindowCount++
			}
			else {
				if (Test-LogVerbose) {
					Write-LogDebug "Localhost URL(s) detected with [Problem loading page] window found!" -Style Warning
					Write-LogDebug "Assuming the failed page might be the localhost URL we're checking for..." -Style Warning
				}
				Write-LogWarning "[$GroupDisplayName] is already opened! (detected as failed localhost page)"
				return $true
			}
		}

		# Additional fallback: Check for partial URL matches in window titles (less common but possible)
		# Some browsers might show the full URL in the title
		if (-not $foundMatch) {
			foreach ($window in $browserWindows) {
				$title = $window.Title
				if ([string]::IsNullOrWhiteSpace($title)) { continue }

				# Apply negative matching to fallback as well
				$skipDueToServiceWord = $false
				if ($excludeServiceWords.Count -gt 0) {
					foreach ($serviceWord in $excludeServiceWords) {
						if ($title -match "(?i)\b$([regex]::Escape($serviceWord))\b") {
							$skipDueToServiceWord = $true
							break
						}
					}
				}
				if ($skipDueToServiceWord) { continue }

				foreach ($url in $Urls) {
					try {
						$uri = [System.Uri]$url
						# Check if the full domain appears in the title
						if ($title -match [regex]::Escape($uri.Host)) {
							Write-LogDebug " Fallback match: Found full domain [$($uri.Host)] in title [$title]"
							if ($ReturnCount) {
								$matchedWindowCount++
								break  # Break URL loop, continue to next window
							}
							Write-LogWarning "[$GroupDisplayName] is already opened! (domain match)"
							return $true
						}
					}
					catch {
						# Skip invalid URLs
					}
				}
			}
		}

		if ($ReturnCount) {
			Write-LogDebug " [ReturnCount] Found $matchedWindowCount matching window(s) for [$GroupDisplayName]"
			return $matchedWindowCount
		}

		if (Test-LogVerbose) {
			if ($keywords.Count -eq 0) {
				Write-LogDebug "WARNING: No valid keywords extracted from URLs!" -Style Error
			}
			Write-LogDebug "No matches found - group is NOT already open! (best score: $bestMatchScore)" -Style Warning
		}
		return $false
	}
	catch {
		Write-LogDebug "Error => $_" -Style Error
		Write-LogDebug "Stack trace => $($_.ScriptStackTrace)" -Style Error

		return $false
	}
}
