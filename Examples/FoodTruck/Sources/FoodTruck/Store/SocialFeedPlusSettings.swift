/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The social feed settings view.
*/

import SwiftUI
import StoreKit
import FoodTruckKit

struct SocialFeedPlusSettings: View {
    var controller: StoreSubscriptionController
    @AppStorage("showPlusPosts") private var showPlusPosts = false
    @AppStorage("advancedTools") private var advancedTools = true
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        List {
            SubscriptionStatusView(controller: controller)
            Section("Settings") {
                Toggle("Highlight Social Feed+ posts", isOn: $showPlusPosts)
                Toggle("Advanced engagement tools", isOn: $advancedTools)
                NavigationLink("Social-media providers") {
                    EmptyView()
                }
            }
            #if (os(iOS) || WEB)
            Section {
                NavigationLink {
                    StoreSupportView()
                } label: {
                    Label("Subscription support", systemImage: "questionmark.circle")
                }
            }
            #else
            Section("Subscription support") {
                Button("Restore missing purchases") {
                    Task(priority: .userInitiated) {
                        try await AppStore.sync()
                    }
                }
            }
            #endif
        }
        .navigationTitle("Manage Social Feed+")
        .toolbar {
            #if (os(iOS) || WEB)
            let placement = ToolbarItemPlacement.navigationBarTrailing
            #else
            let placement = ToolbarItemPlacement.cancellationAction
            #endif
            ToolbarItemGroup(placement: placement) {
                Button {
                    dismiss()
                } label: {
                    Label("Dismiss", systemImage: "xmark")
                        #if (os(macOS) && !WEB)
                        .labelStyle(.titleOnly)
                        #endif
                }
            }
        }
        .onAppear {
            // The user might lose their entitlement while this view is in the
            // navigation stack. In this case you need to dismiss the view.
            if controller.entitledSubscription == nil {
                dismiss()
            }
        }
    }
}

struct SubscriptionStatusView: View {
    var controller: StoreSubscriptionController
    #if (os(iOS) || WEB)
    @State private var manageSubscriptionIsPresented = false
    #else
    @Environment(\.openURL) private var openURL
    #endif
    
    var currentSubscriptionName: String {
        controller.entitledSubscription?.displayName ?? String(localized: "None")
    }
    
    var newNextSubscriptionName: String? {
        if controller.entitledSubscriptionID != controller.autoRenewPreference {
            return controller.nextSubscription?.displayName
        }
        return nil
    }
    
    var renewalText: String {
        let expiration = controller.expirationDate?.formatted(
            date: .abbreviated,
            time: .omitted
        ) ?? String(localized: "None")
        
        guard let nextSubscription = controller.nextSubscription else {
            return String(localized: "Expires on \(expiration)")
        }
        let prefix: String
        if let newNextSubscriptionName = newNextSubscriptionName {
            prefix = String(localized: "Renews to \(newNextSubscriptionName)")
        } else {
            prefix = String(localized: "Renews")
        }
        let price = nextSubscription.displayPrice
        return String(localized: "\(prefix) for \(price) on \(expiration)")
    }
    
    var body: some View {
        Section("Your subscription") {
            VStack(alignment: .leading) {
                Text(currentSubscriptionName)
                    .font(.headline)
                    .bold()
                Text(renewalText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Button("Manage subscription") {
                #if (os(iOS) || WEB)
                manageSubscriptionIsPresented = true
                #else
                if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                    openURL(url)
                }
                #endif
            }
            #if (os(iOS) || WEB)
            .manageSubscriptionsSheet(isPresented: $manageSubscriptionIsPresented)
            #endif
        }
    }
    
}

struct SocialFeedPlusSettings_Previews: PreviewProvider {

    static var previews: some View {
        NavigationStack {
            SocialFeedPlusSettings(
                controller: StoreActor.shared.subscriptionController
            )
        }
    }
    
}
