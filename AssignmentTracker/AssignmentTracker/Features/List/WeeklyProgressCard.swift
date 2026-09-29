import SwiftUI

struct WeeklyProgressCard: View {
    let done: Int
    let total: Int

    private var remaining: Int { total - done }
    private var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }

    private var headline: String {
        if total == 0 { return "Nothing due" }
        if remaining == 0 { return "All done" }
        return "\(remaining) to go"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("This week")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Palette.secondaryText)
                    Text(headline)
                        .font(.system(size: 28, weight: .bold))
                        .tracking(-0.5)
                        .contentTransition(.numericText())
                }
                Spacer()
                Text("\(done) of \(total) done")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.secondaryText)
                    .contentTransition(.numericText())
            }

            Capsule()
                .fill(Palette.track)
                .frame(height: 6)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(.tint)
                            .frame(width: proxy.size.width * fraction)
                    }
                }
                .clipShape(.capsule)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .glassCard(cornerRadius: 26)
        .animation(.snappy, value: done)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This week")
        .accessibilityValue("\(headline). \(done) of \(total) done")
    }
}

#Preview {
    WeeklyProgressCard(done: 2, total: 5)
        .padding()
        .background { AmbientBackground() }
}
