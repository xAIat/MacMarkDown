import AppKit
import AVFoundation

// MARK: - Read aloud
//
// Speaks the selection, or the whole document when nothing is selected.

extension MarkdownTextView {

    @objc func startSpeaking(_ sender: Any?) {
        stopSpeaking(sender)

        let utterance: AVSpeechUtterance
        if let attributed = textLayoutManager.textSelectionsAttributedString(), attributed.length > 0 {
            utterance = AVSpeechUtterance(attributedString: attributed)
        } else if !string.isEmpty {
            utterance = AVSpeechUtterance(string: string)
        } else {
            return
        }
        utterance.prefersAssistiveTechnologySettings = true
        speechSynthesizer.delegate = speechDelegate
        isSpeaking = true
        speechSynthesizer.speak(utterance)
    }

    @objc func stopSpeaking(_ sender: Any?) {
        guard isSpeaking else { return }
        speechSynthesizer.stopSpeaking(at: .word)
    }
}

/// Delegate object rather than a conformance on `MarkdownTextView` itself:
/// `AVSpeechSynthesizerDelegate` refines `Sendable`, and a `Sendable`
/// conformance on the class must live in the class's own source file.
final class MarkdownSpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {

    private unowned let textView: MarkdownTextView

    init(textView: MarkdownTextView) {
        self.textView = textView
        super.init()
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.textView.isSpeaking = false }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.textView.isSpeaking = false }
    }
}
