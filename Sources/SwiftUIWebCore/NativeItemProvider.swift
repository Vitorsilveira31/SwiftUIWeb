// Native builds use Foundation's `NSItemProvider` in the drag, drop and paste API, as SwiftUI does. SwiftUIWeb's own
// lazy item provider (DragDrop.swift) exists only on Embedded, where browser transfers are its delivery path.
//
// The members below are the SwiftUIWeb-internal surface the drag, drop and paste code calls, backed by Foundation's
// registration API. Every payload a native provider carries is a registered data representation that answers when
// it is requested; the representations of a runtime transfer (a paste) read the transfer runtime's payload.
