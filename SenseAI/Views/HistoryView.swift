import SwiftUI

struct HistoryView: View {
    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.07).ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color(red: 0.60, green: 0.40, blue: 0.98))
                Text("History")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Session history will appear here")
                    .font(.system(size: 14))
                    .foregroundStyle(.gray)
            }
        }
        .navigationTitle("History")
    }
}
