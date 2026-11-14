# SecurityExample

A web keychain: the Keychain calls (`SecItemAdd`, `SecItemCopyMatching` and `SecItemDelete`) run in the browser through
`SwiftUIWebSecurity`, and the secret is stored encrypted. The page also shows the cookie jar from `SwiftUIWebNetworking`.

```sh
make run security             # build and serve it (it prints the address)
make security-browser-test    # build it and run Tools/test-security-browser.mjs on Chromium and WebKit
```

On the first load the page adds a secret and shows "Added". After a reload it finds the same secret and shows it. The Forget button
deletes the secret and shows "Forgotten". The bytes at rest are AES-GCM ciphertext in IndexedDB, and the test checks that.

The cookie line shows a cookie that a script may write, and not the `HttpOnly` one: the jar refuses the `HttpOnly` cookie from script,
so it never appears on the page.

What to look at in `main.swift`:

- `WebSecurity.unlock()`, called before any keychain call, and `WebSecurity.synchronize()`, called after a write or delete.
- The `query` dictionary for `kSecClassGenericPassword`, used by add, find and delete.
- `HTTPCookieStorage.shared` with `setCookie` and `observeChanges`, which keep the cookie line in step with the jar.
