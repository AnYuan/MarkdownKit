# Third-Party Notices

MarkdownKit itself is licensed under the MIT License; see `LICENSE`.

This repository also redistributes third-party code and bundled resources. Checked-in
license/notice texts live under `ThirdParty/Licenses/`, the normalized machine-readable
Mermaid inventory lives under `ThirdParty/Inventories/`, and the release provenance lock
lives at `ThirdParty/provenance.lock.json`.

## Runtime and Bundled Dependencies

| Component | Scope | Exact source | License identifier | Checked-in notices / licenses | Notes |
| --- | --- | --- | --- | --- | --- |
| Mermaid `dist/mermaid.min.js` | Bundled runtime resource | `https://unpkg.com/mermaid@10.9.5/dist/mermaid.min.js` | MIT | `ThirdParty/Licenses/mermaid/LICENSE`, `ThirdParty/Licenses/mermaid/BUNDLE_NOTICES.txt`, `ThirdParty/Licenses/mermaid/THIRD_PARTY_LICENSE_REPORT.md` | Vendored at `Sources/MarkdownKit/Resources/mermaid.min.js`; SHA-256 `616a109f19cd186842e11d45b35ac07456b3a75513310f6ea075351aa430b1e2`. See the normalized inventory and consolidated Mermaid report linked below. |
| MathJaxSwift | Direct runtime package | `https://github.com/colinc86/MathJaxSwift.git` @ `e23d6eab941da699ac4a60fb0e60f3ba5c937459` (`3.4.0`) | MIT | `ThirdParty/Licenses/MathJaxSwift/LICENSE.md` | Used for MarkdownKit math rendering. |
| Splash | Direct runtime package | `https://github.com/JohnSundell/Splash.git` @ `7f4df436eb78fe64fe2c32c58006e9949fa28ad8` (`0.16.0`) | MIT | `ThirdParty/Licenses/Splash/LICENSE` | Used for Swift syntax highlighting. |
| SwiftDraw | Direct runtime package | `https://github.com/swhitty/SwiftDraw` @ `776456051ea2b099343e18ed8a53fca9dd2e9807` (`0.27.0`) | zlib | `ThirdParty/Licenses/SwiftDraw/LICENSE.txt` | Used by the math SVG pipeline. |
| swift-markdown | Direct runtime package | `https://github.com/swiftlang/swift-markdown.git` @ `3c6f9523da3a1ec2fd829673e472d95b8097a3b8` (`0.8.0`) | Apache-2.0 with Swift Runtime Library Exception | `ThirdParty/Licenses/swift-markdown/LICENSE.txt`, `ThirdParty/Licenses/swift-markdown/NOTICE.txt` | Public Markdown parser dependency. Upstream NOTICE is preserved verbatim. |
| swift-cmark | Transitive runtime package via swift-markdown | `https://github.com/swiftlang/swift-cmark.git` @ `924936d0427cb25a61169739a7660230bffa6ea6` (`0.8.0`) | BSD-2-Clause + MIT + CC-BY-SA-4.0 notices (see COPYING) | `ThirdParty/Licenses/swift-cmark/COPYING` | `COPYING` is retained verbatim because it includes multiple required notices, including derived MIT code and CommonMark spec attribution. |

## Mermaid bundled third-party closure

MarkdownKit vendors the official Mermaid `10.9.5` monolithic UMD bundle. The checked-in
provenance records that the published npm artifact and a frozen-lock rebuild from tag
`v10.9.5` / commit `665b3d05cbe1ac7b78b154a464de39c5d17ba7b9` are byte-identical:
SHA-256 `616a109f19cd186842e11d45b35ac07456b3a75513310f6ea075351aa430b1e2`, 3,338,725 bytes.

Authoritative checked-in Mermaid provenance artifacts:

- `ThirdParty/Inventories/mermaid-10.9.5-umd-bundled-inventory.json` — deterministic 62-package inventory derived from the frozen production closure and matching Rollup UMD module map
- `ThirdParty/Licenses/mermaid/THIRD_PARTY_LICENSE_REPORT.md` — consolidated source / license / notice report covering all 62 bundled package instances
- `ThirdParty/Licenses/mermaid/BUNDLE_NOTICES.txt` — the six exact license-bearing comments preserved from the published UMD bundle

Bundled package counts:

- 62 bundled package instances
- 16 direct + 46 transitive bundled instances
- 3 bundled via prebuilt sub-bundles (`heap`, `lodash`, `web-worker`)
- 46 production-closure packages excluded as non-bundled

| License identifier | Bundled package count |
| --- | ---: |
| MIT | 36 |
| ISC | 18 |
| BSD-3-Clause | 5 |
| Apache-2.0 | 1 |
| EPL-2.0 | 1 |
| (MPL-2.0 OR Apache-2.0) | 1 |

Additional Mermaid closure notes:

- `khroma@2.1.0` is normalized to MIT from its shipped `license` file; its package metadata omits a license field.
- `dompurify@3.2.4` remains recorded as `(MPL-2.0 OR Apache-2.0)`; MarkdownKit elects Apache-2.0 for redistribution.
- `BUNDLE_NOTICES.txt` is **not** the complete dependency closure. It only preserves the six exact license-bearing comments emitted by the published UMD; the normalized inventory and consolidated report own the full 62-package closure.

## MathJaxSwift Embedded Component Inventory

MathJaxSwift `3.4.0` commits generated MathJax resources whose package inventory is pinned by its
upstream `Sources/MathJaxSwift/Resources/mjn/package-lock.json`.

Inventory source:
`https://raw.githubusercontent.com/colinc86/MathJaxSwift/e23d6eab941da699ac4a60fb0e60f3ba5c937459/Sources/MathJaxSwift/Resources/mjn/package-lock.json`

Generated bundle notices retained verbatim:

- `ThirdParty/Licenses/MathJaxSwift-embedded/generated/chtml.bundle.js.LICENSE.txt`
- `ThirdParty/Licenses/MathJaxSwift-embedded/generated/mml.bundle.js.LICENSE.txt`
- `ThirdParty/Licenses/MathJaxSwift-embedded/generated/svg.bundle.js.LICENSE.txt`

Those generated notice files surface the bundled `mhchemparser` Apache-2.0 notice and are kept
verbatim for redistribution.

| Embedded component | Exact upstream package | License identifier | Checked-in notices / licenses | Notes |
| --- | --- | --- | --- | --- |
| commander | `https://registry.npmjs.org/commander/-/commander-9.2.0.tgz` | MIT | `ThirdParty/Licenses/MathJaxSwift-embedded/commander/LICENSE` | Transitive runtime dependency of `speech-rule-engine`. |
| esm | `https://registry.npmjs.org/esm/-/esm-3.2.25.tgz` | MIT | `ThirdParty/Licenses/MathJaxSwift-embedded/esm/LICENSE` | Runtime dependency of `mathjax-full`. |
| mathjax-full | `https://registry.npmjs.org/mathjax-full/-/mathjax-full-3.2.2.tgz` | Apache-2.0 | `ThirdParty/Licenses/MathJaxSwift-embedded/mathjax-full/LICENSE` | Primary JavaScript math engine bundled by MathJaxSwift. |
| mhchemparser | `https://registry.npmjs.org/mhchemparser/-/mhchemparser-4.2.1.tgz` | Apache-2.0 | `ThirdParty/Licenses/MathJaxSwift-embedded/mhchemparser/LICENSE.txt`; generated bundle notices above | `mhchemparser`'s generated-bundle notice is preserved exactly as emitted upstream. |
| mj-context-menu | `https://registry.npmjs.org/mj-context-menu/-/mj-context-menu-0.6.1.tgz` | Apache-2.0 | `ThirdParty/Licenses/MathJaxSwift-embedded/mathjax-full/LICENSE` | The authoritative license identifier comes from `https://registry.npmjs.org/mj-context-menu/0.6.1`; that tarball does not ship a separate license file, so the Apache-2.0 text is indexed here via the exact `mathjax-full` copy already bundled in the same generated stack. |
| speech-rule-engine | `https://registry.npmjs.org/speech-rule-engine/-/speech-rule-engine-4.0.7.tgz` | Apache-2.0 | `ThirdParty/Licenses/MathJaxSwift-embedded/speech-rule-engine/LICENSE` | Provides speech/accessibility rules. |
| wicked-good-xpath | `https://registry.npmjs.org/wicked-good-xpath/-/wicked-good-xpath-1.3.0.tgz` | MIT | `ThirdParty/Licenses/MathJaxSwift-embedded/wicked-good-xpath/LICENSE` | Transitive runtime dependency of `speech-rule-engine`. |
| xmldom-sre | `https://registry.npmjs.org/xmldom-sre/-/xmldom-sre-0.1.31.tgz` | `(LGPL-2.0 or MIT)` | `ThirdParty/Licenses/MathJaxSwift-embedded/xmldom-sre/LICENSE` | License identifier is preserved exactly as published by the authoritative npm package metadata. |

## Test and Development-Only Dependencies

| Component | Scope | Exact source | License identifier | Checked-in notices / licenses | Notes |
| --- | --- | --- | --- | --- | --- |
| swift-snapshot-testing | Direct test dependency | `https://github.com/pointfreeco/swift-snapshot-testing.git` @ `bf8d8c27f0f0c6d5e77bff0db76ab68f2050d15d` (`1.18.9`) | MIT | `ThirdParty/Licenses/swift-snapshot-testing/LICENSE` | Used only by test and snapshot suites. |
| swift-custom-dump | Transitive test dependency via swift-snapshot-testing | `https://github.com/pointfreeco/swift-custom-dump` @ `2a2a938798236b8fa0bc57c453ee9de9f9ec3ab0` (`1.4.1`) | MIT | `ThirdParty/Licenses/swift-custom-dump/LICENSE` | Test-only helper dependency. |
| swift-syntax | Transitive test dependency via swift-snapshot-testing | `https://github.com/swiftlang/swift-syntax` @ `4799286537280063c85a32f09884cfbca301b1a1` (`602.0.0`) | Apache-2.0 with Swift Runtime Library Exception | `ThirdParty/Licenses/swift-syntax/LICENSE.txt` | Test-only syntax dependency of swift-snapshot-testing. |
| xctest-dynamic-overlay | Transitive test dependency via swift-snapshot-testing | `https://github.com/pointfreeco/xctest-dynamic-overlay` @ `dfd70507def84cb5fb821278448a262c6ff2bbad` (`1.9.0`) | MIT | `ThirdParty/Licenses/xctest-dynamic-overlay/LICENSE` | Test-only helper dependency. |

## Machine-Readable Provenance

For deterministic review and CI drift detection, consult `ThirdParty/provenance.lock.json`. The
lock records the exact `Package.swift` / `Package.resolved` policy, the vendored Mermaid artifact
metadata, the checked-in Mermaid inventory/report hashes, every checked-in license/notice file
hash, and the MathJaxSwift embedded component inventory.
