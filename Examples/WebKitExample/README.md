# WebKitExample

An embedded web view from `SwiftUIWebWeb`. It shows two `WebContentView`s: one with HTML written in the app, and one with a
page on another origin. The app sees link navigations in the first one, and cannot read the DOM of the second.

```sh
make run webkit               # build and serve it (it prints the address)
```

The first view holds a small HTML page with a same-origin link. Each navigation updates the line above the views, and an external
link is handed to the system. The Back, Forward and Reload buttons drive the first view's history. The second view loads
`https://example.com`, which needs network access; the parent page can display it, but it cannot inspect its links or its DOM.

What to look at in `main.swift`:

- `WebContentModel(html:baseURL:)`, the state that holds the page and its history.
- `WebContentView(model:configuration:onNavigation:onExternalLink:)`, with `externalLinkBehavior: .openExternally`.
- `WebContentView(url:title:externalLinkBehavior:)`, the cross-origin form.
- `goBack()`, `goForward()`, `reload()` and `navigationState.isLoading`.
