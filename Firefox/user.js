//
/* You may copy+paste this file and use it as it is.
 *
 * If you make changes to your about:config while the program is running, the
 * changes will be overwritten by the user.js when the application restarts.
 *
 * To make lasting changes to preferences, you will have to edit the user.js.
 */

/****************************************************************************
 * Betterfox                                                                *
 * "Ad meliora"                                                             *
 * version: 146                                                             *
 * url: https://github.com/yokoffing/Betterfox                              *
 ****************************************************************************/

/****************************************************************************
 * SECTION: FASTFOX                                                         *
 * Performance optimizations for faster browsing                            *
 ****************************************************************************/

/** GENERAL ***/
// Sets font cache to 32MB for faster text rendering
user_pref("gfx.content.skia-font-cache-size", 32);

/** GFX (Graphics) ***/
// Enables hardware acceleration for compositing layers (faster rendering)
user_pref("gfx.webrender.layer-compositor", true);

// Increases canvas cache for better performance with graphics-heavy sites
// 32,768 items, 4MB total cache
user_pref("gfx.canvas.accelerated.cache-items", 32768);
user_pref("gfx.canvas.accelerated.cache-size", 4096);

// Allows larger WebGL textures (16384x16384 pixels) for 3D graphics
user_pref("webgl.max-size", 16384);

/** DISK CACHE ***/
// DISABLES writing cache to disk - everything stays in RAM for speed
// Requires sufficient RAM (8GB+). Trade-off: faster but uses more memory
user_pref("browser.cache.disk.enable", false);

/** MEMORY CACHE ***/
// Sets RAM cache to 128MB for pages/resources
user_pref("browser.cache.memory.capacity", 131072);

// Max size for a single cached item: 20MB
user_pref("browser.cache.memory.max_entry_size", 20480);

// Keeps 4 pages in memory for instant back/forward navigation
user_pref("browser.sessionhistory.max_total_viewers", 4);

// Remember last 10 closed tabs for "Undo Close Tab"
user_pref("browser.sessionstore.max_tabs_undo", 10);

/** MEDIA CACHE ***/
// Video/audio cache: 256MB per media element
user_pref("media.memory_cache_max_size", 262144);

// Total combined media cache limit: 1GB
user_pref("media.memory_caches_combined_limit_kb", 1048576);

// Buffer 10 minutes (600s) of video ahead for smoother playback
user_pref("media.cache_readahead_limit", 600);

// Resume buffering when 5 minutes (300s) of buffer remain
user_pref("media.cache_resume_threshold", 300);

/** IMAGE CACHE ***/
// Image cache: 10MB
user_pref("image.cache.size", 10485760);

// Decode images in 64KB chunks for faster loading
user_pref("image.mem.decode_bytes_at_a_time", 65536);

/** NETWORK ***/
// Allow up to 1800 simultaneous connections total (default: 900)
user_pref("network.http.max-connections", 1800);

// Max 10 persistent keep-alive connections per server
user_pref("network.http.max-persistent-connections-per-server", 10);

// Allow 5 "urgent" connections per host for critical resources (CSS, JS)
user_pref("network.http.max-urgent-start-excessive-connections-per-host", 5);

// Max 5ms delay before starting a request (reduced from default 10)
user_pref("network.http.request.max-start-delay", 5);

// DISABLES request pacing - sends requests immediately
// Trade-off: faster but more aggressive network usage
user_pref("network.http.pacing.requests.enabled", false);

// DNS cache: 10,000 entries (default: 400)
user_pref("network.dnsCacheEntries", 10000);

// DNS entries expire after 1 hour (3600 seconds)
user_pref("network.dnsCacheExpiration", 3600);

// SSL session cache: 10,240 entries for faster HTTPS reconnections
user_pref("network.ssl_tokens_cache_capacity", 10240);

/** SPECULATIVE LOADING ***/
// DISABLES all predictive/speculative loading features
// Firefox won't preload pages you might visit or pre-resolve DNS
// Trade-off: Better privacy, slightly slower navigation (no pre-fetching)
user_pref("network.http.speculative-parallel-limit", 0);
user_pref("network.dns.disablePrefetch", true);
user_pref("network.dns.disablePrefetchFromHTTPS", true);
user_pref("browser.urlbar.speculativeConnect.enabled", false);
user_pref("browser.places.speculativeConnect.enabled", false);
user_pref("network.prefetch-next", false);

/****************************************************************************
 * SECTION: SECUREFOX                                                       *
 * Privacy and security settings to protect user data                      *
 ****************************************************************************/

/** TRACKING PROTECTION ***/
// Enables Strict Enhanced Tracking Protection
// Blocks most trackers, cookies, cryptominers, fingerprinters
// May break some sites - disable per-site if needed
user_pref("browser.contentblocking.category", "strict");

// Downloads start in temp folder (more secure, can't be auto-executed)
user_pref("browser.download.start_downloads_in_tmp_dir", true);

// Disables website-triggered UI tours/onboarding
user_pref("browser.uitour.enabled", false);

// Sends "Global Privacy Control" signal requesting no data sale/sharing
user_pref("privacy.globalprivacycontrol.enabled", true);

/** OCSP & CERTS / HPKP ***/
// DISABLES OCSP (Online Certificate Status Protocol) checking
// Trade-off: Privacy gain (no request to CA on every HTTPS connection)
// vs slight security loss (won't detect revoked certificates immediately)
user_pref("security.OCSP.enabled", 0);

// Isolates content scripts to prevent cross-extension tracking
user_pref("privacy.antitracking.isolateContentScriptResources", true);

// Disables Content Security Policy violation reports
// Prevents websites from tracking CSP violations
user_pref("security.csp.reporting.enabled", false);

/** SSL / TLS ***/
// Treats unsafe SSL renegotiation as broken connection (security)
user_pref("security.ssl.treat_unsafe_negotiation_as_broken", true);

// Shows advanced "Accept Risk" option on certificate error pages
user_pref("browser.xul.error_pages.expert_bad_cert", true);

// DISABLES TLS 0-RTT (Zero Round Trip Time)
// Prevents replay attacks, adds ~1 round trip to first connection
// Trade-off: Better security vs slightly slower initial HTTPS connection
user_pref("security.tls.enable_0rtt_data", false);

/** DISK AVOIDANCE ***/
// Forces media to cache in RAM only in private browsing (no disk traces)
user_pref("browser.privatebrowsing.forceMediaMemoryCache", true);

// Saves session every 60 seconds instead of 15 (less disk writing)
user_pref("browser.sessionstore.interval", 60000);

/** SHUTDOWN & SANITIZING ***/
// Enables custom history/privacy settings
user_pref("privacy.history.custom", true);

// Resets private browsing mode completely on close
user_pref("browser.privatebrowsing.resetPBM.enabled", true);

/** SEARCH / URL BAR ***/
// Hides "https://" prefix in address bar for cleaner look
user_pref("browser.urlbar.trimHttps", true);

// Shows full URL (including https://) when you click address bar
user_pref("browser.urlbar.untrimOnUserInteraction.featureGate", true);

// Allows different default search engine for private browsing
user_pref("browser.search.separatePrivateDefault.ui.enabled", true);

// DISABLES search suggestions from search engine
// Everything you type in address bar stays local
// Trade-off: Privacy vs convenience of search suggestions
user_pref("browser.search.suggest.enabled", false);

// Disables Firefox Suggest (sponsored suggestions in address bar)
user_pref("browser.urlbar.quicksuggest.enabled", false);

// Disables grouping labels in address bar dropdown
user_pref("browser.urlbar.groupLabels.enabled", false);

// DISABLES form autofill (you must type everything manually)
// Trade-off: Privacy vs convenience
user_pref("browser.formfill.enable", false);

// Shows punycode for international domain names
// Prevents phishing (e.g., "аpple.com" with Cyrillic 'а' looks like "apple.com")
user_pref("network.IDN_show_punycode", true);

/** HTTPS-ONLY MODE ***/
// Automatically upgrades HTTP connections to HTTPS when possible
user_pref("dom.security.https_only_mode", true);

// Shows helpful suggestions on HTTPS-only error pages
user_pref("dom.security.https_only_mode_error_page_user_suggestions", true);

/** PASSWORDS ***/
// Disables capturing passwords from non-standard forms
// (forms without standard submit buttons)
user_pref("signon.formlessCapture.enabled", false);

// Doesn't save passwords entered in private browsing
user_pref("signon.privateBrowsingCapture.enabled", false);

// Allows HTTP authentication for subresources only if same-origin
user_pref("network.auth.subresource-http-auth-allow", 1);

// Doesn't truncate large pastes (allows pasting long passwords/text)
user_pref("editor.truncate_user_pastes", false);

/** EXTENSIONS ***/
// Controls where extensions can be installed from
// 5 = profile folder + application folder
user_pref("extensions.enabledScopes", 5);

/** HEADERS / REFERERS ***/
// When navigating cross-origin, sends only origin (not full URL) as referer
// Example: visiting site B from site A sends "https://A.com" not "https://A.com/page.html"
user_pref("network.http.referer.XOriginTrimmingPolicy", 2);

/** CONTAINERS ***/
// Enables container tabs UI for multi-account login
// Requires Multi-Account Containers extension for full functionality
user_pref("privacy.userContext.ui.enabled", true);

/** VARIOUS ***/
// DISABLES JavaScript in PDFs (security - prevents malicious PDF scripts)
user_pref("pdfjs.enableScripting", false);

/** SAFE BROWSING ***/
// Disables sending download metadata to Google for Safe Browsing checks
// Trade-off: Privacy vs detecting malicious downloads
user_pref("browser.safebrowsing.downloads.remote.enabled", false);

/** MOZILLA ***/
// Blocks all notification requests by default (value: 2)
// (Overridden in MY OVERRIDES to 0 = ask permission)
user_pref("permissions.default.desktop-notification", 2);

// Blocks all location requests by default (value: 2)
// (Overridden in MY OVERRIDES to 0 = ask permission)
user_pref("permissions.default.geo", 2);

// Uses BeaconDB instead of Google for geolocation API
user_pref("geo.provider.network.url", "https://beacondb.net/v1/geolocate");

// Disables automatic search engine updates
user_pref("browser.search.update", false);

// Clears default permissions URL (privacy)
user_pref("permissions.manager.defaultsUrl", "");

// Disables add-on recommendations cache
user_pref("extensions.getAddons.cache.enabled", false);

/** TELEMETRY ***/
// All settings below DISABLE data collection and sending to Mozilla
// Improves privacy and slightly reduces network/CPU usage
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.server", "data:,");
user_pref("toolkit.telemetry.archive.enabled", false);
user_pref("toolkit.telemetry.newProfilePing.enabled", false);
user_pref("toolkit.telemetry.shutdownPingSender.enabled", false);
user_pref("toolkit.telemetry.updatePing.enabled", false);
user_pref("toolkit.telemetry.bhrPing.enabled", false);
user_pref("toolkit.telemetry.firstShutdownPing.enabled", false);
user_pref("toolkit.telemetry.coverage.opt-out", true);
user_pref("toolkit.coverage.opt-out", true);
user_pref("toolkit.coverage.endpoint.base", "");
user_pref("browser.newtabpage.activity-stream.feeds.telemetry", false);
user_pref("browser.newtabpage.activity-stream.telemetry", false);
user_pref("datareporting.usage.uploadEnabled", false);

/** EXPERIMENTS ***/
// Disables Mozilla experiments and studies (SHIELD)
user_pref("app.shield.optoutstudies.enabled", false);
user_pref("app.normandy.enabled", false);
user_pref("app.normandy.api_url", "");

/** CRASH REPORTS ***/
// Disables automatic crash report submission
user_pref("breakpad.reportURL", "");
user_pref("browser.tabs.crashReporting.sendReport", false);

/****************************************************************************
 * SECTION: PESKYFOX                                                        *
 * Removes annoying UI elements and Mozilla recommendations                *
 ****************************************************************************/

/** MOZILLA UI ***/
// Hides "Get Add-ons" pane in about:addons
user_pref("extensions.getAddons.showPane", false);

// Disables add-on recommendations in about:addons
user_pref("extensions.htmlaboutaddons.recommendations.enabled", false);

// Disables "Recommended by Pocket" and other Mozilla recommendations
user_pref("browser.discovery.enabled", false);

// Stops asking to set Firefox as default browser
user_pref("browser.shell.checkDefaultBrowser", false);

// Disables "Contextual Feature Recommender" popups
// (Suggestions for add-ons and features while browsing)
user_pref(
	"browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons",
	false,
);
user_pref(
	"browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features",
	false,
);

// Hides "More from Mozilla" section in Settings
user_pref("browser.preferences.moreFromMozilla", false);

// Skips warning page when opening about:config
user_pref("browser.aboutConfig.showWarning", false);

// Disables "What's New" page after Firefox updates
user_pref("browser.startup.homepage_override.mstone", "ignore");

// Disables welcome page on first run
user_pref("browser.aboutwelcome.enabled", false);

// Disables Firefox profiles feature (removes profile name from window title)
user_pref("browser.profiles.enabled", false);

// Clears the profile store ID so Firefox doesn't associate a named profile group
user_pref("toolkit.profiles.storeID", "");

/** THEME ADJUSTMENTS ***/
// Allows userChrome.css and userContent.css for custom styling
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

// Shows "Compact" density option in Customize toolbar
user_pref("browser.compactmode.show", true);

// Disables separate taskbar button for private windows (Windows only)
user_pref("browser.privateWindowSeparation.enabled", false);

/** AI ***/
// DISABLES all built-in AI features
user_pref("browser.ml.enable", false); // AI infrastructure
user_pref("browser.ml.chat.enabled", true); // AI chatbot
user_pref("browser.ml.chat.menu", false); // AI chat in right-click menu
user_pref("browser.tabs.groups.smart.enabled", false); // Smart tab groups
user_pref("browser.ml.linkPreview.enabled", false); // AI link previews

/** FULLSCREEN NOTICE ***/
// Removes fullscreen animation and warning message
user_pref("full-screen-api.transition-duration.enter", "0 0");
user_pref("full-screen-api.transition-duration.leave", "0 0");
user_pref("full-screen-api.warning.timeout", 0);

/** URL BAR ***/
// Disables trending searches in address bar dropdown
user_pref("browser.urlbar.trending.featureGate", false);

/** NEW TAB PAGE ***/
// Removes default top sites (Facebook, Twitter, etc.)
user_pref("browser.newtabpage.activity-stream.default.sites", "");

// Disables sponsored shortcuts on new tab page
user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);

// Disables "Recommended by Pocket" stories
user_pref("browser.newtabpage.activity-stream.feeds.section.topstories", false);

// Disables sponsored stories
user_pref("browser.newtabpage.activity-stream.showSponsored", false);

// Hides sponsored content checkboxes in settings
user_pref("browser.newtabpage.activity-stream.showSponsoredCheckboxes", false);

/** DOWNLOADS ***/
// Doesn't add downloads to Windows "Recent Documents" list
user_pref("browser.download.manager.addToRecentDocs", false);

/** PDF ***/
// Opens PDF attachments in browser instead of downloading
user_pref("browser.download.open_pdf_attachments_inline", true);

/** TAB BEHAVIOR ***/
// Keeps bookmark menu open when opening bookmark in new tab
user_pref("browser.bookmarks.openInTabClosesMenu", false);

// Shows "View Image Info" option in right-click context menu
user_pref("browser.menu.showViewImageInfo", true);

// Highlights all matches when using Ctrl+F find bar
user_pref("findbar.highlightAll", true);

// Double-clicking to select a word doesn't include trailing space
user_pref("layout.word_select.eat_space_to_next_word", false);

/****************************************************************************
 * START: MY OVERRIDES                                                      *
 * Personal customizations that override Betterfox defaults                *
 ****************************************************************************/
// visit https://github.com/yokoffing/Betterfox/wiki/Common-Overrides
// visit https://github.com/yokoffing/Betterfox/wiki/Optional-Hardening
// Enter your personal overrides below this line:

/** WINDOWS FONT RENDERING ***/
// Improves text clarity on Windows using DirectWrite (like Chrome)
// Makes fonts look sharper and less blurry
user_pref("gfx.font_rendering.cleartype_params.rendering_mode", 5);
user_pref("gfx.font_rendering.cleartype_params.cleartype_level", 100);
user_pref("gfx.font_rendering.directwrite.use_gdi_table_loading", false);
//user_pref("gfx.font_rendering.cleartype_params.enhanced_contrast", 50); // 50-100 [OPTIONAL]

/** PERMISSIONS ***/
// OVERRIDES Betterfox default (which blocks all requests)
// Allows websites to ASK for location permission (value: 0 = ask)
user_pref("permissions.default.geo", 0);

// OVERRIDES Betterfox default (which blocks all requests)
// Allows websites to ASK to send notifications (value: 0 = ask)
user_pref("permissions.default.desktop-notification", 0);

/** NEW TAB PAGE SHORTCUTS ***/
// Set to FALSE to disable showing pinned shortcuts on new tab
// user_pref("browser.newtabpage.activity-stream.feeds.topsites", false);
user_pref("browser.newtabpage.activity-stream.feeds.topsites", true);

// Removes default top sites (Facebook, Twitter, Amazon, etc.)
// This doesn't prevent you from adding your own shortcuts
user_pref("browser.newtabpage.activity-stream.default.sites", "");

// Remove sponsored content from new tab (duplicate from Peskyfox, but ensuring it's set)
user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false); // Sponsored shortcuts
user_pref("browser.newtabpage.activity-stream.feeds.section.topstories", false); // Recommended by Pocket
user_pref("browser.newtabpage.activity-stream.showSponsored", false); // Sponsored Stories

/** FIREFOX VIEW ***/
// Disables the Firefox View feature tour popup
user_pref("browser.firefox-view.feature-tour", '{"screen":"","complete":true}');

/** PASSWORD & FORM MANAGEMENT ***/
// DISABLES built-in password manager
// Use external password manager like Bitwarden or 1Password instead
user_pref("signon.rememberSignons", false);

// DISABLES address autofill manager
user_pref("extensions.formautofill.addresses.enabled", false);

// DISABLES credit card autofill manager
user_pref("extensions.formautofill.creditCards.enabled", false);

/** CAPTIVE PORTAL DETECTION ***/
// DISABLES auto-detection of public WiFi login pages
// Not needed on a trusted/VPN-managed network
// If you use public WiFi, consider enabling this
user_pref("captivedetect.canonicalURL", "");
user_pref("network.captive-portal-service.enabled", true);
user_pref("network.connectivity-service.enabled", true);

/** DNS-OVER-HTTPS (DoH) ***/
// Sets DoH provider to DNSWarden (with Hagezi blocklists)
// Provides DNS-level ad/tracker/malware blocking
user_pref(
	"network.trr.uri",
	"https://dns.dnswarden.com/00000000000000000000028",
);

// DoH MODE: 0 = DISABLED (fastest)
// DoH is disabled here for maximum speed (DNS handled elsewhere)
// e.g. a VPN or local resolver can handle DNS separately
// Other modes: 2 = try DoH first, fallback to normal DNS
//              3 = DoH only (strict, can break if DoH fails)
user_pref("network.trr.mode", 0);

/** NEW TAB CUSTOMIZATION ***/
// Hides weather widget on new tab page
user_pref("browser.newtabpage.activity-stream.showWeather", false);

/** ADDRESS BAR ***/
// Hides top sites in dropdown when clicking address bar
// Keeps address bar cleaner
user_pref("browser.urlbar.suggest.topsites", false);

/** CERTIFICATE PINNING ***/
// STRICT certificate pinning enforcement
// Value: 1 = allow user MiTM (default, allows antivirus inspection)
//        2 = strict (blocks MiTM, may break with corporate proxies/antivirus)
// Trade-off: Better security vs potential issues with legitimate MiTM
// (antivirus software, corporate firewalls, parental controls)
user_pref("security.cert_pinning.enforcement_level", 2);

/** PRIVACY - CLEAR DATA ON SHUTDOWN ***/
// Clears browsing data when Firefox closes
user_pref("privacy.sanitize.sanitizeOnShutdown", true);

// What to clear on shutdown:
user_pref("privacy.clearOnShutdown_v2.cache", false); // KEEP cache (faster restart)
user_pref("privacy.clearOnShutdown_v2.cookiesAndStorage", false); // KEEP cookies (stay logged in)
user_pref("privacy.clearOnShutdown_v2.browsingHistoryAndDownloads", true); // CLEAR history
user_pref("privacy.clearOnShutdown_v2.downloads", true); // CLEAR download history
user_pref("privacy.clearOnShutdown_v2.formdata", true); // CLEAR form data

/** SESSION PRIVACY ***/
// Doesn't save form content, scroll positions, or POST data in session
// Value: 0 = save everything
//        1 = save everything except on HTTPS pages
//        2 = never save (most private)
// Trade-off: Better privacy vs slower session restoration after crash/restart
user_pref("browser.sessionstore.privacy_level", 2);

// --- SESSION RESTORE: DISABLE COMPLETELY ---
// Ensure Firefox does NOT restore previous session under any circumstance.
// - `browser.startup.page = 1` opens Firefox Home (Default) on startup (never restores)
// - `browser.startup.homepage` set to about:home (Firefox Home)
// - `browser.startup.restoreLastSession` explicitly disabled
// - disable automatic resume-after-crash and limit resumed-crashes to 0
user_pref("browser.startup.page", 1);
user_pref("browser.startup.homepage", "about:home");
user_pref("browser.startup.restoreLastSession", false);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("browser.sessionstore.max_resumed_crashes", 0);
user_pref("browser.sessionstore.restore_on_demand", false);

/** DRM (DIGITAL RIGHTS MANAGEMENT) ***/
// DISABLES DRM content playback
// BREAKS: Netflix, Spotify, Disney+, Hulu, Amazon Prime Video, etc.
// Enable if you use streaming services:
//   user_pref("media.eme.enabled", true);
//   user_pref("browser.eme.ui.enabled", true);
user_pref("media.eme.enabled", false);
user_pref("browser.eme.ui.enabled", false);

/****************************************************************************
 * SECTION: SMOOTHFOX                                                       *
 * Smooth scrolling configuration                                           *
 ****************************************************************************/
// visit https://github.com/yokoffing/Betterfox/blob/main/Smoothfox.js
// Enter your scrolling overrides below this line:

/** ADDRESS BAR SEARCH ***/
// Disables unified search button in address bar (search engine switcher)
user_pref("browser.urlbar.scotchBonnet.enableOverride", false);

/****************************************************************************
 * END: BETTERFOX                                                           *
 ****************************************************************************/

/****************************************************************************
 * PERFORMANCE NOTES:                                                       *
 *                                                                          *
 * SPEED OPTIMIZATIONS IN THIS CONFIG:                                     *
 * ✓ Disk cache disabled (all in RAM)                                      *
 * ✓ Large memory caches (128MB browser, 1GB media)                        *
 * ✓ DNS cache: 10,000 entries                                             *
 * ✓ DoH disabled (mode 0) for fastest DNS                                 *
 * ✓ Increased network connections (1800 total)                            *
 * ✓ Request pacing disabled (immediate requests)                          *
 *                                                                          *
 * PRIVACY TRADE-OFFS:                                                      *
 * ⚠ Speculative loading disabled (no pre-fetching)                        *
 * ⚠ Search suggestions disabled (no typing sent to search engine)         *
 * ⚠ Telemetry completely disabled                                         *
 * ⚠ Safe Browsing reduced (no download metadata to Google)                *
 *                                                                          *
 * CONVENIENCE TRADE-OFFS:                                                  *
 * ⚠ DRM disabled (streaming services won't work)                          *
 * ⚠ Password manager disabled (use external manager)                      *
 * ⚠ Form autofill disabled (manual typing required)                       *
 * ⚠ History cleared on shutdown                                           *
 *                                                                          *
 * SECURITY ENHANCEMENTS:                                                   *
 * ✓ Strict tracking protection                                            *
 * ✓ HTTPS-only mode                                                       *
 * ✓ Certificate pinning (strict)                                          *
 * ✓ TLS 0-RTT disabled (prevents replay attacks)                          *
 * ✓ PDF JavaScript disabled                                               *
 *                                                                          *
 * RECOMMENDED RAM: 8GB minimum (16GB+ ideal)                              *
 * Disk cache disabled means everything uses RAM                           *
 *                                                                          *
 ****************************************************************************/

/****************************************************************************
 * FIX: "Original profile" APPEARING IN WINDOW TITLE                        *
 *                                                                          *
 * If Firefox shows "Google - Original profile - Mozilla Firefox" instead   *
 * of "Google - Mozilla Firefox", follow these steps:                       *
 *                                                                          *
 * 1. Close Firefox completely (check Task Manager for firefox.exe)         *
 *                                                                          *
 * 2. Ensure this user.js has:                                              *
 *      user_pref("browser.profiles.enabled", false);                       *
 *      user_pref("toolkit.profiles.storeID", "");                          *
 *                                                                          *
 * 3. Edit profiles.ini at:                                                 *
 *      %APPDATA%\Mozilla\Firefox\profiles.ini                              *
 *                                                                          *
 *    Remove these two lines from the [Profile0] section:                   *
 *      StoreID=d72bf3f7                                                    *
 *      ShowSelector=1                                                      *
 *                                                                          *
 *    Before:                                                               *
 *      [Profile0]                                                          *
 *      Name=default-release                                                *
 *      IsRelative=1                                                        *
 *      Path=Profiles/lhsx19yx.default-release                              *
 *      StoreID=d72bf3f7                                                    *
 *      ShowSelector=1                                                      *
 *                                                                          *
 *    After:                                                                *
 *      [Profile0]                                                          *
 *      Name=default-release                                                *
 *      IsRelative=1                                                        *
 *      Path=Profiles/lhsx19yx.default-release                              *
 *                                                                          *
 * 4. Deploy user.js to the Firefox profile folder:                         *
 *      %APPDATA%\Mozilla\Firefox\Profiles\lhsx19yx.default-release\        *
 *                                                                          *
 * 5. Relaunch Firefox. The title should now be "Google - Mozilla Firefox". *
 *                                                                          *
 ****************************************************************************/
