# Mozilla Readability

- Upstream: https://github.com/mozilla/readability
- Fixed commit: `ab4027a8b37669745016869a37a504727992b2ba`
- Imported file: `Readability.js`
- License: Apache License 2.0, preserved in `LICENSE.md`
- Imported on: 2026-08-10

## Local integration boundary

The upstream JavaScript source is stored without local source modifications.
`WebArticleExtractionHost.swift` loads it inside a non-persistent `WKWebView`
whose page JavaScript is disabled. The application injects a restrictive
Content Security Policy before parsing and uses only the extracted article
title and plain text.

The rest of the Mozilla repository, its Node.js tooling, tests and package
dependencies are not included in the application.

## Integrity

- `Readability.js` SHA-256: `e9330028c8a5a4aa7d75147be2605d520f7f213c7b28474947dc0e9c984e9bed`
- `LICENSE.md` SHA-256: `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30`
