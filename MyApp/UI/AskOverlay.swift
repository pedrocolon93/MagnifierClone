import SwiftUI

/// Overlays for the Ask flow, driven entirely by `AppModel.phase`.
struct AskOverlay: View {
    let model: AppModel
    @Namespace private var pillSpace
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ZStack {
            content
            if showsAnswer { answerOverlay.transition(.opacity) }
        }
        // Fill the screen even when `content` is empty, so the typing pill's inset sits on the keyboard.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) {
            if model.phase == .typing { typingPill }
        }
        .animation(.smooth, value: model.phase)
        .onChange(of: model.phase) { _, new in
            if new != .typing { draft = "" }
        }
    }

    // MARK: - Phases

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .listening(let transcript):
            VStack {
                Button { model.stopListening() } label: {
                    pill(icon: "mic.fill", text: transcript.isEmpty ? "Listening…" : transcript)
                }
                .accessibilityLabel(transcript.isEmpty ? "Listening" : transcript)
                .accessibilityHint("Double tap to stop listening and ask")
                Spacer()
            }
        case .asking(let question):
            VStack(spacing: 12) {
                pill(icon: nil, text: question)
                    .matchedGeometryEffect(id: "pill", in: pillSpace)
                HStack(spacing: 8) {
                    ProgressView().tint(.white)
                    Text("Asking…").font(.headline).foregroundStyle(.white)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(.ultraThinMaterial, in: .capsule)
                .accessibilityElement(children: .combine)
                Spacer()
            }
        case .awaitingCloudConsent:
            consent
        default:
            EmptyView()
        }
    }

    private var consent: some View {
        VStack(spacing: 16) {
            Text("This question needs Apple's Private Cloud Compute. Send this image?")
                .font(.title3).foregroundStyle(.white)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                consentButton("Don't send", prominent: false) { model.respondToCloudConsent(send: false) }
                consentButton("Send", prominent: true) { model.respondToCloudConsent(send: true) }
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 28))
        .padding(.horizontal, 24)
    }

    private func consentButton(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.headline)
                .foregroundStyle(prominent ? .black : .white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(prominent ? Color.white : Color.white.opacity(0.2), in: .capsule)
        }
    }

    // MARK: - Pills

    private func pill(icon: String?, text: String) -> some View {
        HStack(spacing: 10) {
            if let icon { Image(systemName: icon).accessibilityHidden(true) }
            Text(text).font(.headline).multilineTextAlignment(.leading)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(.ultraThinMaterial, in: .capsule)
        .padding(.horizontal, 16)
    }

    private var typingPill: some View {
        HStack(spacing: 8) {
            Button(action: cancel) {
                Image(systemName: "xmark").font(.headline).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Cancel")
            TextField("Ask a question", text: $draft)
                .focused($fieldFocused)
                .submitLabel(.send)
                .onSubmit(send)
                .foregroundStyle(.white)
                .tint(.white)
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 32))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Send")
        }
        .padding(.leading, 6).padding(.trailing, 6)
        .background(.ultraThinMaterial, in: .capsule)
        .matchedGeometryEffect(id: "pill", in: pillSpace)
        .padding(.horizontal, 16).padding(.bottom, 8)
        .defaultFocus($fieldFocused, true)
        .onAppear { fieldFocused = true }
    }

    private func cancel() {
        fieldFocused = false
        withAnimation(.smooth) { model.submit(question: "") }
    }

    private func send() {
        let text = draft
        fieldFocused = false
        withAnimation(.smooth) { model.submit(question: text) }
    }

    // MARK: - Answer

    private var showsAnswer: Bool {
        switch model.phase {
        case .answering, .failed: true
        default: false
        }
    }

    private var answerOverlay: some View {
        let parts = answerParts
        return ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.75).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !parts.question.isEmpty {
                        Text(parts.question).font(.title2.bold())
                    }
                    if let notice = parts.notice {
                        Text(notice).font(.callout).foregroundStyle(.secondary)
                    }
                    Text(parts.body).font(.title3)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 64).padding(.bottom, 32)
            }
            Button { model.dismissAnswer() } label: {
                Image(systemName: "xmark").font(.title3.bold()).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: .circle)
            }
            .padding(12)
            .accessibilityLabel("Close answer")
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .onChange(of: announcement, initial: true) { _, text in
            if let text { AccessibilityNotification.Announcement(text).post() }
        }
    }

    /// Text to announce: a finished answer or a failure message; nil while streaming.
    private var announcement: String? {
        switch model.phase {
        case .answering(_, let answer, _, true): answer
        case .failed(_, let message): message
        default: nil
        }
    }

    private var answerParts: (question: String, notice: String?, body: String, isComplete: Bool) {
        switch model.phase {
        case .answering(let q, let a, let n, let done): (q, n, a, done)
        case .failed(let q, let m): (q, nil, m, false)
        default: ("", nil, "", false)
        }
    }
}
