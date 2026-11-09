//
//  AppDatabase.swift
//  Haki
//
//  Opens the on-device SwiftData store. When it can't be opened (a model
//  change that can't migrate, a full disk, a damaged file) the app shows
//  `AppDatabaseRecoveryView` instead of crashing, and the user can try again,
//  continue with a temporary database, or set the file aside and start fresh.
//

import Foundation
import Observation
import SwiftData
import SwiftUI

@Observable
final class AppDatabase {
    /// The open database, or `nil` while the on-device store can't be opened.
    private(set) var container: ModelContainer? = nil
    /// Why the store couldn't be opened, shown under "Details".
    private(set) var failureDescription: String? = nil
    /// How many times in a row opening the store has failed.
    private(set) var failedAttempts = 0

    init() {
        open()
    }

    /// An in-memory store filled with sample money, meal and workout data,
    /// for UI tests (`HakiLaunchOptions.isUITesting`). Nothing is saved.
    init(uiTestingSampleData: Void) {
        do {
            let container = try HakiSchema.makeContainer(inMemory: true)
            LedgerStore.loadSampleData(into: container.mainContext)
            PreviewData.loadHealthSamples(into: container.mainContext)
            use(container)
        } catch {
            failureDescription = String(describing: error)
            failedAttempts = 1
        }
    }

    /// A store that failed to open, for previews of the recovery screen.
    init(previewFailure: String) {
        failureDescription = previewFailure
        failedAttempts = 1
    }

    /// Opens the on-device store, retrying once before giving up.
    func open() {
        var lastError: (any Error)?
        for _ in 0..<2 {
            do {
                let container = try HakiSchema.makeContainer()
                use(container)
                return
            } catch {
                lastError = error
            }
        }
        container = nil
        failedAttempts += 1
        failureDescription = lastError.map { String(describing: $0) }
    }

    /// Continues with an in-memory database so sign-in, the feed and Invest
    /// keep working. Money data added this session isn't kept; the next launch
    /// tries the on-device store again.
    func continueWithTemporaryData() {
        do {
            let container = try HakiSchema.makeContainer(inMemory: true)
            use(container)
        } catch {
            failureDescription = String(describing: error)
        }
    }

    /// Moves the store's files into a backup folder beside them (kept, not
    /// deleted), then opens a new, empty store.
    func resetLocalData() {
        do {
            try Self.moveStoreAside()
        } catch {
            failureDescription = String(describing: error)
            return
        }
        open()
    }

    private func use(_ container: ModelContainer) {
        LedgerStore.ensureDefaultCategories(in: container.mainContext)
        self.container = container
        failureDescription = nil
        failedAttempts = 0
    }

    /// Where `HakiSchema.makeContainer()` keeps its store: the same
    /// configuration, so the same location.
    private static var storeURL: URL {
        ModelConfiguration(schema: Schema(HakiSchema.models), isStoredInMemoryOnly: false).url
    }

    private static func moveStoreAside() throws {
        let fileManager = FileManager.default
        let store = storeURL
        let directory = store.deletingLastPathComponent()
        let fileName = store.lastPathComponent
        // The SQLite file, its journal files, and Core Data's external-storage folder.
        let names: [String] = [
            fileName,
            fileName + "-shm",
            fileName + "-wal",
            "." + store.deletingPathExtension().lastPathComponent + "_SUPPORT",
        ]
        let existing = names.filter { name in
            fileManager.fileExists(atPath: directory.appending(path: name).path(percentEncoded: false))
        }
        guard !existing.isEmpty else { return }

        let backup = directory
            .appending(path: "Haki data set aside", directoryHint: .isDirectory)
            .appending(path: String(Int(Date.now.timeIntervalSince1970)), directoryHint: .isDirectory)
        try fileManager.createDirectory(at: backup, withIntermediateDirectories: true)
        for name in existing {
            try fileManager.moveItem(at: directory.appending(path: name), to: backup.appending(path: name))
        }
    }
}

/// Shown at the root instead of the app when the on-device store can't be opened.
struct AppDatabaseRecoveryView: View {
    let database: AppDatabase

    @State private var confirmsReset = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header
                primaryActions
                resetSection
                if let details = database.failureDescription {
                    DisclosureGroup("Details") {
                        Text(details)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    }
                    .hakiCard()
                }
            }
            .padding(24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Color.hakiBackground)
        .confirmationDialog("Reset local data?", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("Reset Local Data", role: .destructive) {
                database.resetLocalData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Haki sets the current file aside on this iPhone and starts with no transactions, budgets, bills or accounts. Your profile, posts and brokerage connections aren't affected.")
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(Color.hakiWarning)
                .accessibilityHidden(true)
            Text("Haki couldn't open your data")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("Your transactions, budgets, bills and accounts are kept in a file on this iPhone, and that file couldn't be opened. Nothing has been deleted.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if database.failedAttempts > 1 {
                Text("Still couldn't open it. If this keeps happening, continue without saving for now, or reset local data.")
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 32)
    }

    private var primaryActions: some View {
        VStack(spacing: 12) {
            Button {
                database.open()
            } label: {
                Text("Try Again")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                database.continueWithTemporaryData()
            } label: {
                Text("Continue Without Saving")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Text("Sign-in, the feed and Invest work as usual. Money data you add won't be kept, and Haki tries your file again the next time it opens.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var resetSection: some View {
        VStack(spacing: 8) {
            Button("Reset Local Data", role: .destructive) {
                confirmsReset = true
            }
            .font(.body.weight(.semibold))
            Text("Sets the file aside on this iPhone (it isn't deleted) and starts with empty money data.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

#Preview {
    AppDatabaseRecoveryView(database: AppDatabase(previewFailure: "SwiftDataError: loadIssueModelContainer"))
        .previewEnvironment()
}
