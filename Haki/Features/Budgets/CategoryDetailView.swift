//
//  CategoryDetailView.swift
//  Haki
//
//  PLACEHOLDER: replaced by the feature implementation.
//

import Foundation
import SwiftData
import SwiftUI

struct CategoryDetailView: View {
    let category: TransactionCategory
    let month: MonthInterval

    var body: some View {
        Text("CategoryDetailView")
    }
}

#Preview {
    CategoryDetailView(category: PreviewData.sampleCategory, month: .current())
        .previewEnvironment()
}
