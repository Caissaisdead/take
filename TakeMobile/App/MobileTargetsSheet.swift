import SwiftUI

/// The draft's target and the day's; a field left empty means none.
struct MobileTargetsSheet: View {
    @Environment(ProjectModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var target: Int?
    @State private var daily: Int?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Whole draft") {
                        TextField("e.g. 90,000", value: $target, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Each day") {
                        TextField("e.g. 1,000", value: $daily, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text("\(model.totalWords.formatted()) words on main now; leave a field empty for no target.")
                }
            }
            .navigationTitle("Targets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Set") {
                        model.setTargets(target, daily: daily)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            target = model.manuscript.target
            daily = model.manuscript.dailyTarget
        }
    }
}
