function Invoke-GoogleTranslate {
	<#
	.SYNOPSIS
		Translates text using Google Translate.

	.DESCRIPTION
		Translates text between languages using the Google Translate API.
		The output language is configured in Configuration.psd1 under
		DefaultTranslateLanguages. The source language is auto-detected unless
		-InputLanguage is provided. Supports both positional (quick) and named
		parameter usage.

	.PARAMETER Text
		The text to translate. Accepts remaining arguments so multi-word input
		does not need to be quoted.

	.PARAMETER InputLanguage
		Optional source language override. When omitted, Google Translate auto-detects
		the input language.

	.PARAMETER OutputLanguage
		Target language for translation. Defaults to Configuration.psd1 → DefaultTranslateLanguages.OutputLanguage.

	.EXAMPLE
		Invoke-GoogleTranslate kako si
		# Auto-detects the input language and translates to English (using defaults)

	.EXAMPLE
		Invoke-GoogleTranslate -InputLanguage English -OutputLanguage Croatian -Text hello world
		# Translates "hello world" from English to Croatian

	.EXAMPLE
		Invoke-GoogleTranslate -InputLanguage German -OutputLanguage English -Text guten morgen
		# Translates "guten morgen" from German to English
	#>
	[CmdletBinding(PositionalBinding = $false)]
	param(
		[string]$InputLanguage,

		[string]$OutputLanguage,

		[string]$Text,

		[Parameter(Position = 0, ValueFromRemainingArguments, DontShow)]
		[string[]]$RemainingWords
	)

	# Merge -Text (named, single token) with remaining positional words
	$allText = @()
	if ($Text) { $allText += $Text }
	if ($RemainingWords) { $allText += $RemainingWords }
	$translationText = ($allText -join ' ').Trim()

	# Load the default output language from configuration
	$defaults = $global:Configuration.DefaultTranslateLanguages
	$defaultOutput = if ($defaults) { $defaults.OutputLanguage } else { "English" }

	$sourceLang = if ($PSBoundParameters.ContainsKey('InputLanguage')) { $InputLanguage } else { "Auto" }
	$targetLang = if ($PSBoundParameters.ContainsKey('OutputLanguage')) { $OutputLanguage } else { $defaultOutput }

	if (-not $translationText) {
		Write-Warning "No text provided to translate."
		return
	}

	# Map language names to Google Translate language codes
	$languageMap = @{
		"Afrikaans"   = "af";
		"Albanian"    = "sq";
		"Arabic"      = "ar";
		"Armenian"    = "hy"
		"Azerbaijani" = "az";
		"Basque"      = "eu";
		"Belarusian"  = "be";
		"Bengali"     = "bn"
		"Bosnian"     = "bs";
		"Bulgarian"   = "bg";
		"Catalan"     = "ca";
		"Chinese"     = "zh-CN"
		"Croatian"    = "hr";
		"Czech"       = "cs";
		"Danish"      = "da";
		"Dutch"       = "nl"
		"English"     = "en";
		"Estonian"    = "et";
		"Finnish"     = "fi";
		"French"      = "fr"
		"Galician"    = "gl";
		"Georgian"    = "ka";
		"German"      = "de";
		"Greek"       = "el"
		"Gujarati"    = "gu";
		"Hebrew"      = "he";
		"Hindi"       = "hi";
		"Hungarian"   = "hu"
		"Icelandic"   = "is";
		"Indonesian"  = "id";
		"Irish"       = "ga";
		"Italian"     = "it"
		"Japanese"    = "ja";
		"Kannada"     = "kn";
		"Kazakh"      = "kk";
		"Korean"      = "ko"
		"Latvian"     = "lv";
		"Lithuanian"  = "lt";
		"Macedonian"  = "mk";
		"Malay"       = "ms"
		"Maltese"     = "mt";
		"Mongolian"   = "mn";
		"Norwegian"   = "no";
		"Persian"     = "fa"
		"Polish"      = "pl";
		"Portuguese"  = "pt";
		"Romanian"    = "ro";
		"Russian"     = "ru"
		"Serbian"     = "sr";
		"Slovak"      = "sk";
		"Slovenian"   = "sl";
		"Spanish"     = "es"
		"Swahili"     = "sw";
		"Swedish"     = "sv";
		"Tamil"       = "ta";
		"Telugu"      = "te"
		"Thai"        = "th";
		"Turkish"     = "tr";
		"Ukrainian"   = "uk";
		"Urdu"        = "ur"
		"Uzbek"       = "uz";
		"Vietnamese"  = "vi";
		"Welsh"       = "cy"
	}

	$sourceCode = if (-not $PSBoundParameters.ContainsKey('InputLanguage') -or $InputLanguage -in @('Auto', 'Detect', 'Automatic')) {
		'auto'
	}
	else {
		$languageMap[$sourceLang]
	}
	$targetCode = $languageMap[$targetLang]

	$supportedList = ($languageMap.Keys | Sort-Object | ForEach-Object { "  - $_" }) -join "`n"

	if (-not $sourceCode) {
		Write-Error "Unsupported input language: '$sourceLang'.`nSupported:`n$supportedList"
		return
	}
	if (-not $targetCode) {
		Write-Error "Unsupported output language: '$targetLang'.`nSupported:`n$supportedList"
		return
	}

	$encodedText = [System.Uri]::EscapeDataString($translationText)
	$uri = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=$sourceCode&tl=$targetCode&dt=t&q=$encodedText"

	try {
		$response = Invoke-RestMethod -Uri $uri -Method Get -ErrorAction Stop
		$translated = ($response[0] | ForEach-Object { $_[0] }) -join ''
		return Write-Host -ForegroundColor Green "`n[$targetLang] => $translated"
	}
	catch {
		Write-Error "Translation failed: $_"
	}
}
