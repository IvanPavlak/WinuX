# Add Browser Group

This guide shows how to add URL groups for use with `Open-Browser`.

## What Are Browser Groups?

Browser groups are collections of URLs that can be opened together:

```powershell
Open-Browser AI          # Opens ChatGPT, Claude, Perplexity, etc.
Open-Browser Tools,AI    # Opens multiple groups
Open-Browser ChatGPT     # Opens single named URL directly
```

## Browser Groups Structure

Groups support unlimited nesting:

```powershell
BrowserGroups = @(
    @{ GroupName = @(
        @{ Name = "UrlName"; Url = "https://example.com" }
    )}
)
```

## Adding a Simple Group

### Flat URL List

```powershell
BrowserGroups = @(
    # Existing groups...

    @{ MyTools = @(
        "https://tool1.com"
        "https://tool2.com"
        "https://tool3.com"
    )}
)
```

Usage:

```powershell
Open-Browser MyTools    # Opens all 3 URLs
```

### Named URLs (Recommended)

Named URLs allow direct access:

```powershell
BrowserGroups = @(
    @{ AI = @(
        @{ Name = "ChatGPT"; Url = "https://chat.openai.com/" }
        @{ Name = "Claude"; Url = "https://claude.ai/new" }
        @{ Name = "Perplexity"; Url = "https://www.perplexity.ai/" }
    )}
)
```

Usage:

```powershell
Open-Browser AI         # Opens all AI URLs
Open-Browser ChatGPT    # Opens only ChatGPT
Open-Browser Claude     # Opens only Claude
```

## Adding Nested Groups

For organization:

```powershell
BrowserGroups = @(
    @{ GitHub = @(
        @{ Personal = @(
            @{ Name = "PersonalProfile"; Url = "https://github.com/YourUsername" }
            @{ Name = "WinuXRepo"; Url = "https://github.com/YourUsername/WinuX" }
        )}
        @{ Work = @(
            @{ Name = "WorkProfile"; Url = "https://github.com/WorkOrg" }
            @{ Name = "WorkProject"; Url = "https://github.com/WorkOrg/Project" }
        )}
    )}
)
```

Usage:

```powershell
Open-Browser GitHub             # Opens ALL GitHub URLs (Personal + Work)
Open-Browser Personal           # Opens Personal subgroup
Open-Browser PersonalProfile    # Opens single URL
```

## Name Uniqueness Requirement

> [!WARNING]
> Names must be **unique across ALL groups**!

❌ **Bad** - Duplicate names:

```powershell
@{ Personal = @(
    @{ Name = "Profile"; Url = "https://github.com/personal" }   # "Profile" used
)}
@{ Work = @(
    @{ Name = "Profile"; Url = "https://github.com/work" }       # "Profile" used again!
)}
```

✅ **Good** - Unique names:

```powershell
@{ Personal = @(
    @{ Name = "PersonalProfile"; Url = "https://github.com/personal" }
)}
@{ Work = @(
    @{ Name = "WorkProfile"; Url = "https://github.com/work" }
)}
```

## Complex Nesting Example

```powershell
BrowserGroups = @(
    @{ Development = @(
        @{ Documentation = @(
            @{ Name = "MDN"; Url = "https://developer.mozilla.org" }
            @{ Name = "DevDocs"; Url = "https://devdocs.io" }
        )}
        @{ Tools = @(
            @{ Name = "Regex101"; Url = "https://regex101.com/" }
            @{ Name = "JsonFormatter"; Url = "https://jsonformatter.org/" }
        )}
        @{ Learning = @(
            @{ Tutorials = @(
                @{ Name = "FreeCodeCamp"; Url = "https://www.freecodecamp.org" }
                @{ Name = "Codecademy"; Url = "https://www.codecademy.com" }
            )}
            @{ Courses = @(
                @{ Name = "Pluralsight"; Url = "https://www.pluralsight.com" }
                @{ Name = "Udemy"; Url = "https://www.udemy.com" }
            )}
        )}
    )}
)
```

Usage:

```powershell
Open-Browser Development     # Opens EVERYTHING (8 URLs)
Open-Browser Documentation   # Opens MDN + DevDocs
Open-Browser Learning        # Opens all 4 learning URLs
Open-Browser Tutorials       # Opens FreeCodeCamp + Codecademy
Open-Browser MDN             # Opens single URL
```

## Mixed Arrays

A group can contain **both** named URLs and nested sub-groups at the same level. This is useful when a group has individual URLs alongside categorized sub-groups:

```powershell
BrowserGroups = @(
    @{ Server = @(
        @{ DomainLinks = @(
            @{ Name = "Homepage"; Url = "https://homepage.example.com" }
            @{ Name = "Proxmox"; Url = "https://proxmox.example.com" }
            @{ Name = "TrueNAS"; Url = "https://truenas.example.com" }
            @{ ArrStack = @(
                @{ Name = "Sonarr"; Url = "https://sonarr.example.com" }
                @{ Name = "Radarr"; Url = "https://radarr.example.com" }
                @{ Name = "Prowlarr"; Url = "https://prowlarr.example.com" }
            )}
        )}
    )}
)
```

Usage:

```powershell
Open-Browser DomainLinks    # Opens ALL URLs (Homepage + Proxmox + TrueNAS + ArrStack)
Open-Browser ArrStack       # Opens only Sonarr + Radarr + Prowlarr
Open-Browser Homepage       # Opens single URL
```

> [!NOTE]
> Mixed arrays are fully backwards compatible. Groups that use only named URLs or only nested sub-groups continue to work unchanged.

## Using Groups in Workspaces

Reference groups in workspace actions:

```powershell
WorkspaceActions = @{
    WORKSTATION-01 = @(
        @{ Action = "Open-Browser"; Parameters = @{ Groups = @("AI", "GitHub", "Seq") } }
    )
    Learning = @(
        @{ Action = "Open-Browser"; Parameters = @{ Groups = @("Learning", "Documentation") } }
    )
}
```

## Interactive Menu

When called without arguments, shows interactive menu:

```powershell
Open-Browser
```

Shows:

```
═══════════════════════════════════════════════════════════════
Available Browser Groups
═══════════════════════════════════════════════════════════════
1. AI
   1.1. ChatGPT
   1.2. Claude
   1.3. Perplexity
2. GitHub
   2.1. Personal
        2.1.1. PersonalProfile
        2.1.2. WinuXRepo
   2.2. Work
        ...
───────────────────────────────────────────────────────────────
Selection (number or name):
```

## Search Functionality

Use `-Search` for web searches:

```powershell
Open-Browser -Search "PowerShell tutorials"
Open-Browser -Search "how to use FancyZones"
```

Combined with groups and private mode:

```powershell
Open-Browser -Private -Search "sensitive query"
```

## Browser Selection

Specify browser with `-Browser`:

```powershell
Open-Browser AI -Browser Chrome
Open-Browser AI -Browser Edge
Open-Browser AI -Browser Brave
Open-Browser AI -Browser Tor       # Tor Browser
```

Default browser is configured in:

```powershell
Universal = @{
    DefaultBrowser = "Firefox"
}
```

## Complete Example

Adding a "Monitoring" group:

```powershell
BrowserGroups = @(
    # Existing groups...

    @{ Monitoring = @(
        @{ Local = @(
            @{ Name = "Seq"; Url = "http://localhost:5341/#/events" }
            @{ Name = "Grafana"; Url = "http://localhost:3000" }
            @{ Name = "Prometheus"; Url = "http://localhost:9090" }
        )}
        @{ Cloud = @(
            @{ Name = "AzurePortal"; Url = "https://portal.azure.com" }
            @{ Name = "AppInsights"; Url = "https://portal.azure.com/#blade/HubsExtension/BrowseResource/resourceType/microsoft.insights%2Fcomponents" }
        )}
    )}
)
```

Usage:

```powershell
Open-Browser Monitoring    # Opens all 5 URLs
Open-Browser Local         # Opens Seq, Grafana, Prometheus
Open-Browser Cloud         # Opens Azure URLs
Open-Browser Seq           # Opens just Seq
```
