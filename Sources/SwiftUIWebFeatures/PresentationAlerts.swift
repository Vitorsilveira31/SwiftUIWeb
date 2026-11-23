@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore

public extension View {
  // titleVisibility: .automatic hides the title as iOS action sheets do; the title still names the
  // dialog for assistive technology.
  nonisolated func confirmationDialog<Actions: View>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, @ViewBuilder actions: @escaping () -> Actions) -> some View {
    _modified(ConfirmationDialogModifier(title: titleKey.resolved, isPresented: isPresented, titleVisibility: titleVisibility, actions: actions))
  }

  nonisolated func confirmationDialog<Actions: View, Message: View>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, @ViewBuilder actions: @escaping () -> Actions, @ViewBuilder message: @escaping () -> Message) -> some View {
    _modified(ConfirmationDialogModifierWithMessage(title: titleKey.resolved, isPresented: isPresented, titleVisibility: titleVisibility, actions: actions, message: message))
  }

  nonisolated func confirmationDialog<Actions: View, T>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, presenting data: T?, @ViewBuilder actions: @escaping (T) -> Actions) -> some View {
    _modified(ConfirmationDialogModifier(title: titleKey.resolved, isPresented: _presentingBinding(isPresented, data), titleVisibility: titleVisibility, actions: _presenting(data, actions)))
  }

  nonisolated func confirmationDialog<Actions: View, Message: View, T>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, presenting data: T?, @ViewBuilder actions: @escaping (T) -> Actions, @ViewBuilder message: @escaping (T) -> Message) -> some View {
    _modified(ConfirmationDialogModifierWithMessage(title: titleKey.resolved, isPresented: _presentingBinding(isPresented, data), titleVisibility: titleVisibility, actions: _presenting(data, actions), message: _presenting(data, message)))
  }

  @_disfavoredOverload nonisolated func confirmationDialog<S: StringProtocol, Actions: View>(_ title: S, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, @ViewBuilder actions: @escaping () -> Actions) -> some View {
    _modified(ConfirmationDialogModifier(title: String(title), isPresented: isPresented, titleVisibility: titleVisibility, actions: actions))
  }

  @_disfavoredOverload nonisolated func confirmationDialog<S: StringProtocol, Actions: View, Message: View>(_ title: S, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, @ViewBuilder actions: @escaping () -> Actions, @ViewBuilder message: @escaping () -> Message) -> some View {
    _modified(ConfirmationDialogModifierWithMessage(title: String(title), isPresented: isPresented, titleVisibility: titleVisibility, actions: actions, message: message))
  }

  @_disfavoredOverload nonisolated func confirmationDialog<S: StringProtocol, Actions: View, T>(_ title: S, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, presenting data: T?, @ViewBuilder actions: @escaping (T) -> Actions) -> some View {
    _modified(ConfirmationDialogModifier(title: String(title), isPresented: _presentingBinding(isPresented, data), titleVisibility: titleVisibility, actions: _presenting(data, actions)))
  }

  @_disfavoredOverload nonisolated func confirmationDialog<S: StringProtocol, Actions: View, Message: View, T>(_ title: S, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, presenting data: T?, @ViewBuilder actions: @escaping (T) -> Actions, @ViewBuilder message: @escaping (T) -> Message) -> some View {
    _modified(ConfirmationDialogModifierWithMessage(title: String(title), isPresented: _presentingBinding(isPresented, data), titleVisibility: titleVisibility, actions: _presenting(data, actions), message: _presenting(data, message)))
  }

  nonisolated func confirmationDialog<Actions: View>(_ title: Text, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, @ViewBuilder actions: @escaping () -> Actions) -> some View {
    _modified(ConfirmationDialogModifier(title: title.value, isPresented: isPresented, titleVisibility: titleVisibility, actions: actions))
  }

  nonisolated func confirmationDialog<Actions: View, Message: View>(_ title: Text, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, @ViewBuilder actions: @escaping () -> Actions, @ViewBuilder message: @escaping () -> Message) -> some View {
    _modified(ConfirmationDialogModifierWithMessage(title: title.value, isPresented: isPresented, titleVisibility: titleVisibility, actions: actions, message: message))
  }

  nonisolated func confirmationDialog<Actions: View, T>(_ title: Text, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, presenting data: T?, @ViewBuilder actions: @escaping (T) -> Actions) -> some View {
    _modified(ConfirmationDialogModifier(title: title.value, isPresented: _presentingBinding(isPresented, data), titleVisibility: titleVisibility, actions: _presenting(data, actions)))
  }

  nonisolated func confirmationDialog<Actions: View, Message: View, T>(_ title: Text, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, presenting data: T?, @ViewBuilder actions: @escaping (T) -> Actions, @ViewBuilder message: @escaping (T) -> Message) -> some View {
    _modified(ConfirmationDialogModifierWithMessage(title: title.value, isPresented: _presentingBinding(isPresented, data), titleVisibility: titleVisibility, actions: _presenting(data, actions), message: _presenting(data, message)))
  }
}
