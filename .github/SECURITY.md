# Security Policy

## Supported versions

AltCast is a community project. Security fixes are applied to the latest release; older builds are not patched. Always upgrade to the latest version before reporting.

## Reporting a vulnerability

**Do not** open a public GitHub issue for security reports.

Instead, use GitHub's [private vulnerability reporting](https://github.com/filipefilardi/altsound/security/advisories/new) form, or email the maintainer directly. Include:

- A description of the issue and its impact
- Steps to reproduce (or a proof-of-concept)
- Affected platforms and AltCast versions
- Suggested fix if you have one

We'll keep you posted as the fix lands and credit you in the release notes if you'd like.

## Scope

AltCast is a Jellyfin client. In-scope vulnerabilities include:

- Local credential or token leakage (logs, exported files, screenshots)
- Insecure storage of credentials
- Privilege escalation on the device
- Bugs that send credentials or tokens to unintended endpoints
- Cache or download path traversal

Out of scope:

- Vulnerabilities in Jellyfin itself — report those to the [Jellyfin project](https://github.com/jellyfin/jellyfin/security/policy)
- Vulnerabilities in third-party dependencies — please report upstream, but feel free to also let us know so we can pin / update
- Issues that require physical device access plus an already-unlocked device
