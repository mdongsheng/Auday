import AVFoundation
import SwiftUI

struct OnboardingView: View {
    @State private var isRequesting = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            Circle()
                .fill(Theme.accentGradient)
                .frame(width: 420, height: 420)
                .blur(radius: 120)
                .opacity(0.45)
                .offset(y: -280)

            VStack(alignment: .leading, spacing: 28) {
                Spacer()
                GradientIcon(systemName: "waveform", size: 64)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your day, remembered.")
                        .font(Theme.display(34))
                    Text("Auday turns your Apple Watch into an all-day AI memory. Record, transcribe and ask about anything you heard.")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 18) {
                    feature("applewatch", "Record from your wrist", "Tap once on the Watch. Audio syncs to your iPhone.")
                    feature("lock.shield", "Private by design", "Transcription runs on-device. No Auday servers, ever.")
                    feature("heart.text.square", "Context from your body", "Heart rate, stress, sleep and places enrich every memory.")
                    feature("sparkles", "Bring your own model", "Connect any OpenAI-compatible model with your own key.")
                }

                Spacer()

                Button {
                    Task { await requestPermissions() }
                } label: {
                    HStack {
                        if isRequesting { ProgressView().tint(.white) }
                        Text("Get Started").font(Theme.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundStyle(.white)
                    .background(Theme.accentGradient, in: Capsule())
                }
                .disabled(isRequesting)
            }
            .padding(24)
        }
    }

    private func feature(_ icon: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            GradientIcon(systemName: icon, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func requestPermissions() async {
        isRequesting = true
        _ = await AVAudioApplication.requestRecordPermission()
        _ = await Transcriber.requestAuthorization()
        _ = await HealthStore.shared.requestAuthorization()
        LocationTracker.shared.requestAuthorization()
        isRequesting = false
        AppSettings.shared.hasOnboarded = true
    }
}
