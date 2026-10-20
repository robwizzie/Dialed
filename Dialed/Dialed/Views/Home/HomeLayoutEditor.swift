//
//  HomeLayoutEditor.swift
//  Dialed
//
//  Drag Home's cards into the order you want and hide the ones you don't
//  use. Changes apply as you make them.
//

import SwiftUI

struct HomeLayoutEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var layout = HomeLayout.load()
    /// In a sheet it brings its own navigation bar; pushed from Settings it doesn't.
    var inSheet = true

    var body: some View {
        if inSheet {
            NavigationStack { list }
        } else {
            list
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(layout.order) { section in
                    row(section)
                }
                .onMove { from, to in
                    layout.move(from: from, to: to)
                    layout.save()
                }
            } footer: {
                Text("Drag to reorder. Tap the eye to show or hide a card. Some cards only appear at certain times.")
            }
            Section {
                Button("Reset to default") {
                    HomeLayout.reset()
                    withAnimation { layout = .standard }
                }
                .foregroundColor(Neka.rose)
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Customize Home")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if inSheet {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }

    private func row(_ section: HomeSection) -> some View {
        let shown = !layout.hidden.contains(section)
        return HStack(spacing: 12) {
            Image(systemName: section.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(shown ? Neka.ink : Neka.inkTertiary)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Neka.track))
            VStack(alignment: .leading, spacing: 1) {
                Text(section.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(shown ? Neka.ink : Neka.inkTertiary)
                if let note = section.note {
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundColor(Neka.inkTertiary)
                }
            }
            Spacer()
            Button {
                withAnimation(.easeOut(duration: 0.2)) { layout.toggle(section) }
                layout.save()
                #if os(iOS)
                UISelectionFeedbackGenerator().selectionChanged()
                #endif
            } label: {
                Image(systemName: shown ? "eye.fill" : "eye.slash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(shown ? Neka.greenText : Neka.inkTertiary)
                    .frame(width: 36, height: 32)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(shown ? "Hide \(section.title)" : "Show \(section.title)")
        }
    }
}
