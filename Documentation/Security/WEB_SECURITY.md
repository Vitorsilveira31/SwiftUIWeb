# Web keychain, storage and sessions

How SwiftUIWeb maps Apple's persistence APIs onto the browser, and what each mapping does and
does not guarantee. The framework assumes no deployment: no proxy, origin layout or server.

| Apple API | Browser backing | Who can read it |
|---|---|---|
| `UserDefaults`, `@AppStorage` | `localStorage` | any script in the origin, in plain text |
| `@SceneStorage` | `sessionStorage` (one tab) | any script in the origin, in plain text |
| `SecItem…` (`kSecClassGenericPassword`) | `WebSecurity`: Web Crypto + IndexedDB | any script in the origin, through `crypto.subtle` |
| Sign-in session | `HttpOnly`, `Secure`, `SameSite` cookie set by the server | the browser only; no script, no WASM |

## WebSecurity

`SwiftUIWebSecurity` keeps the Security.framework item API (`SecItemAdd`, `SecItemCopyMatching`,
`SecItemUpdate`, `SecItemDelete`, the `kSec…` keys, Apple's `errSec…` codes) over the strongest
mechanism a web page has. That mechanism is weaker than the Keychain, and the API does not pretend
otherwise.

### Storage layout

- One IndexedDB database per store, `swui:security:<name>` (default `keychain`), with one object
  store, `records`.
- `key`: a `CryptoKey`, AES-GCM 256, created by `crypto.subtle.generateKey` with
  `extractable: false` and the usages `encrypt` and `decrypt` only. IndexedDB stores the
  `CryptoKey` object itself; its bytes are never exposed to JavaScript.
- `item:<id>`: `{ v: 1, iv, sealed }` per item, where `sealed` is the AES-GCM ciphertext of the
  whole item (attributes such as service and account included, and the secret) under a fresh
  random 96-bit IV, with `<store name> NUL <id>` as additional authenticated data. A ciphertext
  copied onto another id fails authentication and is skipped, never returned.
- IndexedDB therefore reveals how many items exist, their sizes and their numeric ids, not their
  contents.
- The key is created on first use. Generation happens outside IndexedDB (Web Crypto cannot run
  inside a transaction); one read-write transaction then keeps a key that is already stored and
  saves the new one only if none is, so two tabs opening the store at the same time share one key.

### Who can use the key

Anything that runs JavaScript in the page's origin can open the database, obtain the same
`CryptoKey` and call `crypto.subtle.decrypt` with it: the application, a cross-site scripting
injection, a compromised dependency, a browser extension with access to the page. `extractable:
false` stops them from exporting or copying the key's bytes; it does not stop them from using the
key while they run. Other origins cannot open the database.

The key also lives in the browser profile on disk, protected by the operating system's user
account. Someone who copies the whole profile can expect to recover the items.

### Compared with the Keychain

| | Apple Keychain | WebSecurity |
|---|---|---|
| Key protection | device keys, Secure Enclave where present | non-extractable `CryptoKey` in the profile |
| Access control | per app, by code signature and entitlements | per origin; every script in it |
| Device lock (`kSecAttrAccessible…`) | enforced | stored, not enforced |
| Biometrics / user presence | `SecAccessControl` | not available |
| Synchronization | iCloud Keychain, opt-in | not available (`errSecUnimplemented`) |
| Lifetime | until deleted; survives app updates | until the site's data is cleared: private windows, storage pressure and browser retention policies can remove it |
| Use from a different tab or process | immediate | after the next `unlock()` |

Treat items as secrets the application can obtain again, not as the only copy. The protection that
matters most on the web is keeping foreign code out of the origin: a strict Content-Security-Policy
and few third-party scripts.

### Calls and their states

- `WebSecurity.unlock()` decrypts every item into memory; the synchronous `SecItem…` calls then
  answer from it, and each change is encrypted and written in the background, in order.
- Before `unlock()` finishes, or after `WebSecurity.lock()`: `errSecInteractionNotAllowed`.
- Without IndexedDB or Web Crypto (Web Crypto needs a secure context: HTTPS or localhost):
  `unlock()` throws `.unavailable` and the calls answer `errSecNotAvailable`.
- A failed write leaves the item in memory and sets `WebSecurity.lastPersistenceError`.
- `lock()` waits for pending writes and drops the decrypted items. Swift cannot overwrite the
  memory that held them, so it shortens how long plaintext stays reachable; it does not erase it.

### What crosses into Swift

Only plaintext the application stores or reads: values on `SecItemAdd`/`SecItemUpdate`, and every
item when `unlock()` decrypts the store (the synchronous API needs them in memory). Key material
never leaves Web Crypto. In the worker runtime the encryption runs in the worker, so plaintext does
not reach the page's main thread. Host diagnostics carry no item data.

## Sessions

Authentication state belongs to the server and the browser. The server sets an `HttpOnly`,
`Secure`, `SameSite` cookie; the browser stores it and attaches it to requests according to the
request's credentials mode. SwiftUIWeb never receives it: BrowserIO drops `Set-Cookie` before a
response reaches Swift. `HTTPCookieStorage.shared` (Foundation's API, provided on Embedded) is a view of the page's
own `document.cookie` through BrowserIO. It lists only the cookies script can see (HttpOnly cookies are invisible),
and `setCookie` writes script-visible cookies only: it refuses HttpOnly cookies, which script cannot write, and
does nothing under `cookieAcceptPolicy == .never`. The browser still decides what it stores.

- `URLSession` sends credentials same-origin (`WebCredentialsPolicy.sameOrigin`) by default. The
  application can change the mode in `SwiftUIWebWeb` with `URLSessionConfiguration.webCredentialsPolicy`
  for a whole session, or `URLRequest.webCredentialsPolicy` for one request:
  - `.sameOrigin` (default): cookies and credentials go only to the request's origin.
  - `.omit`: no cookies or HTTP credentials, even to the request's origin.
  - `.include`: cookies go cross-origin too. This is a deliberate exposure. Use it only for an origin
    you control, and make the server answer with a specific `Access-Control-Allow-Origin` and
    `Access-Control-Allow-Credentials: true`. SameSite rules still decide whether the browser sends a
    cookie on a cross-site request.

  `httpShouldSetCookies` on the configuration and `httpShouldHandleCookies` on a request turn cookies
  off whatever the mode is, by sending the request with `credentials: "omit"`. The modes are browser
  behavior; other hosts have no transport of their own (tests install one), so they do not apply there. Redirects are
  always followed by the browser; `URLSession` does not expose a manual or error redirect policy.
- `kSecClassInternetPassword` returns `errSecUnimplemented`: a session credential must not be an
  item the page can read.
- `WebSecurity.Session(statusURL:).state()` asks an endpoint the cookie authorizes and reports
  `.active`, `.signedOut` or `.unknown(status:)`. The endpoint must answer itself: the request refuses
  redirects, so a redirect to a sign-in page that answers 200 reads as `.unknown`, not `.active`.

Whether the API shares the page's origin, which `SameSite` value the cookie uses and how CORS is
configured are decisions of the application and its server, not of SwiftUIWeb.

### OAuth sign-in in a popup

An OAuth server can redirect a sign-in popup to `<base>oauth-callback?code=...`. That page writes its whole address to
Web Storage (`BrowserWebStorage`, namespace `oauth`, key `callback`) and closes; the application window reads it from
there. The address carries the authorization code, so the application:

- generates a random `state` before it opens the popup, keeps it, and refuses a callback whose `state` differs (another
  page can open the callback address too);
- removes the `callback` key as soon as it has read it, so the code does not stay in the browser's storage;
- exchanges the code at its own server, preferably with PKCE, since a page cannot keep a client secret.

SwiftUIWeb carries the address only; it does not generate or check `state`.

## Serving the bundle

The framework ships no server, so the headers that protect the page are the application's to send. The page's
Content-Security-Policy is a `<meta>` inside `index.html` (see `Documentation/BROWSER_APP_SHELL.md`); a few things
cannot be set from markup and belong in the server's response headers:

| Header | Why |
|---|---|
| `Content-Security-Policy: frame-ancestors 'none'` (or `'self'`) | Keeps another site from framing the app and tricking clicks. `frame-ancestors` is ignored in a `<meta>` policy. |
| `Strict-Transport-Security: max-age=63072000; includeSubDomains` | Web Crypto (`WebSecurity`) and `Secure` cookies need HTTPS; this keeps a first visit from being downgraded. |
| `X-Content-Type-Options: nosniff` | The development server sends it; send it in production too. |
| `Referrer-Policy: strict-origin-when-cross-origin` | Keeps paths and query strings of the app's routes out of the `Referer` sent to other origins. |
| `Permissions-Policy` | Turn off the features the app does not use (camera, microphone, geolocation) so an injected script cannot ask for them. |
| `Cross-Origin-Opener-Policy: same-origin` | Isolates the page from windows it opens or that open it. |

Serve `app.wasm` as `application/wasm`, compressed (Brotli), and let `index.html` answer every route without a file
extension (the app does its own routing). Do not load a script from a CDN without Subresource Integrity, and prefer
files served from the app's own origin, which the default policy already allows.
