//
//  FoodEntrySheet.swift
//  Dialed
//
//  Sheet for adding or editing food entries
//

import SwiftUI

struct FoodEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let existingEntry: FoodEntry?
    let onSave: (String, Double, Double, Double?, Double?, Bool) -> Void
    
    @State private var name: String = ""
    @State private var calories: String = ""
    @State private var protein: String = ""
    @State private var carbs: String = ""
    @State private var fat: String = ""
    @State private var saveAsMeal: Bool = false
    @State private var showSavedMeals: Bool = false
    
    @FocusState private var focusedField: Field?
    
    enum Field {
        case name, calories, protein, carbs, fat
    }
    
    private var isEditing: Bool {
        existingEntry != nil
    }
    
    private var canSave: Bool {
        !name.isEmpty && !calories.isEmpty && !protein.isEmpty
    }
    
    init(existingEntry: FoodEntry? = nil, onSave: @escaping (String, Double, Double, Double?, Double?, Bool) -> Void) {
        self.existingEntry = existingEntry
        self.onSave = onSave
        
        if let entry = existingEntry {
            _name = State(initialValue: entry.name)
            _calories = State(initialValue: String(Int(entry.calories)))
            _protein = State(initialValue: String(Int(entry.proteinGrams)))
            _carbs = State(initialValue: entry.carbsGrams != nil ? String(Int(entry.carbsGrams!)) : "")
            _fat = State(initialValue: entry.fatGrams != nil ? String(Int(entry.fatGrams!)) : "")
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Quick add saved meals (only when adding new)
                    if !isEditing {
                        savedMealsSection
                    }
                    
                    // Name field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Food Name")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        
                        TextField("e.g., Grilled Chicken", text: $name)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .padding()
                            .background(inputBackground)
                            .focused($focusedField, equals: .name)
                    }
                    
                    // Macros grid
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Nutrition")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        
                        HStack(spacing: 12) {
                            // Calories
                            MacroInputField(
                                label: "Calories",
                                value: $calories,
                                unit: "cal",
                                color: .orange,
                                isRequired: true,
                                isFocused: focusedField == .calories
                            )
                            .focused($focusedField, equals: .calories)
                            
                            // Protein
                            MacroInputField(
                                label: "Protein",
                                value: $protein,
                                unit: "g",
                                color: .blue,
                                isRequired: true,
                                isFocused: focusedField == .protein
                            )
                            .focused($focusedField, equals: .protein)
                        }
                        
                        HStack(spacing: 12) {
                            // Carbs
                            MacroInputField(
                                label: "Carbs",
                                value: $carbs,
                                unit: "g",
                                color: .green,
                                isRequired: false,
                                isFocused: focusedField == .carbs
                            )
                            .focused($focusedField, equals: .carbs)
                            
                            // Fat
                            MacroInputField(
                                label: "Fat",
                                value: $fat,
                                unit: "g",
                                color: .yellow,
                                isRequired: false,
                                isFocused: focusedField == .fat
                            )
                            .focused($focusedField, equals: .fat)
                        }
                    }
                    
                    // Save as meal toggle (only when adding new)
                    if !isEditing {
                        Toggle(isOn: $saveAsMeal) {
                            HStack(spacing: 8) {
                                Image(systemName: "bookmark.fill")
                                    .foregroundStyle(.orange)
                                Text("Save as Quick Meal")
                                    .font(.body)
                                    .foregroundStyle(.primary)
                            }
                        }
                        .padding()
                        .background(inputBackground)
                    }
                }
                .padding()
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle(isEditing ? "Edit Entry" : "Add Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveEntry()
                    }
                    .disabled(!canSave)
                }
                
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Done") {
                            focusedField = nil
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    // MARK: - Saved Meals Section
    
    private var savedMealsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Quick Add")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button(action: { showSavedMeals.toggle() }) {
                    Text(showSavedMeals ? "Hide" : "Show all")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
            
            let meals = SavedMealsManager.load()
            let displayMeals = showSavedMeals ? meals : Array(meals.prefix(3))
            
            if meals.isEmpty {
                Text("No saved meals yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(displayMeals) { meal in
                        Button(action: {
                            fillFromMeal(meal)
                        }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(meal.name)
                                    .font(.caption.bold())
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                
                                HStack(spacing: 8) {
                                    Text("\(Int(meal.calories)) cal")
                                        .font(.caption2)
                                    Text("\(Int(meal.proteinGrams))g P")
                                        .font(.caption2)
                                }
                                .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(.orange.opacity(0.3), lineWidth: 1)
                                    )
                            )
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private var inputBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(white: 0.15))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.white.opacity(0.1), lineWidth: 0.5)
            )
    }
    
    private func fillFromMeal(_ meal: SavedMeal) {
        name = meal.name
        calories = String(Int(meal.calories))
        protein = String(Int(meal.proteinGrams))
        carbs = meal.carbsGrams != nil ? String(Int(meal.carbsGrams!)) : ""
        fat = meal.fatGrams != nil ? String(Int(meal.fatGrams!)) : ""
    }
    
    private func saveEntry() {
        let caloriesValue = Double(calories) ?? 0
        let proteinValue = Double(protein) ?? 0
        let carbsValue = carbs.isEmpty ? nil : Double(carbs)
        let fatValue = fat.isEmpty ? nil : Double(fat)
        
        onSave(name, caloriesValue, proteinValue, carbsValue, fatValue, saveAsMeal)
        dismiss()
    }
}

// MARK: - Macro Input Field

private struct MacroInputField: View {
    let label: String
    @Binding var value: String
    let unit: String
    let color: Color
    let isRequired: Bool
    let isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                
                if isRequired {
                    Text("*")
                        .font(.caption2.bold())
                        .foregroundStyle(.red)
                }
            }
            
            HStack {
                TextField("0", text: $value)
                    .keyboardType(.numberPad)
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(white: 0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isFocused ? color.opacity(0.5) : .white.opacity(0.1), lineWidth: isFocused ? 2 : 0.5)
                    )
            )
        }
    }
}

#Preview {
    FoodEntrySheet(
        existingEntry: nil,
        onSave: { _, _, _, _, _, _ in }
    )
}
