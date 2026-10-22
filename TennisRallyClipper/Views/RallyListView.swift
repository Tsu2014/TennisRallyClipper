import SwiftUI

/// 单个回合的行视图，点击可预览跳转。
struct RallyRow: View {
    let rally: Rally
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("回合 \(rally.index + 1)")
                        .font(.headline)
                    Text("\(format(rally.startTime)) → \(format(rally.endTime))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("时长 \(String(format: "%.1f", rally.duration))s · 含前后各 2 秒缓冲")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(Int(rally.confidence * 100))%")
                        .font(.caption)
                        .foregroundColor(.blue)
                    ProgressView(value: rally.confidence)
                        .frame(width: 64)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func format(_ t: Double) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}
