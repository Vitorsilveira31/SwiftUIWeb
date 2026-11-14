# CloneKit

What the realistic example apps share: models and a typed client for the jsonplaceholder-shaped API, and the pictures the mock service
draws. Nothing here draws a view; each example keeps its own design.

- `Models/` the resources (`PlaceholderUser`, `PlaceholderPost`, `PlaceholderComment`, `PlaceholderAlbum`, `PlaceholderPhoto`, `PlaceholderTodo`).
- `Network/PlaceholderClient` the typed calls, through a `PlaceholderTransport` (`URLSessionTransport` in the app, a double in a test).
- `Network/PlaceholderImage` the paths of the pictures under `/api/images/`.

Every path starts with `/api`: the dev server forwards it to [`Tools/mock-jsonplaceholder.mjs`](../../Tools/mock-jsonplaceholder.mjs) for an example
with an `Examples/<Name>/.mock-api` marker. `API=real make run <name>` answers the data from jsonplaceholder.typicode.com instead.
Add a call to the client when an example needs one, with a test in `Tests/CloneKitTests`.
