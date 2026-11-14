# Security policy

## Supported versions

SwiftUIWeb is before 1.0. Security fixes go into the latest release only; there are no backports to older versions.

## Reporting a vulnerability

Do not open a public issue, discussion or pull request for a vulnerability.

Report it privately through GitHub: on the repository page open **Security**, then **Report a vulnerability**. Describe
what an attacker can do, the version or commit, the browser, and the smallest application or steps that show it.

You will get an answer within seven days. Once a fix is ready it is released, and the advisory is published with credit
to you unless you ask otherwise.

## What the framework already protects against

[`Documentation/Security/WEB_SECURITY.md`](Documentation/Security/WEB_SECURITY.md) describes the browser-side model: the
Content Security Policy of built bundles, how the keychain stores secrets in IndexedDB, session and credential handling,
and the same-origin boundary of web content. A report that one of those guarantees does not hold is in scope. So is a
way for markup, a URL or data an application renders to run script in its page.
