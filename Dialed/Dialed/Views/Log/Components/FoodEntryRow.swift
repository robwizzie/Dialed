//
//  FoodEntryRow.swift
//  Dialed
//
//  Row component for displaying a food entry
//

import SwiftUI

struct FoodEntryRow: View {
    let entry: FoodEntry
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: entry.timestamp)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Food icon
            VStack {
                Image(systemName: "fork.knife")
                    .font(.caption)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange, .yellow],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .frame(width: 32, height: 32)
            .background(
                Circle()
                    .fill(.orange.opacity(0.1))
            )
            
            // Food info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.name)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    if entry.isSavedMeal {
                        Image(systemName: "bookmark.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.caption2)
                        Text("\(Int(entry.calories))")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    
                    HStack(spacing: 4) {
                        Text("P:")
                            .font(.caption2.bold())
                        Text("\(Int(entry.proteinGrams))g")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    
                    Text(timeString)
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.7))
                }
            }
            
            Spacer()
            
            // Edit button
            Button(action: onEdit) {
                Image(systemName: "pencil.circle.fill")
                    .font(.body)
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(0.05), lineWidth: 0.5)
                )
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

#Preview {
    VStack {
        FoodEntryRow(
            entry: FoodEntry(
                dayDate: Date(),
                name: "Grilled Chicken Salad",
                calories: 450,
                proteinGrams: 42,
                carbsGrams: 20,
                fatGrams: 15
            ),
            onEdit: {},
            onDelete: {}
        )
        
        FoodEntryRow(
            entry: FoodEntry(
                dayDate: Date(),
                name: "Clear Whey Shake",
                calories: 90,
                proteinGrams: 20,
                isSavedMeal: true
            ),
            onEdit: {},
            onDelete: {}
        )
    }
    .padding()
    .background(AppColors.background)
}
