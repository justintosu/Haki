//
//  BackendConfig.swift
//  Haki
//
//  Supabase project settings. The publishable key is meant to ship in apps:
//  it only allows what the database's row-level security policies allow.
//  Secrets (Plaid keys, the service-role key) live in Supabase Edge Function
//  secrets, never here.
//

import Foundation

nonisolated enum BackendConfig {
    static let supabaseURL = URL(string: "https://bixzpnxadghxuvgckksx.supabase.co")!
    static let supabasePublishableKey = "sb_publishable_1mrJ0cWUy2qQFueJiGnUvA_pqHiw8_w"

    /// Where Supabase sends users back after email confirmation, password
    /// reset and OAuth sign-in. Registered as a URL scheme in Config/Haki-Info.plist
    /// and must be listed under Auth > URL Configuration > Redirect URLs in Supabase.
    static let authCallbackURL = URL(string: "haki://auth-callback")!

    static let avatarsBucket = "avatars"
    static let postImagesBucket = "post-images"

    /// Public URL of an image in one of the public storage buckets.
    static func publicImageURL(bucket: String, path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        return URL(string: "\(supabaseURL.absoluteString)/storage/v1/object/public/\(bucket)/\(encoded)")
    }

    static func avatarURL(path: String?) -> URL? { publicImageURL(bucket: avatarsBucket, path: path) }
    static func postImageURL(path: String?) -> URL? { publicImageURL(bucket: postImagesBucket, path: path) }
}
