//
//  CommunityGuidelinesView.swift
//  Haki
//
//  The rules for everything people share on Haki (profiles, posts, photos
//  and comments), how to report and block, and what happens to reports.
//  Agreed to during onboarding; also pushed from Settings. Pushed inside a
//  NavigationStack (no stack of its own).
//

import Foundation
import SwiftUI

struct CommunityGuidelinesView: View {
    init() {}

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                introCard
                ruleCard("Not allowed on Haki", systemImage: "xmark.octagon", rules: Self.notAllowed)
                ruleCard("Talk about investing honestly", systemImage: "chart.line.uptrend.xyaxis", rules: Self.investing)
                ruleCard("If you see something wrong", systemImage: "flag", rules: Self.safetyTools)
                enforcementCard
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(Color.hakiBackground)
        .navigationTitle("Community Guidelines")
    }

    // MARK: Cards

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Keep Haki a good place to talk about money")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("These rules apply to everything you share on Haki: your profile, posts, photos and comments. Haki has zero tolerance for objectionable content and abusive behavior.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .hakiCard()
    }

    private func ruleCard(_ title: String, systemImage: String, rules: [CommunityGuidelinesRule]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title, systemImage: systemImage)
            ForEach(rules) { rule in
                CommunityGuidelinesRuleRow(rule: rule)
            }
        }
        .hakiCard()
    }

    private var enforcementCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader("What happens next", systemImage: "checkmark.shield")
            Text("Haki's team reviews reported posts, comments and accounts, usually within 24 hours. Content that breaks these guidelines is removed, and accounts that post it are suspended or removed for good. The person you report isn't told who reported them.")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Text("Using Haki's social features means you agree to follow these guidelines.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .hakiCard()
    }

    // MARK: Rules

    private static let notAllowed: [CommunityGuidelinesRule] = [
        CommunityGuidelinesRule(
            title: "Harassment or bullying",
            detail: "No insulting, threatening, shaming or targeting anyone, and no encouraging others to pile on.",
            systemImage: "hand.raised"
        ),
        CommunityGuidelinesRule(
            title: "Hate",
            detail: "No attacks on people for their race, ethnicity, national origin, religion, caste, sex, gender identity, sexual orientation, disability, age or illness, and no hateful slurs or symbols.",
            systemImage: "nosign"
        ),
        CommunityGuidelinesRule(
            title: "Threats and violence",
            detail: "No threats, calls for violence, or content that glorifies violence or encourages self-harm.",
            systemImage: "exclamationmark.triangle"
        ),
        CommunityGuidelinesRule(
            title: "Sexual content",
            detail: "No nudity, pornography or sexual content — and never anything that sexualizes minors.",
            systemImage: "eye.slash"
        ),
        CommunityGuidelinesRule(
            title: "Scams and spam",
            detail: "No pump-and-dump schemes, fake giveaways, “guaranteed returns” offers, phishing links, repeated posts or unwanted promotion.",
            systemImage: "xmark.shield"
        ),
        CommunityGuidelinesRule(
            title: "Impersonation",
            detail: "Don't pretend to be another person, a company or a financial professional, or mislead people about who you are.",
            systemImage: "person.crop.circle.badge.xmark"
        ),
        CommunityGuidelinesRule(
            title: "Other people's private information",
            detail: "Don't share anyone's private details — addresses, phone numbers, account numbers or screenshots of their finances — without their permission.",
            systemImage: "lock"
        ),
    ]

    private static let investing: [CommunityGuidelinesRule] = [
        CommunityGuidelinesRule(
            title: "Nothing is guaranteed",
            detail: "Share ideas, trades and opinions, but never present a stock, fund or strategy as a sure thing, risk-free or guaranteed to make money.",
            systemImage: "exclamationmark.circle"
        ),
        CommunityGuidelinesRule(
            title: "Opinions, not advice",
            detail: "Posts on Haki are people's own views, not professional financial advice. Do your own research before you invest.",
            systemImage: "text.bubble"
        ),
        CommunityGuidelinesRule(
            title: "Be upfront",
            detail: "Say so if you're paid to promote something, and don't hype a stock to profit from other people buying or selling it.",
            systemImage: "megaphone"
        ),
    ]

    private static let safetyTools: [CommunityGuidelinesRule] = [
        CommunityGuidelinesRule(
            title: "Report posts, comments and accounts",
            detail: "Open the menu on a post or profile, or press and hold a comment, and choose Report.",
            systemImage: "flag"
        ),
        CommunityGuidelinesRule(
            title: "Block people",
            detail: "Blocking someone hides their posts, comments and activity from you, and stops you following them.",
            systemImage: "hand.raised.slash"
        ),
    ]
}

// MARK: - Helpers

private nonisolated struct CommunityGuidelinesRule: Identifiable {
    let title: String
    let detail: String
    let systemImage: String

    var id: String { title }
}

private struct CommunityGuidelinesRuleRow: View {
    let rule: CommunityGuidelinesRule

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: rule.systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.title)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(rule.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        CommunityGuidelinesView()
    }
    .previewEnvironment()
}
