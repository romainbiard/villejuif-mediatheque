// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

#if canImport(VisionKit) && os(iOS)
import DesignSystem
import SwiftUI
import VisionKit

/// Full-screen camera barcode scan: library card, or ISBN for a suggestion.
struct CardScannerView: View {
    var prompt: String = .local("Visez le code-barres au dos de votre carte")
    var detectedTitle: String = .local("Carte détectée")
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var detected: String?

    /// The scanner only exists on a recent device with a camera (not in the simulator).
    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            DataScanner { value in
                if detected == nil { detected = value }
            }
            .ignoresSafeArea()

            VStack(spacing: 14) {
                if let detected {
                    Label(detectedTitle, systemImage: "checkmark.circle.fill")
                        .font(.headline)
                    Text(detected).font(.title3.weight(.semibold)).monospacedDigit().tracking(1)
                    Button(.local("Utiliser ce numéro")) {
                        onScan(detected)
                        dismiss()
                    }
                    .buttonStyle(.prominent(tint: .white, foreground: .ink))
                } else {
                    Text(prompt).font(.headline)
                }
                Button(detected == nil ? String.local("Saisir à la main") : String.local("Recommencer")) {
                    if detected == nil { dismiss() } else { detected = nil }
                }
            }
            .foregroundStyle(.white)
            .padding(20)
            .frame(maxWidth: .infinity)
            .glassEffect(.regular.tint(.black.opacity(0.35)), in: RoundedRectangle(cornerRadius: 34, style: .continuous))
            .padding(12)
        }
        .overlay(alignment: .topLeading) {
            Button(.local("Fermer"), systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .padding(16)
        }
        .sensoryFeedback(.success, trigger: detected != nil)
    }
}

private struct DataScanner: UIViewControllerRepresentable {
    let onBarcode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onBarcode: onBarcode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onBarcode: (String) -> Void

        init(onBarcode: @escaping (String) -> Void) {
            self.onBarcode = onBarcode
        }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            for case let .barcode(barcode) in items {
                if let value = barcode.payloadStringValue, !value.isEmpty {
                    onBarcode(value)
                    return
                }
            }
        }
    }
}
#endif
