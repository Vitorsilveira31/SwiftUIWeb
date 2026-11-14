// Apple's Food Truck imports AppIntents where it offers Siri and Shortcuts, behind `#if os(iOS)`. A browser has neither,
// so the module only has to exist for the import to resolve.
import SwiftUIWeb
