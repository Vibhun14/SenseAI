import SwiftUI
import UniformTypeIdentifiers

// MARK: - Import Session
// Holds URLs selected by the user before loading into the engine
struct HarmoniImportSession {
    var jsonURL:   URL? = nil
    var audioURL:  URL? = nil
    var drumsURL:  URL? = nil
    var bassURL:   URL? = nil
    var vocalsURL: URL? = nil
    var otherURL:  URL? = nil

    var isReadyToLoad: Bool { jsonURL != nil && audioURL != nil }
}

// MARK: - Import Flow View
struct HarmoniImportView: View {
    @Binding var session: HarmoniImportSession
    let onLoad: () -> Void

    @State private var pickingFile: PickTarget? = nil

    enum PickTarget: Identifiable {
        case json, audio, drums, bass, vocals, other
        var id: Self { self }

        var label: String {
            switch self {
            case .json:   return "Stem Data JSON"
            case .audio:  return "Full Song (mp3/wav/m4a)"
            case .drums:  return "Drums Stem"
            case .bass:   return "Bass Stem"
            case .vocals: return "Vocals Stem"
            case .other:  return "Other Stem"
            }
        }

        var types: [UTType] {
            switch self {
            case .json:   return [.json]
            case .audio, .drums, .bass, .vocals, .other:
                return [.audio, .mp3, UTType(filenameExtension: "m4a") ?? .audio,
                        UTType(filenameExtension: "wav") ?? .audio]
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            Text("IMPORT FILES")
                .font(.system(size: 11, weight: .medium))
                .tracking(1.4)
                .foregroundStyle(Color.gray.opacity(0.5))
                .padding(.bottom, 12)

            // Required files
            Text("Required")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(red: 0.20, green: 0.83, blue: 0.60))
                .padding(.bottom, 8)

            ImportRow(target: .json,  session: $session, pickingFile: $pickingFile)
            ImportRow(target: .audio, session: $session, pickingFile: $pickingFile)

            Divider()
                .background(Color.white.opacity(0.06))
                .padding(.vertical, 12)

            // Optional stem files
            Text("Optional — for stem toggle mode")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.gray.opacity(0.6))
                .padding(.bottom, 8)

            ImportRow(target: .drums,  session: $session, pickingFile: $pickingFile)
            ImportRow(target: .bass,   session: $session, pickingFile: $pickingFile)
            ImportRow(target: .vocals, session: $session, pickingFile: $pickingFile)
            ImportRow(target: .other,  session: $session, pickingFile: $pickingFile)

            Spacer(minLength: 20)

            // Load button
            Button(action: onLoad) {
                HStack(spacing: 8) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Load Song")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(session.isReadyToLoad ? .black : Color.gray)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(session.isReadyToLoad
                            ? Color(red: 0.20, green: 0.83, blue: 0.60)
                            : Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .animation(.easeInOut(duration: 0.15), value: session.isReadyToLoad)
            }
            .disabled(!session.isReadyToLoad)

            Text("Process your song in the HarmoniAI Colab notebook first to generate the JSON file.")
                .font(.system(size: 11))
                .foregroundStyle(Color.gray.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.top, 8)
        }
        .padding(16)
        .background(Color(red: 0.07, green: 0.07, blue: 0.10))
        .overlay(RoundedRectangle(cornerRadius: 20)
            .stroke(Color.white.opacity(0.06), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .sheet(item: $pickingFile) { target in
            DocumentPicker(types: target.types) { url in
                switch target {
                case .json:   session.jsonURL   = url
                case .audio:  session.audioURL  = url
                case .drums:  session.drumsURL  = url
                case .bass:   session.bassURL   = url
                case .vocals: session.vocalsURL = url
                case .other:  session.otherURL  = url
                }
                pickingFile = nil
            }
        }
    }
}

// MARK: - Import Row
struct ImportRow: View {
    let target: HarmoniImportView.PickTarget
    @Binding var session: HarmoniImportSession
    @Binding var pickingFile: HarmoniImportView.PickTarget?

    private var selectedURL: URL? {
        switch target {
        case .json:   return session.jsonURL
        case .audio:  return session.audioURL
        case .drums:  return session.drumsURL
        case .bass:   return session.bassURL
        case .vocals: return session.vocalsURL
        case .other:  return session.otherURL
        }
    }

    var body: some View {
        Button(action: { pickingFile = target }) {
            HStack(spacing: 12) {
                Image(systemName: selectedURL != nil ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(selectedURL != nil
                                     ? Color(red: 0.20, green: 0.83, blue: 0.60)
                                     : Color.gray.opacity(0.4))

                VStack(alignment: .leading, spacing: 2) {
                    Text(target.label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                    if let url = selectedURL {
                        Text(url.lastPathComponent)
                            .font(.system(size: 11))
                            .foregroundStyle(Color(red: 0.20, green: 0.83, blue: 0.60).opacity(0.8))
                            .lineLimit(1)
                    } else {
                        Text("Tap to select")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.gray.opacity(0.4))
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.gray.opacity(0.3))
            }
            .padding(.vertical, 10)
        }
    }
}

// MARK: - UIKit Document Picker Wrapper
struct DocumentPicker: UIViewControllerRepresentable {
    let types: [UTType]
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController,
                                 context: Context) {}

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                             didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            // Start security-scoped access
            let accessed = url.startAccessingSecurityScopedResource()
            // Copy to temp directory so we own it
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: temp)
            try? FileManager.default.copyItem(at: url, to: temp)
            if accessed { url.stopAccessingSecurityScopedResource() }
            onPick(temp)
        }
    }
}
