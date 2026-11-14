// This is the only platform import in the shared UI layer. The web package
// defines WEB; the Darwin Xcode project leaves it unset and uses
// Apple's SwiftUI. Everything below is ordinary SwiftUI-shaped source.
#if WEB
import SwiftUIWeb
#else
import SwiftUI
#endif

// MARK: - Settings model

public enum SettingsDestination: String, CaseIterable, Hashable, Identifiable, Sendable {
  case general
  case wiFi
  case bluetooth
  case cellular
  case personalHotspot
  case battery
  case vpn
  case accessibility
  case appearance
  case notifications
  case privacy

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .general: return "General"
    case .wiFi: return "Wi-Fi"
    case .bluetooth: return "Bluetooth"
    case .cellular: return "Cellular"
    case .personalHotspot: return "Personal Hotspot"
    case .battery: return "Battery"
    case .vpn: return "VPN"
    case .accessibility: return "Accessibility"
    case .appearance: return "Appearance"
    case .notifications: return "Notifications"
    case .privacy: return "Privacy & Security"
    }
  }

  public var summary: String {
    switch self {
    case .general: return "About, software update, storage, and device preferences"
    case .wiFi: return "Home Network"
    case .bluetooth: return "On"
    case .cellular: return ""
    case .personalHotspot: return "Allow others to join"
    case .battery: return "85%"
    case .vpn: return "Not Connected"
    case .accessibility: return ""
    case .appearance: return "Light"
    case .notifications: return ""
    case .privacy: return ""
    }
  }

  public var systemImage: String {
    switch self {
    case .general: return "gearshape"
    case .wiFi: return "wifi"
    case .bluetooth: return "bluetooth"
    case .cellular: return "antenna.radiowaves.left.and.right"
    case .personalHotspot: return "personalhotspot"
    case .battery: return "battery.100percent"
    case .vpn: return "globe"
    case .accessibility: return "accessibility"
    case .appearance: return "circle.lefthalf.filled"
    case .notifications: return "bell.badge"
    case .privacy: return "hand.raised"
    }
  }

  public var tint: Color {
    switch self {
    case .general: return .gray
    case .wiFi: return .blue
    case .bluetooth: return .blue
    case .cellular: return .green
    case .personalHotspot: return .green
    case .battery: return .green
    case .vpn: return .blue
    case .accessibility: return .blue
    case .appearance: return .black
    case .notifications: return .red
    case .privacy: return .orange
    }
  }

  public var searchText: String {
    [title, summary, rawValue].joined(separator: " ").lowercased()
  }

  public var group: SettingsGroup {
    switch self {
    case .general, .accessibility, .appearance, .notifications, .privacy:
      return .system
    case .wiFi, .bluetooth, .cellular, .personalHotspot, .battery, .vpn:
      return .connectivity
    }
  }
}

public enum SettingsGroup: String, CaseIterable, Hashable, Identifiable, Sendable {
  case connectivity
  case system

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .connectivity: return "Connectivity"
    case .system: return "System"
    }
  }
}

/// The selection is intentionally a small, typed value. `TabView` owns the
/// adaptive presentation: it is a bottom tab bar on compact iPhone-sized
/// windows, a top tab strip on iPadOS, and a sidebar on wide windows. Keeping
/// the value typed also lets the native and Embedded renderers share exactly
/// the same route model without URL or DOM plumbing in the example.
private enum SettingsTab: String, Hashable, CaseIterable {
  case overview
  case account
  case services
  case general
  case wiFi
  case bluetooth
  case cellular
  case personalHotspot
  case battery
  case vpn
  case accessibility
  case appearance
  case notifications
  case privacy

  var index: Int {
    switch self {
    case .overview: return 0
    case .account: return 1
    case .services: return 2
    case .general: return 3
    case .wiFi: return 4
    case .bluetooth: return 5
    case .cellular: return 6
    case .personalHotspot: return 7
    case .battery: return 8
    case .vpn: return 9
    case .accessibility: return 10
    case .appearance: return 11
    case .notifications: return 12
    case .privacy: return 13
    }
  }

  init(destination: SettingsDestination) {
    switch destination {
    case .general: self = .general
    case .wiFi: self = .wiFi
    case .bluetooth: self = .bluetooth
    case .cellular: self = .cellular
    case .personalHotspot: self = .personalHotspot
    case .battery: self = .battery
    case .vpn: self = .vpn
    case .accessibility: self = .accessibility
    case .appearance: self = .appearance
    case .notifications: self = .notifications
    case .privacy: self = .privacy
    }
  }
}

// MARK: - Shared entry point

/// The same root is used by the iOS/iPadOS Xcode target and the SwiftUIWeb
/// browser target. The modern sidebar-adaptable tab style supplies the
/// platform shell, so the example does not need a viewport check or a second
/// navigation implementation.
public struct SharedRootView: View {
  public init() {}

  public var body: some View {
    SettingsRootView()
      .background(Color.clear)
  }
}

public struct SettingsRootView: View {
  @State private var selectedTab = 0

  public init() {}

  public var body: some View {
    TabView(selection: $selectedTab) {
      Tab("Settings", systemImage: "gearshape", value: 0) {
        SettingsOverviewView(selectedTab: $selectedTab)
      }

      TabSection("Apple Account") {
        Tab("Apple Account", systemImage: "person.crop.circle", value: 1) {
          AccountSettingsView()
        }
        Tab("Services", systemImage: "shippingbox", value: 2) {
          ServicesSettingsView()
        }
      }

      TabSection("Connectivity") {
        Tab("Wi-Fi", systemImage: "wifi", value: 4) {
          WiFiSettingsView()
        }
        Tab("Bluetooth", systemImage: "bluetooth", value: 5) {
          SimpleSettingsView(destination: .bluetooth, message: "Choose a device to connect.")
        }
        Tab("Cellular", systemImage: "antenna.radiowaves.left.and.right", value: 6) {
          SimpleSettingsView(destination: .cellular, message: "Manage cellular data and roaming.")
        }
        Tab("Personal Hotspot", systemImage: "personalhotspot", value: 7) {
          SimpleSettingsView(destination: .personalHotspot, message: "Share this connection with nearby devices.")
        }
        Tab("Battery", systemImage: "battery.100percent", value: 8) {
          BatterySettingsView()
        }
        Tab("VPN", systemImage: "globe", value: 9) {
          SimpleSettingsView(destination: .vpn, message: "Add a VPN configuration to protect your connection.")
        }
      }

      TabSection("System") {
        Tab("General", systemImage: "gearshape", value: 3) {
          GeneralSettingsView()
        }
        Tab("Accessibility", systemImage: "accessibility", value: 10) {
          SimpleSettingsView(destination: .accessibility, message: "Make iPhone and iPad work better for you.")
        }
        Tab("Appearance", systemImage: "circle.lefthalf.filled", value: 11) {
          AppearanceSettingsView()
        }
        Tab("Notifications", systemImage: "bell.badge", value: 12) {
          SimpleSettingsView(destination: .notifications, message: "Choose how apps notify you.")
        }
        Tab("Privacy & Security", systemImage: "hand.raised", value: 13) {
          SimpleSettingsView(destination: .privacy, message: "Control access to your data and sensors.")
        }
      }
    }
    .tabViewStyle(.sidebarAdaptable)
    .background(Color.clear)
  }
}

// MARK: - iPhone landing screen

private struct SettingsOverviewView: View {
  @Binding var selectedTab: Int
  @State private var airplaneMode = false
  private let connectivityDestinations: [SettingsDestination] = [
    .wiFi,
    .bluetooth,
    .cellular,
    .personalHotspot,
    .battery,
    .vpn
  ]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text("Settings")
          .font(.largeTitle.weight(.bold))
          .padding(.horizontal, 4)

        Button {
          selectedTab = SettingsTab.account.index
        } label: {
          SettingsAccountCard()
        }
        .buttonStyle(.plain)
        .settingsDirectRowActionHoverEffect()
        .accessibilityIdentifier("settings-tab-\(SettingsTab.account.index)")

        SettingsCard {
          SettingsToggleRow(
            destination: .cellular,
            title: "Airplane Mode",
            symbol: "airplane",
            tint: .orange,
            isOn: $airplaneMode
          )
          SettingsDivider()
          ForEach(connectivityDestinations, id: \.rawValue) { destination in
            if destination != .wiFi {
              SettingsDivider()
            }
            SettingsOverviewLink(destination: destination, selectedTab: $selectedTab)
          }
        }

        SettingsCard {
          SettingsOverviewLink(destination: .general, selectedTab: $selectedTab)
          SettingsDivider()
          SettingsOverviewLink(destination: .accessibility, selectedTab: $selectedTab)
          SettingsDivider()
          SettingsOverviewLink(destination: .appearance, selectedTab: $selectedTab)
          SettingsDivider()
          SettingsOverviewLink(destination: .notifications, selectedTab: $selectedTab)
          SettingsDivider()
          SettingsOverviewLink(destination: .privacy, selectedTab: $selectedTab)
        }

        Text("Settings Demo")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .center)
          .padding(.bottom, 12)
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 24)
      .frame(maxWidth: 760, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .center)
    }
    .navigationTitle("Settings")
    .navigationBarTitleDisplayMode(.large)
  }
}

private struct SettingsOverviewLink: View {
  let destination: SettingsDestination
  @Binding var selectedTab: Int

  var body: some View {
    Button {
      selectedTab = SettingsTab(destination: destination).index
    } label: {
      SettingsRowLabel(destination: destination, showsSummary: true)
    }
    .foregroundStyle(.primary)
    .buttonStyle(.plain)
    .settingsDirectRowActionHoverEffect()
    .accessibilityIdentifier("settings-tab-\(SettingsTab(destination: destination).index)")
  }
}

// MARK: - Detail screens

private struct WiFiSettingsView: View {
  @State private var wiFiEnabled = true
  @State private var connectivityAssist = true

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        SettingsHero(destination: .wiFi, description: "Connect to Wi-Fi, view available networks, and manage settings for joining networks and nearby hotspots.")

        SettingsCard {
          SettingsToggleRow(
            destination: .wiFi,
            title: "Wi-Fi",
            symbol: "wifi",
            tint: .blue,
            isOn: $wiFiEnabled
          )
          SettingsDivider()
          SettingsNetworkRow(name: "Home Network", connected: wiFiEnabled, secured: true)
        }

        Text("Other Networks")
          .font(.headline)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 4)

        SettingsCard {
          SettingsNetworkRow(name: "Cafe Guest", connected: false, secured: false)
          SettingsDivider()
          SettingsNetworkRow(name: "Neighbor 5G", connected: false, secured: true)
          SettingsDivider()
          SettingsNetworkRow(name: "Other…", connected: false, secured: false)
        }

        SettingsCard {
          SettingsToggleRow(
            destination: .cellular,
            title: "Connectivity Assist",
            subtitle: "1.08 GB",
            symbol: "antenna.radiowaves.left.and.right",
            tint: .green,
            isOn: $connectivityAssist,
            showsIcon: false
          )
          SettingsDivider()
          Button("Reset Data Usage") {}
            .foregroundStyle(Color.accentColor)
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        Text("Use cellular data in addition to Wi-Fi for a more reliable internet connection. Learn more…")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 4)
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 24)
      .frame(maxWidth: 840, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .center)
    }
    .navigationTitle("Wi-Fi")
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button("Edit") {}
      }
    }
  }
}

private struct GeneralSettingsView: View {
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        SettingsHero(destination: .general, description: "Manage your overall setup and preferences for iPhone and iPad, such as software updates, device language, AirDrop, and more.")

        SettingsCard {
          SettingsDetailLink(title: "About", symbol: "info.circle", tint: .gray)
          SettingsDivider()
          SettingsDetailLink(title: "Software Update", symbol: "arrow.down.circle", tint: .gray)
          SettingsDivider()
          SettingsDetailLink(title: "iPad Storage", symbol: "internaldrive", tint: .gray)
        }

        SettingsCard {
          SettingsDetailLink(title: "AppleCare & Warranty", symbol: "apple.logo", tint: .red)
        }

        SettingsCard {
          SettingsDetailLink(title: "AirDrop", symbol: "dot.radiowaves.left.and.right", tint: .blue)
          SettingsDivider()
          SettingsDetailLink(title: "AirPlay & Continuity", symbol: "airplayvideo", tint: .blue)
          SettingsDivider()
          SettingsDetailLink(title: "Screen Capture", symbol: "record.circle", tint: .gray)
        }

        SettingsCard {
          SettingsDetailLink(title: "AutoFill & Passwords", symbol: "key.fill", tint: .gray)
          SettingsDivider()
          SettingsDetailLink(title: "Background App Refresh", symbol: "arrow.clockwise", tint: .gray)
          SettingsDivider()
          SettingsDetailLink(title: "Date & Time", symbol: "calendar", tint: .blue)
          SettingsDivider()
          SettingsDetailLink(title: "Dictionary", symbol: "book", tint: .blue)
        }
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 24)
      .frame(maxWidth: 840, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .center)
    }
    .navigationTitle("General")
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button("Edit") {}
      }
    }
  }
}

private struct SimpleSettingsView: View {
  let destination: SettingsDestination
  let message: String
  @State private var enabled = true

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        SettingsHero(destination: destination, description: message)
        SettingsCard {
          SettingsToggleRow(
            destination: destination,
            title: destination.title,
            symbol: destination.systemImage,
            tint: destination.tint,
            isOn: $enabled
          )
          SettingsDivider()
          Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 24)
      .frame(maxWidth: 840, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .center)
    }
    .navigationTitle(destination.title)
  }
}

private struct BatterySettingsView: View {
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        SettingsHero(destination: .battery, description: "See battery usage and charging information.")
        SettingsCard {
          SettingsDetailLink(title: "Battery Percentage", symbol: "percent", tint: .green)
          SettingsDivider()
          SettingsDetailLink(title: "Battery Health & Charging", symbol: "battery.100percent", tint: .green)
        }
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 24)
      .frame(maxWidth: 840, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .center)
    }
    .navigationTitle("Battery")
  }
}

private struct AppearanceSettingsView: View {
  @State private var useDarkAppearance = false

  var body: some View {
    Form {
      Section("Appearance") {
        Toggle("Dark Appearance", isOn: $useDarkAppearance)
        Text(useDarkAppearance ? "Dark" : "Light")
          .foregroundStyle(.secondary)
      }
      Section("Options") {
        SettingsDetailLink(title: "Wallpaper", symbol: "photo", tint: .blue)
        SettingsDetailLink(title: "Display & Brightness", symbol: "sun.max", tint: .orange)
      }
    }
    .navigationTitle("Appearance")
    .preferredColorScheme(useDarkAppearance ? .dark : .light)
  }
}

private struct AccountSettingsView: View {
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        SettingsAccountCard()
        SettingsCard {
          SettingsDetailLink(title: "Personal Information", symbol: "person", tint: .blue)
          SettingsDivider()
          SettingsDetailLink(title: "Password & Security", symbol: "lock.shield", tint: .green)
          SettingsDivider()
          SettingsDetailLink(title: "iCloud", symbol: "icloud", tint: .blue)
        }
      }
      .padding(20)
      .frame(maxWidth: 760, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .center)
    }
    .navigationTitle("Apple Account")
  }
}

private struct ServicesSettingsView: View {
  var body: some View {
    Form {
      Section("Services Included with Purchase") {
        SettingsDetailLink(title: "Apple Music", symbol: "music.note", tint: .red)
        SettingsDetailLink(title: "iCloud+", symbol: "icloud", tint: .blue)
        SettingsDetailLink(title: "Apple TV+", symbol: "tv", tint: .red)
      }
    }
    .navigationTitle("Services")
  }
}

// MARK: - Reusable visual primitives

private struct SettingsIcon: View {
  let destination: SettingsDestination
  let size: Double

  init(destination: SettingsDestination, size: Double = 42) {
    self.destination = destination
    self.size = size
  }

  var body: some View {
    Image(systemName: destination.systemImage)
      .font(.body.weight(.semibold))
      .foregroundStyle(.white)
      .frame(width: size, height: size)
      .background(destination.tint)
      .cornerRadius(size * 0.22)
      .accessibilityLabel(destination.title)
  }
}

private struct SettingsAccountCard: View {
  var compact = false

  var body: some View {
    HStack(spacing: compact ? 10 : 14) {
      ZStack {
        Circle()
          .fill(LinearGradient(colors: [.cyan, .teal], startPoint: .top, endPoint: .bottom))
        Image(systemName: "person.fill")
          .font(compact ? .title3 : .title)
          .foregroundStyle(.white)
      }
      .frame(width: compact ? 42 : 62, height: compact ? 42 : 62)

      VStack(alignment: .leading, spacing: 3) {
        Text("Jane Appleseed")
          .font(compact ? .headline : .title3.weight(.semibold))
        Text("Apple Account, iCloud+, and more")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(compact ? 2 : 1)
      }
      Spacer(minLength: 0)
      Image(systemName: "chevron.right")
        .font(.caption.weight(.bold))
        .foregroundStyle(.secondary)
    }
    .padding(compact ? 4 : 16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.primary.opacity(0.06))
    .clipShape(RoundedRectangle(cornerRadius: compact ? 12 : 22))
    // Apply the stretch after the background wrapper as well. This keeps the
    // card full-width inside a leading-aligned settings column on WebKit and
    // SwiftUIWeb, matching SwiftUI's layout proposal on iPad.
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
  }
}

private struct SettingsHero: View {
  let destination: SettingsDestination
  let description: String

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      SettingsIcon(destination: destination, size: 58)
      Text(destination.title)
        .font(.largeTitle.weight(.bold))
      Text(description)
        .font(.body)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Button("Learn more…") {}
        .foregroundStyle(Color.accentColor)
        .buttonStyle(.plain)
    }
    .padding(16)
    .background(Color.primary.opacity(0.06))
    .clipShape(RoundedRectangle(cornerRadius: 22))
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct SettingsCard<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    VStack(spacing: 0) {
      content
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 4)
    // The width proposal must be applied after padding and before the
    // background wrapper; otherwise a leading-aligned parent shrink-wraps the
    // background to its intrinsic row content on the browser renderer.
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.primary.opacity(0.06))
    .clipShape(RoundedRectangle(cornerRadius: 22))
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct SettingsRowLabel: View {
  let destination: SettingsDestination
  let showsSummary: Bool

  var body: some View {
    HStack(spacing: 12) {
      SettingsIcon(destination: destination)
      VStack(alignment: .leading, spacing: 3) {
        Text(destination.title)
          .font(.body)
        if showsSummary && !destination.summary.isEmpty {
          Text(destination.summary)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      Spacer(minLength: 0)
      Image(systemName: "chevron.right")
        .font(.caption.weight(.bold))
        .foregroundStyle(.secondary)
    }
    .padding(.vertical, 10)
    .contentShape(Rectangle())
  }
}

private struct SettingsToggleRow: View {
  let destination: SettingsDestination
  let title: String
  var subtitle: String? = nil
  let symbol: String
  let tint: Color
  @Binding var isOn: Bool
  var showsIcon = true

  var body: some View {
    HStack(spacing: 12) {
      if showsIcon {
        Image(systemName: symbol)
          .font(.body.weight(.semibold))
          .foregroundStyle(.white)
          .frame(width: 42, height: 42)
          .background(tint)
          .cornerRadius(11)
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
        if let subtitle {
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 8)
      Toggle("", isOn: $isOn)
        .labelsHidden()
        .tint(.green)
    }
    .padding(.vertical, 10)
    .contentShape(Rectangle())
  }
}

private struct SettingsNetworkRow: View {
  let name: String
  let connected: Bool
  let secured: Bool

  var body: some View {
    HStack(spacing: 12) {
      if connected {
        Image(systemName: "checkmark")
          .foregroundStyle(Color.accentColor)
          .font(.body.weight(.bold))
          .frame(width: 20)
      } else {
        Spacer().frame(width: 20)
      }
      Text(name)
        .frame(maxWidth: .infinity, alignment: .leading)
      if secured {
        Image(systemName: "lock.fill")
          .font(.caption)
      }
      Image(systemName: "wifi")
        .font(.caption)
      Image(systemName: "info.circle")
        .foregroundStyle(Color.accentColor)
    }
    .padding(.vertical, 10)
    .accessibilityLabel(name)
  }
}

private struct SettingsDetailLink: View {
  let title: String
  let symbol: String
  let tint: Color

  var body: some View {
    Button(action: {}) {
      HStack(spacing: 12) {
        Image(systemName: symbol)
          .font(.body.weight(.semibold))
          .foregroundStyle(.white)
          .frame(width: 28, height: 28)
          .background(tint)
          .cornerRadius(8)
        Text(title)
          .foregroundStyle(.primary)
        Spacer(minLength: 0)
        Image(systemName: "chevron.right")
          .font(.caption.weight(.bold))
          .foregroundStyle(.secondary)
      }
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .buttonStyle(.plain)
    .settingsDirectRowActionHoverEffect()
  }
}

private struct SettingsDivider: View {
  var body: some View {
    Divider()
      .padding(.leading, 54)
  }
}
