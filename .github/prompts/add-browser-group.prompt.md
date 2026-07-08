---
description: "Add a new browser group to Configuration.psd1 using the Configuration module."
argument-hint: "Group name and URLs (e.g., 'DevTools with GitHub and StackOverflow')"
agent: "agent"
---

# Add Browser Group

Add a browser group to Configuration.psd1 using `Add-BrowserGroup`.

## Steps

1. Ask the user for:
    - **Group name** (must be unique across all browser groups)
    - **URLs** with labels (Name/Url pairs)
    - Whether it's a **simple** group (URL strings only) or **named** (recommended)

2. Call the configuration function:

```powershell
Add-BrowserGroup -GroupName "GroupName" -Urls @(
    @{ Name = "Label1"; Url = "https://..." }
    @{ Name = "Label2"; Url = "https://..." }
)
```

3. Read `AI/Instructions/ConfigurationPatterns.md` for format reference if needed.

## Rules from [ConfigurationPatterns.md](../../AI/Instructions/ConfigurationPatterns.md)

- Group names and URL names must be **globally unique**
- Named URLs are recommended over simple URL lists
- Nesting is supported for sub-groups
