# PhotosPickerExample

The `PhotosPicker` from `SwiftUIWebPhotosUI`, in the browser: a file chooser that accepts images and videos. The app reads the
bytes of the chosen items asynchronously and reports how many it read.

```sh
make run photos-picker        # build and serve it (it prints the address)
```

The page has two pickers. The first picks one image or video. The second picks up to six items in the order they were chosen. After
a choice, the page shows the number of bytes read, and for the single item the name of the file.

What to look at in `main.swift`:

- `PhotosPicker(selection:matching:)` with `.any(of: .images, .videos)`, a filter that is passed to the browser's file input.
- `PhotosPicker(_:selection:maxSelectionCount:selectionBehavior:matching:)`, the multiple-selection form with `.ordered`.
- `.task(id:)` on the selection, which starts the loading each time the choice changes.
- `loadDataRepresentation(forTypeIdentifier:)`, the way the bytes are read. The comments explain why it is used instead of the generic
  `loadTransferable`.
