# Security Policy

WinuX is a system-provisioning tool for Windows 11. It is installed with a single command
that **downloads and executes a script with Administrator privileges**:

```powershell
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'; irm 'https://raw.githubusercontent.com/IvanPavlak/WinuX/master/Windows/PowerShell/Modules/Bootstrap/Install-Bootstrap.ps1' | iex
```

Because of this, we take the security of WinuX seriously and ask that you do too.

---

## Threat model

WinuX runs with the **highest privilege level on the machine** and performs broad,
state-changing operations. The trust boundary:

| Capability                                    | Why it matters                                                                                                                                           |
| --------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Runs as Administrator**                     | The bootstrap requires admin to create symlinks and reconfigure the OS. Any vulnerability is, by definition, privileged.                                 |
| **`irm \| iex` remote execution**             | The installer fetches a script over HTTPS and pipes it into the shell. Users trust GitHub/CDN integrity, the ref they pin, and the maintainer's account. |
| **Installs third-party software**             | Packages are installed via WinGet/Scoop/Chocolatey. A malicious or typosquatted package entry would run elevated.                                        |
| **Creates symbolic links & writes dotfiles**  | A path-handling bug could redirect a symlink to, or overwrite, an unintended location.                                                                   |
| **Clones repositories / uses tokens**         | Private-repo installs accept a GitHub PAT. Mishandling (logging, leaking) a token is a security issue.                                                   |
| **Sets execution policy & security protocol** | The installer adjusts `ExecutionPolicy`/TLS settings.                                                                                                    |

### In scope

- Remote code execution, privilege escalation, or arbitrary file write introduced by WinuX
  code (the bootstrap, modules, or `Configuration.psd1` handling).
- Command/script injection through configuration values, hostnames, paths, or placeholder
  expansion (`Expand-ConfigPaths`).
- Leakage of secrets (e.g. a GitHub PAT) into logs, console output, the clipboard, or
  committed files.
- Insecure download/verification logic (downgrade, missing TLS, unpinned refs).
- Symlink/path-traversal bugs that write outside intended directories.

### Out of scope

- Vulnerabilities in third-party software that WinuX merely installs (report those upstream),
  unless WinuX pins a known-malicious version.
- Issues that require an attacker to already have Administrator on the machine.
- The inherent risk of `irm | iex` itself - documented and mitigated by the "review before
  running" guidance below, not a bug.

---

## Supported versions

WinuX is a rolling-release tool installed from a Git branch; there are no long-lived release
lines. Security fixes are applied to `master` and the most recent tagged release.

| Version / ref        | Supported                             |
| -------------------- | ------------------------------------- |
| `master` (latest)    | :white_check_mark:                    |
| Latest release tag   | :white_check_mark:                    |
| Older tags / commits | :x:                                   |
| Forks                | :x: (report to the fork's maintainer) |

If you pinned an older commit or branch, update to the latest `master` before reporting, in
case the issue is already fixed.

---

## Reporting a vulnerability

**Please do NOT report security vulnerabilities through public GitHub issues, discussions, or
pull requests.**

Report privately using **GitHub Security Advisories**:

1. Go to the repository's **Security** tab.
2. Click **Report a vulnerability** to open a private
   [GitHub Security Advisory](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability).
3. Provide as much detail as you can:
    - A clear description of the vulnerability and its impact.
    - The affected file(s)/function(s) and ref/commit.
    - Step-by-step reproduction (a minimal `Configuration.psd1` snippet or command line is
      ideal).
    - Any proof-of-concept, logs, or screenshots (redact secrets such as tokens).

Please give us a reasonable opportunity to investigate and remediate before any public
disclosure. We support **coordinated disclosure** and will credit reporters (with permission).

### Response timeline

This is a personal project maintained in spare time; these are good-faith targets, not
contractual SLAs:

| Stage                                                | Target                                         |
| ---------------------------------------------------- | ---------------------------------------------- |
| Acknowledge your report                              | within **72 hours**                            |
| Initial assessment / triage                          | within **7 days**                              |
| Status update cadence                                | at least every **7 days** until resolved       |
| Fix or mitigation for confirmed high-severity issues | typically within **30 days**                   |
| Public advisory + credit                             | after a fix is released (coordinated with you) |

---

## Guidance for users - review scripts before running

WinuX intentionally uses `irm | iex` for convenience, but **executing a remote script as
Administrator is a powerful action.** Protect yourself:

- **Read the script before you run it.** Open
  [`Install-Bootstrap.ps1`](Windows/PowerShell/Modules/Bootstrap/Install-Bootstrap.ps1) and
  skim the modules before piping anything into `iex`.
- **Pin to a ref you have reviewed.** Prefer a specific tag or commit over `master` for
  byte-for-byte reproducibility, and re-review when you update.
- **Inspect `Configuration.psd1`** - it controls what software is installed, which symlinks
  are created, and which repos are cloned. Make it your own; don't run someone else's
  configuration blindly.
- **Never paste a token you don't control**, and never share a `Configuration.psd1` or
  bootstrap log that contains secrets.
- **Run in a VM or disposable machine first** if you are evaluating WinuX.
- **Use the official repository.** Only install from `https://github.com/IvanPavlak/WinuX`;
  be wary of forks or third-party gists.

If something about a script looks wrong, **stop and report it** before running it.
