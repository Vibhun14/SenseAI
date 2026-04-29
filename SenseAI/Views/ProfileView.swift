import SwiftUI

struct ProfileView: View {
    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.07).ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color(red: 0.60, green: 0.40, blue: 0.98))
                Text("Your Profile")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Personalization coming soon")
                    .font(.system(size: 14))
                    .foregroundStyle(.gray)
            }
        }
        .navigationTitle("Profile")
    }
}
