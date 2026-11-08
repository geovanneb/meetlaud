# Security policy

Meetlaud's promise is that meeting content never leaves the device unless the person sends it, and then only to a computer they paired. A way to break that promise is a security issue, even if it looks minor.

## Reporting

Please use [GitHub private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability) on this repository. Do not open a public issue.

Please include the steps to reproduce, the app version, and the impact.

## In scope

- Any network connection outside the model download flow and a connector the person paired
- Weaknesses in connector pairing or encryption (see `docs/connectors.md`)
- User data reaching logs, backups, or other apps against the user's settings
- Model files passing verification after tampering
- Bypassing the app lock
- Meeting content causing the app to act without the user's confirmation
- A URL or other app starting the microphone

## Supported versions

The latest release and the `main` branch get security fixes.
