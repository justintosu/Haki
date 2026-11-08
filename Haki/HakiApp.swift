//
//  HakiApp.swift
//  Haki
//
//  Created by Justin To on 7/14/26.
//

import Foundation
import SwiftData
import SwiftUI

@main
struct HakiApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try HakiSchema.makeContainer()
        } catch {
            fatalError("Haki couldn't open its database: \(error)")
        }
        LedgerStore.ensureDefaultCategories(in: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
