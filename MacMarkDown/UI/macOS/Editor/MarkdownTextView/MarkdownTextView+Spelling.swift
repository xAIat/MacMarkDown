import AppKit

// MARK: - Spell checking
//
// `MarkdownTextView` is not an `NSTextView`, so it does not inherit AppKit's
// spell checking. This lightweight integration asks `NSSpellChecker` for
// misspelled ranges in the document and marks them with a dotted red
// underline. Attributes live only in memory (saving writes plain text), so the
// markup never leaks into the file.

extension MarkdownTextView {

    /// Appends "Spelling" suggestions for the word at `contentPoint`, if any.
    func appendSpellingMenuItems(to menu: NSMenu, at contentPoint: NSPoint) {
        guard isEditable else { return }
        let range = selectedRange()
        guard range.length > 0 else { return }
        let word = (string as NSString).substring(with: range)
        guard !word.isEmpty,
              let guesses = NSSpellChecker.shared.guesses(
                  forWordRange: range,
                  in: string,
                  language: nil,
                  inSpellDocumentWithTag: 0
              ),
              !guesses.isEmpty
        else { return }
        menu.addItem(.separator())
        for guess in guesses.prefix(5) {
            let item = NSMenuItem(title: guess, action: #selector(replaceSpellingWithGuess(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = guess
            menu.addItem(item)
        }
    }

    @objc private func replaceSpellingWithGuess(_ sender: NSMenuItem) {
        guard let guess = sender.representedObject as? String else { return }
        let range = selectedRange()
        guard range.length > 0 else { return }
        replaceCharacters(in: range, with: guess)
        setSelectedRange(NSRange(location: range.location, length: (guess as NSString).length))
    }


    /// Misspelled ranges from the most recent check.
    var spellingRanges: [NSRange] {
        get { _spellingRanges }
        set { _spellingRanges = newValue }
    }

    /// Runs a spelling pass over the whole document. Call after edits and when
    /// the preference changes.
    func updateSpelling() {
        guard isContinuousSpellCheckingEnabled, textContentStorage.documentLength > 0 else {
            clearSpellingMarks()
            return
        }
        let text = string
        let checker = NSSpellChecker.shared
        var ranges: [NSRange] = []
        var searchStart = 0
        let ns = text as NSString
        while searchStart < ns.length {
            let range = checker.checkSpelling(
                of: text,
                startingAt: searchStart,
                language: nil,
                wrap: false,
                inSpellDocumentWithTag: 0,
                wordCount: nil
            )
            guard range.location != NSNotFound, range.length > 0 else { break }
            ranges.append(range)
            searchStart = range.location + range.length
        }
        applySpellingMarks(ranges)
    }

    private func applySpellingMarks(_ ranges: [NSRange]) {
        guard let storage = textStorage else { return }
        clearSpellingMarks()
        for range in ranges where NSMaxRange(range) <= storage.length {
            storage.addAttributes(
                [
                    .underlineStyle: NSUnderlineStyle.thick.rawValue
                        | NSUnderlineStyle.patternDot.rawValue,
                    .underlineColor: NSColor.systemRed,
                    .spellingState: NSAttributedString.SpellingState.spelling.rawValue
                ],
                range: range
            )
        }
        _spellingRanges = ranges
        needsDisplay = true
    }

    /// Removes the dotted underlines (without disturbing the syntax colors).
    func clearSpellingMarks() {
        guard let storage = textStorage, !_spellingRanges.isEmpty else { return }
        for range in _spellingRanges where NSMaxRange(range) <= storage.length {
            storage.removeAttribute(.underlineStyle, range: range)
            storage.removeAttribute(.underlineColor, range: range)
            storage.removeAttribute(.spellingState, range: range)
        }
        _spellingRanges = []
    }
}