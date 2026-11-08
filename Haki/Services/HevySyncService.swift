//
//  HevySyncService.swift
//  Haki
//
//  Keeps Haki's workouts in step with the person's Hevy account: workouts
//  logged in Hevy are copied into Haki (WorkoutSource.hevy), and finished
//  Haki workouts can be posted to Hevy. Talks to Hevy directly with the
//  person's own API key (stored in the Keychain, see HevyKeychain); nothing
//  goes through Haki's servers. Every database write goes through
//  WorkoutStore.
//
//  Injected at the root: `.environment(HevySyncService.live)`; read with
//  `@Environment(HevySyncService.self) private var hevy`. The preview
//  instance is connected as "preview" and never touches the network.
//

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class HevySyncService {
    /// Bool in UserDefaults: post uploads to Hevy as private workouts (default off).
    static let uploadPrivateKey = "health.hevyUploadPrivate"
    /// `syncIfDue` syncs when the last sync is older than this.
    static let autoSyncInterval: TimeInterval = 15 * 60

    private(set) var isConnected = false
    private(set) var username: String? = nil
    private(set) var isSyncing = false
    private(set) var lastSyncAt: Date? = nil
    /// User-facing; nil after a successful sync.
    private(set) var lastError: String? = nil
    /// Haki workouts (by `WorkoutRecord.id`) being posted to Hevy right now.
    private(set) var uploadingWorkoutIDs: Set<UUID> = []

    private var storedUploadEnabled = false

    /// Post finished Haki workouts to Hevy automatically. Backed by
    /// `HealthSettings.hevyUploadEnabledKey`.
    var uploadEnabled: Bool {
        get { storedUploadEnabled }
        set {
            storedUploadEnabled = newValue
            if !isPreview {
                defaults.set(newValue, forKey: HealthSettings.hevyUploadEnabledKey)
            }
        }
    }

    /// Preview mode: no network, no Keychain; sync and upload do nothing.
    let isPreview: Bool
    private let defaults: UserDefaults
    private let session: URLSession

    @ObservationIgnored private var apiKey: String? = nil
    /// Hevy's exercise templates by id, loaded once per run.
    @ObservationIgnored private var templates: [String: HevyExerciseTemplate] = [:]
    @ObservationIgnored private var templatesLoaded = false
    @ObservationIgnored private var syncTask: Task<Void, Never>? = nil
    /// Uploads in flight by `WorkoutRecord.id`, so a second request for the
    /// same workout waits for the first instead of posting it twice.
    @ObservationIgnored private var uploadTasks: [UUID: Task<Void, any Error>] = [:]
    /// Bumped when a sync starts and when it's stopped (disconnect), so work
    /// from a stopped sync never writes anything.
    @ObservationIgnored private var syncGeneration = 0
    /// When an automatic or manual sync last started, to space out retries.
    @ObservationIgnored private var lastAttemptAt: Date? = nil

    private static let retryInterval: TimeInterval = 5 * 60
    /// First sync: up to 300 workouts (30 pages of 10), newest first.
    private static let firstSyncPageLimit = 30
    private static let eventPageLimit = 50
    private static let templatePageLimit = 20
    /// Later syncs ask for events from a little before the last sync.
    private static let eventOverlap: TimeInterval = 5 * 60

    /// Real network and Keychain.
    static let live = HevySyncService(isPreview: false, previewConnected: false, defaults: .standard, session: .shared)
    /// Connected as "preview"; no network.
    static let preview = HevySyncService(isPreview: true, previewConnected: true, defaults: .standard, session: .shared)

    /// A preview instance, connected or not (e.g. for a "not connected" preview).
    static func makePreview(connected: Bool) -> HevySyncService {
        HevySyncService(isPreview: true, previewConnected: connected, defaults: .standard, session: .shared)
    }

    private init(isPreview: Bool, previewConnected: Bool, defaults: UserDefaults, session: URLSession) {
        self.isPreview = isPreview
        self.defaults = defaults
        self.session = session
        if isPreview {
            isConnected = previewConnected
            username = previewConnected ? "preview" : nil
            lastSyncAt = previewConnected ? Date.now : nil
            return
        }
        var key = HevyKeychain.read()
        if key != nil, defaults.object(forKey: HealthSettings.hevyUsernameKey) == nil {
            // Keychain items outlive the app: a key without the username Haki
            // saves alongside it was left by an earlier install. Forget it.
            HevyKeychain.delete()
            key = nil
        }
        apiKey = key
        isConnected = key != nil
        let savedName = defaults.string(forKey: HealthSettings.hevyUsernameKey) ?? ""
        username = (key == nil || savedName.isEmpty) ? nil : savedName
        lastSyncAt = key == nil ? nil : HevyAPI.parseDate(defaults.string(forKey: HealthSettings.hevyLastSyncKey))
        storedUploadEnabled = defaults.bool(forKey: HealthSettings.hevyUploadEnabledKey)
    }

    /// Whether `workout` is being posted to Hevy right now.
    func isUploading(_ workout: WorkoutRecord) -> Bool {
        uploadingWorkoutIDs.contains(workout.id)
    }

    // MARK: Connecting

    /// Checks the key with Hevy (GET /v1/user/info), stores it in the
    /// Keychain, then copies recent workouts. Throws when the key is
    /// malformed or Hevy doesn't accept it; sync problems end up in `lastError`.
    func connect(apiKey rawKey: String, in context: ModelContext) async throws {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard HevyAPI.isPlausibleAPIKey(key) else { throw HevyClientError.malformedKey }
        if isPreview {
            isConnected = true
            username = "preview"
            lastSyncAt = Date.now
            lastError = nil
            return
        }

        let info = try await HevyClient(apiKey: key, session: session).userInfo()
        try HevyKeychain.save(key)

        stopSync()
        let name = Self.displayName(for: info)
        defaults.set(name, forKey: HealthSettings.hevyUsernameKey)
        // Start over: the first sync copies recent workouts again (ones copied
        // before are matched by their Hevy id, so nothing is duplicated).
        defaults.removeObject(forKey: HealthSettings.hevyLastSyncKey)
        apiKey = key
        templates = [:]
        templatesLoaded = false
        lastAttemptAt = nil
        username = name.isEmpty ? nil : name
        isConnected = true
        lastSyncAt = nil
        lastError = nil

        await sync(in: context)
    }

    /// Forgets the key. Workouts copied from Hevy stay unless
    /// `removeCopiedWorkouts`; Haki's own workouts always stay.
    func disconnect(removeCopiedWorkouts: Bool, in context: ModelContext) {
        stopSync()
        for task in uploadTasks.values {
            task.cancel()
        }
        if !isPreview {
            HevyKeychain.delete()
            defaults.removeObject(forKey: HealthSettings.hevyUsernameKey)
            defaults.removeObject(forKey: HealthSettings.hevyLastSyncKey)
        }
        apiKey = nil
        templates = [:]
        templatesLoaded = false
        lastAttemptAt = nil
        isConnected = false
        username = nil
        lastSyncAt = nil
        lastError = nil
        if removeCopiedWorkouts {
            WorkoutStore.removeAllHevyCopies(in: context)
        }
    }

    private static func displayName(for info: HevyUserInfo) -> String {
        let candidates = [info.username, info.name].compactMap { $0 }
        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return ""
    }

    // MARK: Syncing

    /// Copies new, changed and deleted Hevy workouts. Never throws: problems
    /// end up in `lastError`, and what was copied before a failure is kept.
    /// Joins the sync already running, if any.
    func sync(in context: ModelContext) async {
        guard isConnected else { return }
        if isPreview {
            lastSyncAt = Date.now
            lastError = nil
            return
        }
        if let running = syncTask {
            await running.value
            return
        }
        syncGeneration += 1
        let generation = syncGeneration
        isSyncing = true
        // Its own task, so leaving the screen that asked doesn't stop the sync halfway.
        let task = Task {
            await self.performSync(generation: generation, in: context)
        }
        syncTask = task
        await task.value
        if generation == syncGeneration {
            syncTask = nil
            isSyncing = false
        }
    }

    /// Starts a sync in the background when connected and the last sync is
    /// more than 15 minutes old. Returns immediately.
    func syncIfDue(in context: ModelContext) {
        guard isConnected, !isPreview, syncTask == nil else { return }
        let now = Date.now
        if let last = HevyAPI.parseDate(defaults.string(forKey: HealthSettings.hevyLastSyncKey)),
           now.timeIntervalSince(last) < Self.autoSyncInterval {
            return
        }
        if let lastAttemptAt, now.timeIntervalSince(lastAttemptAt) < Self.retryInterval {
            return
        }
        Task {
            await self.sync(in: context)
        }
    }

    private func stopSync() {
        syncGeneration += 1
        syncTask?.cancel()
        syncTask = nil
        isSyncing = false
    }

    private func performSync(generation: Int, in context: ModelContext) async {
        guard let key = apiKey else {
            lastError = "Connect your Hevy account again to keep syncing."
            return
        }
        let client = HevyClient(apiKey: key, session: session)
        let startedAt = Date.now
        lastAttemptAt = startedAt
        do {
            await loadTemplatesQuietly(client)
            try checkStillCurrent(generation)
            if let since = HevyAPI.parseDate(defaults.string(forKey: HealthSettings.hevyLastSyncKey)) {
                try await applyEvents(since: since.addingTimeInterval(-Self.eventOverlap), client: client, generation: generation, in: context)
            } else {
                try await copyRecentWorkouts(client: client, generation: generation, in: context)
            }
            try checkStillCurrent(generation)
            defaults.set(HevyAPI.formatDate(startedAt), forKey: HealthSettings.hevyLastSyncKey)
            lastSyncAt = startedAt
            lastError = nil
        } catch {
            guard generation == syncGeneration, !Backend.isCancellation(error) else { return }
            lastError = error.localizedDescription
        }
    }

    /// Throws `CancellationError` once this sync was stopped or superseded.
    private func checkStillCurrent(_ generation: Int) throws {
        if generation != syncGeneration || Task.isCancelled {
            throw CancellationError()
        }
    }

    /// First sync: pages through the newest workouts, saving after each page.
    private func copyRecentWorkouts(client: HevyClient, generation: Int, in context: ModelContext) async throws {
        var page = 1
        var pageCount = 1
        while page <= min(pageCount, Self.firstSyncPageLimit) {
            let result: HevyWorkoutPage
            do {
                result = try await client.workouts(page: page)
            } catch HevyClientError.notFound {
                // Past the last page (or no workouts at all).
                break
            }
            try checkStillCurrent(generation)
            for workout in result.workouts {
                WorkoutStore.upsertHevyWorkout(workout, templates: templates, in: context)
            }
            WorkoutStore.save(in: context)
            if result.workouts.isEmpty { break }
            pageCount = result.pageCount
            page += 1
        }
    }

    /// Later syncs: applies what changed since `since`, saving after each page.
    private func applyEvents(since: Date, client: HevyClient, generation: Int, in context: ModelContext) async throws {
        // Events come newest first, so the first one seen for a workout is its
        // current state; older events for it are skipped.
        var handled: Set<String> = []
        var page = 1
        var pageCount = 1
        while page <= min(pageCount, Self.eventPageLimit) {
            let result: HevyEventPage
            do {
                result = try await client.workoutEvents(since: since, page: page)
            } catch HevyClientError.notFound {
                break
            }
            try checkStillCurrent(generation)
            for event in result.events {
                switch event {
                case .updated(let workout):
                    guard handled.insert(workout.id).inserted else { continue }
                    WorkoutStore.upsertHevyWorkout(workout, templates: templates, in: context)
                case .deleted(let id, _):
                    guard handled.insert(id).inserted else { continue }
                    WorkoutStore.removeHevyWorkout(hevyID: id, in: context)
                case .unknown:
                    continue
                }
            }
            WorkoutStore.save(in: context)
            if result.events.isEmpty { break }
            pageCount = result.pageCount
            page += 1
        }
    }

    // MARK: Exercise templates

    /// Loads every exercise template on the account (Hevy's library and
    /// custom ones). Throws when they can't be loaded.
    private func loadTemplates(_ client: HevyClient, force: Bool = false) async throws {
        if templatesLoaded && !force { return }
        var loaded: [String: HevyExerciseTemplate] = [:]
        var page = 1
        var pageCount = 1
        while page <= min(pageCount, Self.templatePageLimit) {
            let result: HevyTemplatePage
            do {
                result = try await client.exerciseTemplates(page: page)
            } catch HevyClientError.notFound {
                break
            }
            for template in result.exerciseTemplates {
                loaded[template.id] = template
            }
            if result.exerciseTemplates.isEmpty { break }
            pageCount = result.pageCount
            page += 1
        }
        templates = loaded
        templatesLoaded = true
    }

    /// For syncing: without templates, muscles come from Haki's library (or "other").
    private func loadTemplatesQuietly(_ client: HevyClient) async {
        do {
            try await loadTemplates(client)
        } catch {
            // Skipped on purpose; the next sync tries again.
        }
    }

    private func matchingTemplateID(for name: String) -> String? {
        let candidates: [(id: String, title: String, isCustom: Bool)] = templates.values.map { template in
            (id: template.id, title: template.title, isCustom: template.isCustom ?? false)
        }
        return ExerciseLibrary.matchingTemplateID(for: name, in: candidates)
    }

    /// The Hevy template for an exercise: the one it already knows, one with
    /// the same title, or a new custom template. Nil when Hevy didn't say
    /// which id it gave a new template and it can't be found by title.
    private func templateID(for exercise: HevyUploadExercise, client: HevyClient) async throws -> String? {
        if let known = exercise.knownTemplateID, !known.isEmpty, templates.isEmpty || templates[known] != nil {
            return known
        }
        if let match = matchingTemplateID(for: exercise.name) {
            return match
        }
        let created = try await client.createCustomExerciseTemplate(
            title: exercise.name,
            kind: exercise.kind,
            primaryMuscle: exercise.primaryMuscle,
            otherMuscles: exercise.secondaryMuscles,
            equipment: exercise.equipment
        )
        if let created, !created.isEmpty {
            templates[created] = HevyExerciseTemplate(
                id: created,
                title: exercise.name,
                type: exercise.kind.rawValue,
                primaryMuscleGroup: exercise.primaryMuscle.rawValue,
                secondaryMuscleGroups: exercise.secondaryMuscles.map(\.rawValue),
                equipment: exercise.equipment.rawValue,
                isCustom: true
            )
            return created
        }
        try await loadTemplates(client, force: true)
        return matchingTemplateID(for: exercise.name)
    }

    // MARK: Uploading

    /// Posts a finished Haki workout to Hevy (POST /v1/workouts) and marks it
    /// uploaded. Exercises Hevy doesn't have are added as custom exercises
    /// first; if that isn't possible, nothing is posted and the error names them.
    /// Does nothing for a workout that's already in Hevy. While the same
    /// workout is already being posted, waits for that and shares its result.
    func upload(_ workout: WorkoutRecord, in context: ModelContext) async throws {
        guard workout.source == .haki else { throw HevySyncError.notFromHaki }
        guard workout.endedAt != nil else { throw HevySyncError.notFinished }
        guard workout.hevyID == nil else { return }
        guard isConnected else { throw HevySyncError.notConnected }
        if isPreview { return }

        let workoutID = workout.id
        if let running = uploadTasks[workoutID] {
            try await running.value
            return
        }
        // Its own task, so leaving the screen that asked doesn't stop it halfway.
        let task: Task<Void, any Error> = Task {
            try await self.performUpload(workout, in: context)
        }
        uploadTasks[workoutID] = task
        uploadingWorkoutIDs.insert(workoutID)
        defer {
            uploadTasks[workoutID] = nil
            uploadingWorkoutIDs.remove(workoutID)
        }
        try await task.value
    }

    private func performUpload(_ workout: WorkoutRecord, in context: ModelContext) async throws {
        guard let endedAt = workout.endedAt else { throw HevySyncError.notFinished }
        guard let key = apiKey else { throw HevySyncError.notConnected }
        let workoutID = workout.id

        // Copy everything needed before the first await; the workout can
        // change (or be deleted) while Hevy answers.
        let title = workout.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = workout.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let startedAt = workout.startedAt
        let exercises: [HevyUploadExercise] = workout.orderedExercises.compactMap { (exercise: WorkoutExerciseRecord) -> HevyUploadExercise? in
            let sets = exercise.setValues.compactMap { HevyNewWorkout.set(from: $0) }
            guard !sets.isEmpty else { return nil }
            return HevyUploadExercise(
                id: exercise.id,
                name: exercise.name,
                kind: exercise.kind,
                primaryMuscle: exercise.primaryMuscle,
                secondaryMuscles: ExerciseLibrary.exercise(key: exercise.exerciseKey)?.secondaryMuscles ?? [],
                equipment: exercise.equipment,
                knownTemplateID: exercise.hevyTemplateID,
                supersetGroup: exercise.supersetGroup,
                notes: exercise.notes.trimmingCharacters(in: .whitespacesAndNewlines),
                sets: sets
            )
        }
        guard !exercises.isEmpty else { throw HevySyncError.nothingToUpload }

        let client = HevyClient(apiKey: key, session: session)
        try await loadTemplates(client)

        var resolved: [UUID: String] = [:]
        var missing: [String] = []
        var limitMessage: String?
        for exercise in exercises {
            do {
                if let id = try await templateID(for: exercise, client: client) {
                    resolved[exercise.id] = id
                } else {
                    missing.append(exercise.name)
                }
            } catch HevyClientError.notAllowed(let message) {
                missing.append(exercise.name)
                limitMessage = message
            }
        }

        // Remember the templates (also when something is missing), so a retry
        // doesn't create them again.
        guard let current = liveWorkout(id: workoutID, in: context) else { return }
        for exercise in current.exercises {
            if let id = resolved[exercise.id], exercise.hevyTemplateID != id {
                exercise.hevyTemplateID = id
            }
        }
        WorkoutStore.save(in: context)
        guard missing.isEmpty else {
            throw HevySyncError.unknownExercises(missing, detail: limitMessage)
        }
        guard current.hevyID == nil else { return }

        var entries: [HevyNewWorkout.ExerciseEntry] = []
        for exercise in exercises {
            guard let templateID = resolved[exercise.id] else { continue }
            entries.append(HevyNewWorkout.ExerciseEntry(
                exerciseTemplateID: templateID,
                supersetID: exercise.supersetGroup,
                notes: exercise.notes.isEmpty ? nil : exercise.notes,
                sets: exercise.sets
            ))
        }
        let payload = HevyNewWorkout(
            title: title.isEmpty ? WorkoutStore.defaultTitle(for: startedAt) : title,
            description: notes.isEmpty ? nil : notes,
            startTime: startedAt,
            endTime: endedAt,
            isPrivate: defaults.bool(forKey: Self.uploadPrivateKey),
            exercises: entries
        )
        // Disconnecting cancels uploads; don't post after that.
        try Task.checkCancellation()
        let created = try await client.createWorkout(payload)

        guard let uploaded = liveWorkout(id: workoutID, in: context) else { return }
        // A sync running meanwhile may already have copied the new Hevy
        // workout; Haki's own workout is the original, so drop that copy.
        removeCopies(ofHevyID: created.id, in: context)
        WorkoutStore.markUploaded(uploaded, hevyID: created.id, updatedAt: created.updatedDate, in: context)
    }

    /// After finishing a workout: posts it when connected, uploading is on,
    /// and it's a Haki workout not yet in Hevy. Never throws; a failure ends
    /// up in `lastError`.
    func uploadIfEnabled(_ workout: WorkoutRecord, in context: ModelContext) async {
        guard isConnected, uploadEnabled, workout.source == .haki, workout.hevyID == nil, workout.endedAt != nil else { return }
        let name = workout.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = name.isEmpty ? "your workout" : "“\(name)”"
        do {
            // `upload` runs in its own task, so dismissing the screen that
            // asked doesn't cancel it.
            try await upload(workout, in: context)
        } catch {
            guard !Backend.isCancellation(error) else { return }
            lastError = "Couldn't post \(subject) to Hevy. \(error.localizedDescription)"
        }
    }

    private func liveWorkout(id: UUID, in context: ModelContext) -> WorkoutRecord? {
        let target = id
        var descriptor = FetchDescriptor<WorkoutRecord>(predicate: #Predicate<WorkoutRecord> { $0.id == target })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// Deletes copies (source Hevy) of the Hevy workout `hevyID`.
    private func removeCopies(ofHevyID hevyID: String, in context: ModelContext) {
        let target: String? = hevyID
        let hevySource = WorkoutSource.hevy.rawValue
        let descriptor = FetchDescriptor<WorkoutRecord>(predicate: #Predicate<WorkoutRecord> { $0.hevyID == target && $0.sourceRaw == hevySource })
        let copies = (try? context.fetch(descriptor)) ?? []
        guard !copies.isEmpty else { return }
        for copy in copies {
            context.delete(copy)
        }
        WorkoutStore.save(in: context)
    }
}

// MARK: - Errors

/// Why a workout couldn't be posted to Hevy (besides `HevyClientError`s).
nonisolated enum HevySyncError: LocalizedError, Equatable {
    case notConnected
    case notFromHaki
    case notFinished
    case nothingToUpload
    /// Exercises Hevy doesn't have and that couldn't be added as custom ones.
    case unknownExercises([String], detail: String?)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Connect your Hevy account first."
        case .notFromHaki:
            return "Only workouts logged in Haki can be posted to Hevy."
        case .notFinished:
            return "Finish the workout before posting it to Hevy."
        case .nothingToUpload:
            return "This workout has no completed sets to post."
        case .unknownExercises(let names, let detail):
            let list = names.joined(separator: ", ")
            let pronoun = names.count == 1 ? "it" : "them"
            var message = "Hevy doesn't have \(list), and Haki couldn't add \(pronoun) as custom exercises, so the workout wasn't posted."
            if let detail, !detail.isEmpty {
                message += " " + detail
            }
            return message
        }
    }
}

// MARK: - Upload snapshot

/// What's needed from a logged exercise to post it, copied before any await.
private struct HevyUploadExercise {
    var id: UUID
    var name: String
    var kind: ExerciseKind
    var primaryMuscle: MuscleGroup
    var secondaryMuscles: [MuscleGroup]
    var equipment: Equipment
    var knownTemplateID: String?
    var supersetGroup: Int?
    var notes: String
    var sets: [HevyNewWorkout.SetEntry]
}
