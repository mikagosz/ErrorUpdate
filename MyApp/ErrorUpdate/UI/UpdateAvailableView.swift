import SwiftUI

/// Modal view to show available update information.
struct UpdateAvailableView: View {
    @Environment(\.dismiss) private var dismiss
    let info: UpdateInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Dostępna aktualizacja \(info.latestVersion)")
                .font(.headline)

            Text("Release Notes")
                .font(.subheadline.bold())
            ScrollView {
                Text(info.releaseNotes)
                    .font(.subheadline)
            }
            .frame(maxHeight: 200)

            HStack {
                Spacer()
                if info.mandatory {
                    Button("Zainstaluj teraz") {
                        dismiss()
                    }
                } else {
                    Button("Pomiń tę wersję") {
                        dismiss()
                    }
                    Button("Później") {
                        dismiss()
                    }
                    Button("Zainstaluj teraz") {
                        dismiss()
                    }
                }
            }
        }
        .padding()
        .frame(width: 450, height: 380)
    }
}

#if DEBUG
#Preview {
    UpdateAvailableView(info: UpdateInfo(
        latestVersion: "1.1.0",
        available: true,
        releaseNotes: "- Naprawiono awarię przy uruchomieniu\n- Ulepszono wydajność\n- Zaktualizowano biblioteki",
        downloadURL: URL(string: "https://example.com/update.dmg")!,
        sha256: "abc123",
        mandatory: false
    ))
}
#endif
