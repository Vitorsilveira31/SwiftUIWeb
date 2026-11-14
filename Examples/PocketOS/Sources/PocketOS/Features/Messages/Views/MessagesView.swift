import SwiftUI

// Messages: the inbox, or one thread when the shell has a thread open.
struct MessagesView: View {
    let messages: MessagesViewModel
    let shell: ShellViewModel

    var body: some View {
        if let id = shell.state.openedThread {
            ThreadView(threadID: id, messages: messages, shell: shell)
        } else {
            InboxView(messages: messages, shell: shell)
        }
    }
}
