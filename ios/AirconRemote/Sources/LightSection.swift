import SwiftUI

// 照明（ADR-022）。操作画面の Form に組み込む1セクション。押したボタンを1回だけ送る。
// 状態は持たない（照明の今の状態は誰にもわからない）。
struct LightSection: View {
    @State private var sending: LightButton?
    @State private var outcome: CommandOutcome?

    var body: some View {
        Section("照明") {
            HStack(spacing: 8) {
                ForEach(LightButton.allCases) { button in
                    Button {
                        Task { await send(button) }
                    } label: {
                        VStack(spacing: 4) {
                            if sending == button {
                                ProgressView().frame(height: 22)
                            } else {
                                Image(systemName: button.systemImage).font(.title3).frame(height: 22)
                            }
                            Text(button.label).font(.footnote)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .disabled(sending != nil)
                }
            }

            if let outcome {
                Label(outcome.message, systemImage: outcome.isSuccess ? "checkmark.circle" : "exclamationmark.triangle")
                    .foregroundStyle(outcome.isSuccess ? .green : .orange)
            }
        }
    }

    private func send(_ button: LightButton) async {
        sending = button
        defer { sending = nil }
        outcome = await RemoteActions.sendLight(button)
    }
}
