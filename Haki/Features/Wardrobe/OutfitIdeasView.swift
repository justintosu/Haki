//
//  OutfitIdeasView.swift
//  Haki
//
//  Outfit ideas from Haki's AI: pick an occasion (quick chips or typed),
//  optionally say what the weather's like, and get a few outfits made from
//  the pieces in the wardrobe, each with why it works and what it's still
//  missing. "Save outfit" turns an idea into an outfit board. Only the
//  pieces' details are sent (no photos). Presented as a sheet.
//

import Foundation
import SwiftData
import SwiftUI
import UIKit

struct OutfitIdeasView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(HakiAIService.self) private var hakiAI

    @Query(sort: [SortDescriptor(\ClothingItem.createdAt, order: .reverse)])
    private var items: [ClothingItem]

    @State private var occasion = ""
    @State private var weather = ""
    @State private var isLoading = false
    @State private var requestTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var report: OutfitIdeaReport?
    /// The occasion the shown ideas were made for (saved with each outfit).
    @State private var requestedOccasion = ""
    /// Saved ideas, by their position in `report`.
    @State private var savedOutfits: [Int: Outfit] = [:]
    @State private var showsAddPiece = false
    @State private var savedFeedback = 0
    @FocusState private var focusedField: OutfitIdeasField?

    static let minimumPieces = 3
    private static let quickOccasions = ["Work", "Weekend", "Date night", "Gym", "Travel", "Rainy day"]

    init() {}

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if items.count < Self.minimumPieces {
                        notEnoughPieces
                    } else {
                        requestCard
                        statusContent
                        resultsContent
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
                .animation(.snappy, value: isLoading)
            }
            .background(Color.hakiBackground)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Outfit ideas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
        }
        .sheet(isPresented: $showsAddPiece) {
            ClothingItemEditorView(item: nil)
        }
        .sensoryFeedback(.success, trigger: savedFeedback)
        .onDisappear {
            requestTask?.cancel()
        }
    }

    // MARK: Not enough pieces

    private var notEnoughPieces: some View {
        ContentUnavailableView {
            Label("Add a few more pieces", systemImage: "hanger")
        } description: {
            Text(notEnoughText)
        } actions: {
            Button {
                showsAddPiece = true
            } label: {
                Label("Add a piece", systemImage: "camera.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.top, 40)
    }

    private var notEnoughText: String {
        let missing = Self.minimumPieces - items.count
        let pieces = missing == 1 ? "1 more piece" : "\(missing) more pieces"
        return "Outfit ideas need at least \(Self.minimumPieces) pieces in your wardrobe, so add \(pieces). A top, a bottom and shoes work best."
    }

    // MARK: Request

    private var requestCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader("What's it for?", systemImage: "sparkles")
            TextField("Occasion, e.g. Brunch with friends", text: $occasion)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.next)
                .focused($focusedField, equals: .occasion)
                .onSubmit { focusedField = .weather }
                .padding(12)
                .background(Color.hakiBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityLabel("Occasion")
            quickChips
            TextField("Weather (optional), e.g. 55°F and windy", text: $weather)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.go)
                .focused($focusedField, equals: .weather)
                .onSubmit { getIdeas() }
                .padding(12)
                .background(Color.hakiBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityLabel("Weather, optional")
            Button {
                getIdeas()
            } label: {
                Label(report == nil ? "Get ideas" : "Get new ideas", systemImage: "sparkles")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isLoading)
            Text("Haki sends your pieces' names, types, colors and styles (no photos) to its AI to put outfits together.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .hakiCard()
    }

    private var quickChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Self.quickOccasions, id: \.self) { option in
                    WardrobeChip(option, isSelected: trimmedOccasion.caseInsensitiveCompare(option) == .orderedSame) {
                        occasion = option
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Status

    @ViewBuilder
    private var statusContent: some View {
        if isLoading {
            HStack(spacing: 12) {
                ProgressView()
                Text("Putting outfits together from your \(items.count) pieces…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Cancel") {
                    cancelRequest()
                }
                .font(.subheadline.weight(.semibold))
            }
            .hakiCard()
        } else if let errorMessage {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.hakiWarning)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(errorMessage)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Try again") {
                        getIdeas()
                    }
                    .font(.subheadline.weight(.semibold))
                }
                Spacer(minLength: 0)
            }
            .hakiCard()
        }
    }

    // MARK: Results

    @ViewBuilder
    private var resultsContent: some View {
        if let report, !isLoading {
            let byID = itemsByID
            VStack(alignment: .leading, spacing: 12) {
                Text(resultsTitle)
                    .font(.title3.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                let notes = report.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                if !notes.isEmpty {
                    Text(notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if report.outfits.isEmpty {
                    Text("Haki couldn't put an outfit together from these pieces. Try another occasion, or add a few more pieces.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .hakiCard()
                } else {
                    ForEach(Array(report.outfits.enumerated()), id: \.offset) { index, idea in
                        OutfitIdeaCard(
                            idea: idea,
                            pieces: idea.itemIDs.compactMap { byID[$0] },
                            savedOutfit: savedOutfits[index],
                            onSave: { save(idea, at: index) }
                        )
                    }
                }
            }
        }
    }

    private var resultsTitle: String {
        requestedOccasion.isEmpty ? "Ideas for every day" : "Ideas for \(requestedOccasion.lowercased())"
    }

    private var itemsByID: [String: ClothingItem] {
        Dictionary(items.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var trimmedOccasion: String {
        occasion.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Actions

    private func getIdeas() {
        guard items.count >= Self.minimumPieces, !isLoading else { return }
        focusedField = nil
        let pieces = items.map(\.summary)
        let occasionUsed = trimmedOccasion
        let weatherText = weather.trimmingCharacters(in: .whitespacesAndNewlines)
        let weatherUsed: String? = weatherText.isEmpty ? nil : weatherText
        requestTask?.cancel()
        errorMessage = nil
        isLoading = true
        UIAccessibility.post(notification: .announcement, argument: "Getting outfit ideas")
        requestTask = Task {
            do {
                let result = try await hakiAI.suggestOutfits(
                    pieces: pieces,
                    occasion: occasionUsed.isEmpty ? "Everyday" : occasionUsed,
                    weather: weatherUsed
                )
                guard !Task.isCancelled else { return }
                withAnimation(.snappy) {
                    report = result
                    requestedOccasion = occasionUsed
                    savedOutfits = [:]
                    isLoading = false
                }
                let count = result.outfits.count
                let announcement: String = count == 1 ? "1 outfit idea" : "\(count) outfit ideas"
                UIAccessibility.post(notification: .announcement, argument: announcement)
            } catch {
                guard !Task.isCancelled else { return }
                isLoading = false
                if !Backend.isCancellation(error) {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func cancelRequest() {
        requestTask?.cancel()
        requestTask = nil
        isLoading = false
    }

    private func save(_ idea: OutfitIdea, at index: Int) {
        guard savedOutfits[index] == nil else { return }
        guard let outfit = WardrobeStore.saveIdea(idea, occasion: requestedOccasion, from: items, in: modelContext) else {
            errorMessage = "Some of those pieces are no longer in your wardrobe, so that outfit couldn't be saved."
            return
        }
        withAnimation(.snappy) {
            savedOutfits[index] = outfit
        }
        savedFeedback += 1
    }
}

private enum OutfitIdeasField: Hashable {
    case occasion
    case weather
}

/// One idea: its name, why it works, its pieces, what it's missing, and
/// "Save outfit" (then "Open").
private struct OutfitIdeaCard: View {
    let idea: OutfitIdea
    let pieces: [ClothingItem]
    let savedOutfit: Outfit?
    let onSave: () -> Void

    @ScaledMetric(relativeTo: .caption) private var tileSize: CGFloat = 76

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(idea.name)
                    .font(.headline)
                let reason = idea.reason.trimmingCharacters(in: .whitespacesAndNewlines)
                if !reason.isEmpty {
                    Text(reason)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            piecesRow
            if let hint = OutfitRules.hint(pieces.map(\.category)) {
                Label("\(hint) to finish the look.", systemImage: "lightbulb")
                    .font(.footnote)
                    .foregroundStyle(Color.hakiWarning)
            }
            actions
        }
        .hakiCard()
    }

    private var piecesRow: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(pieces) { item in
                    VStack(spacing: 6) {
                        WardrobeItemTile(item: item, cornerRadius: 12)
                            .frame(width: tileSize, height: tileSize)
                        Text(item.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(width: tileSize)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var actions: some View {
        if let savedOutfit {
            HStack(spacing: 10) {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.hakiPositive)
                Spacer(minLength: 8)
                NavigationLink {
                    OutfitBoardView(outfit: savedOutfit)
                } label: {
                    Label("Open board", systemImage: "square.on.square")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }
        } else {
            Button(action: onSave) {
                Label("Save outfit", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityHint("Saves this idea as an outfit board")
        }
    }
}

#Preview {
    OutfitIdeasView()
        .previewEnvironment()
}

#Preview("Too few pieces") {
    OutfitIdeasView()
        .previewEnvironment(empty: true)
}
