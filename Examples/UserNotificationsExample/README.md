# UserNotificationsExample

The `UserNotificationCenter` API from `SwiftUIWebUserNotifications`, in the browser: it asks for permission and shows a local
notification. Web Push is a separate opt-in extension. It needs a service worker and an application backend, and this example does
not use it.

```sh
make run notifications        # build and serve it (it prints the address)
```

The page shows the current permission when it opens. Request permission asks the browser for it, and the status text changes to the
new value. Show local notification is enabled only after permission is granted; it shows "Notification shown" when the browser
accepts it.

What to look at in `main.swift`:

- `UserNotificationCenter.current.authorizationStatus()` and `requestAuthorization(options:)`.
- `NotificationRequest` and `NotificationContent`, which build the local notification with a `userInfo` value.
- `.disabled(...)` on the two buttons, which follows the permission state.
- `.task(id:)` with a counter, which starts each action when its button is pressed.
