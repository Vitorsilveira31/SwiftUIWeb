// Web adapter, not part of Apple's sample.
//
// Apple's AccountStore.swift (excluded from this package) signs in with passkeys through AuthenticationServices and
// needs an AppKit/UIKit presentation anchor. This is the same public surface for the browser: sign-in and sign-up work
// locally, and the signed-in user persists in the page's local storage.
import AuthenticationServices
import Observation
import Foundation
import SwiftUI

@MainActor
@Observable
public final class AccountStore {
    private static let key = "foodtruck.account.username"

    /// Starts signed out; the init below restores a remembered account, and sign-in calls set the user.
    public private(set) var currentUser: User?

    public var isSignedIn: Bool {
        currentUser != nil
    }

    public init() {
        if let username = UserDefaults.standard.string(forKey: Self.key) {
            currentUser = .authenticated(username: username)
        }
    }

    public func signIntoPasskeyAccount(authorizationController: AuthorizationController,
                                       options: ASAuthorizationController.RequestOptions = []) async {
        let username = UserDefaults.standard.string(forKey: Self.key) ?? "Food Truck Owner"
        remember(username)
    }

    public func createPasskeyAccount(authorizationController: AuthorizationController, username: String,
                                     options: ASAuthorizationController.RequestOptions = []) async {
        remember(username)
    }

    public func createPasswordAccount(username: String, password: String) async {
        remember(username)
    }

    public func signOut() {
        currentUser = nil
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    private func remember(_ username: String) {
        currentUser = .authenticated(username: username)
        UserDefaults.standard.set(username, forKey: Self.key)
    }
}
