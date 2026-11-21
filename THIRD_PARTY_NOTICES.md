# Third-party notices

SwiftUIWeb's own source is licensed under the Mozilla Public License 2.0 (see [LICENSE](LICENSE)). This file lists what
else is in the repository or in the bundles it builds, under which license, and the notices those licenses ask to keep.
Licenses that are not MPL-2.0 apply to the parts named here, not to the rest of the repository.

## In the repository, under another license

| Path | What it is | License |
| --- | --- | --- |
| `Examples/FoodTruck` | The Food Truck sample app and its assets, © 2023 Apple Inc., adapted to run with SwiftUIWeb | MIT-style permission notice in [`Examples/FoodTruck/LICENSE.txt`](Examples/FoodTruck/LICENSE.txt) |
| `.agents/skills/*` | Third-party agent skills; each directory that carries a `LICENSE.txt` is under that license (Apache-2.0 for the two that ship one) | per directory |

## Inside built bundles and apps

Code or data from these is part of what `make run` and an application's release build produce.

### Lucide and Feather icons

`Sources/SwiftUIWebBrowser/LucideIcons.swift` carries the SVG shapes of the [Lucide](https://lucide.dev) icons that the
SF Symbol catalog maps to, and the build copies the ones an application uses into its `icon-adapter.js`.

ISC License

Copyright (c) for portions of Lucide are held by Cole Bemis 2013-2022 as part of Feather (MIT).
All other copyright (c) for Lucide are held by Lucide Contributors 2022.

Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted,
provided that the above copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF
THIS SOFTWARE.

### Tailwind CSS preflight

Tailwind CSS is not a dependency of the build. The reset in `@layer base` of `Tools/styles.css` was adapted from its preflight and the adapted rules stay in the stylesheet, so the MIT notice stays with them.

MIT License. Copyright (c) Tailwind Labs, Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
documentation files (the "Software"), to deal in the Software without restriction, including without limitation the
rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit
persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the
Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

### Swift standard library and runtime

An Embedded build links parts of the Swift standard library and runtime into `app.wasm`. They are Apache-2.0 with the
Runtime Library Exception, which asks for no attribution in the compiled output.

## Pulled in by the packages that use them

These are fetched by SwiftPM or Bun when a consumer builds the product that needs them; none is stored in this repository.

| Component | Used by | License |
| --- | --- | --- |
| [swift-crypto](https://github.com/apple/swift-crypto) 4.3.1 and [swift-asn1](https://github.com/apple/swift-asn1) 1.7.3 | `SwiftUIWebCrypto` and the products that depend on it | Apache-2.0 |
| [shaka-player](https://github.com/shaka-project/shaka-player) 5.3.4 | Adaptive media (`SwiftUIWebAVFoundation`); bundled into `shaka-loader.js` for the apps that use it | Apache-2.0 |
| [lottie-web](https://github.com/airbnb/lottie-web) 5.13.0 | Lottie animations (`SwiftUIWebMotion`); its light SVG player is bundled into `lottie-loader.js` for the apps that use it | MIT |

The Apache License 2.0 text is in [LICENSES/Apache-2.0.txt](LICENSES/Apache-2.0.txt). Shaka Player ships
under it; keep its copyright notice with any bundle that contains it.

## Development tools, not distributed

Playwright (Apache-2.0), Bun, the Swift toolchain and Binaryen run on the developer's machine, as does
[swift-syntax](https://github.com/swiftlang/swift-syntax) 604.0.0 (Apache-2.0 with the Runtime Library Exception), which the
source lowerer (`Tools/SwiftUIWebLowering`) is built on. Nothing from them ends up in a bundle.
