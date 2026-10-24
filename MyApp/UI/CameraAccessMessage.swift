import SwiftUI
import UIKit

/// Shown over the black camera area when camera access is denied, with a way to fix it.
struct CameraAccessMessage: View {
    static let message = "Magnifier needs camera access. Turn it on in Settings."
    @Environment(\.openURL) private var openURL

    var body: some View {
        GeometryReader { proxy in
            // Scrolls only when the largest accessibility text sizes don't fit above the control panel.
            ScrollView {
                VStack(spacing: 24) {
                    Text(Self.message)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    } label: {
                        Text("Open Settings")
                            .font(.title3.bold())
                            .foregroundStyle(.black)
                            .padding(.horizontal, 28)
                            .frame(minHeight: 52)
                            .background(.white, in: .capsule)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .onAppear { AccessibilityNotification.Announcement(Self.message).post() }
    }
}

#Preview {
    CameraAccessMessage()
        .background(.black)
        .preferredColorScheme(.dark)
}
