import Foundation

/// AppleScript source templates for Keynote operations. Pure functions —
/// script ASSEMBLY only (execution lives in KeynoteController). All user
/// content is interpolated exclusively through `KeynoteController.quoted(_:)`
/// (design D3); numeric indices are validated Ints and interpolate directly.
enum KeynoteScripts {

    /// Sets the title (default title item) of a slide.
    static func setSlideTitle(documentName: String, slideIndex: Int, title: String) -> String {
        """
        tell application "Keynote"
            tell document \(KeynoteController.quoted(documentName))
                tell slide \(slideIndex)
                    set object text of default title item to \(KeynoteController.quoted(title))
                end tell
            end tell
        end tell
        """
    }

    // MARK: - Presentation lifecycle

    static func createPresentation(theme: String?) -> String {
        let make = theme.map {
            "set d to make new document with properties {document theme: theme \(KeynoteController.quoted($0))}"
        } ?? "set d to make new document"
        return """
        tell application "Keynote"
            \(make)
            return name of d
        end tell
        """
    }

    static func openPresentation(path: String) -> String {
        """
        tell application "Keynote"
            set d to open (POSIX file \(KeynoteController.quoted(path)))
            return name of d
        end tell
        """
    }

    static func savePresentation(documentName: String, path: String?) -> String {
        let save = path.map {
            "save document \(KeynoteController.quoted(documentName)) in (POSIX file \(KeynoteController.quoted($0)))"
        } ?? "save document \(KeynoteController.quoted(documentName))"
        return """
        tell application "Keynote"
            \(save)
            return "saved"
        end tell
        """
    }

    static func closePresentation(documentName: String, discardingChanges: Bool) -> String {
        """
        tell application "Keynote"
            close document \(KeynoteController.quoted(documentName)) saving \(discardingChanges ? "no" : "yes")
            return "closed"
        end tell
        """
    }

    static func listPresentations() -> String {
        """
        tell application "Keynote"
            return name of every document
        end tell
        """
    }

    static func presentationInfo(documentName: String) -> String {
        """
        tell application "Keynote"
            tell document \(KeynoteController.quoted(documentName))
                return {name, count of slides, name of document theme}
            end tell
        end tell
        """
    }
}

// MARK: - Slide CRUD (appended by task 3.2)

extension KeynoteScripts {

    static func addSlide(documentName: String, layout: String?) -> String {
        let make = layout.map {
            "set s to make new slide with properties {base layout: slide layout \(KeynoteController.quoted($0))}"
        } ?? "set s to make new slide"
        return """
        tell application "Keynote"
            tell document \(KeynoteController.quoted(documentName))
                \(make)
                return slide number of s
            end tell
        end tell
        """
    }

    static func deleteSlide(documentName: String, slideIndex: Int) -> String {
        """
        tell application "Keynote"
            tell document \(KeynoteController.quoted(documentName))
                delete slide \(slideIndex)
                return "deleted"
            end tell
        end tell
        """
    }

    static func duplicateSlide(documentName: String, slideIndex: Int) -> String {
        """
        tell application "Keynote"
            tell document \(KeynoteController.quoted(documentName))
                set s to duplicate slide \(slideIndex)
                return slide number of s
            end tell
        end tell
        """
    }

    static func moveSlide(documentName: String, from: Int, toBefore: Int) -> String {
        """
        tell application "Keynote"
            tell document \(KeynoteController.quoted(documentName))
                move slide \(from) to before slide \(toBefore)
                return "moved"
            end tell
        end tell
        """
    }

    static func setSlideSkipped(documentName: String, slideIndex: Int, skipped: Bool) -> String {
        """
        tell application "Keynote"
            tell document \(KeynoteController.quoted(documentName))
                set skipped of slide \(slideIndex) to \(skipped)
                return "ok"
            end tell
        end tell
        """
    }

    static func slideCount(documentName: String) -> String {
        """
        tell application "Keynote"
            return count of slides of document \(KeynoteController.quoted(documentName))
        end tell
        """
    }

    static func slideInfo(documentName: String, slideIndex: Int) -> String {
        """
        tell application "Keynote"
            tell document \(KeynoteController.quoted(documentName))
                tell slide \(slideIndex)
                    return {slide number, name of base layout, skipped, object text of default title item, count of text items, count of images}
                end tell
            end tell
        end tell
        """
    }

    /// Batched slide listing (design D4 — one script per batch of `batchSize`
    /// slides, never one AppleEvent per slide). Each script returns parallel
    /// lists {slide numbers, skipped flags, title texts} for its range.
    static func listSlidesBatches(documentName: String, slideCount: Int, batchSize: Int = 20) -> [String] {
        guard slideCount > 0 else { return [] }
        let indices = Array(1...slideCount)
        return KeynoteController.batches(indices, size: batchSize).map { batch in
            let lo = batch.first!, hi = batch.last!
            return """
            tell application "Keynote"
                tell document \(KeynoteController.quoted(documentName))
                    return {slide number of slides \(lo) thru \(hi), skipped of slides \(lo) thru \(hi), object text of default title item of slides \(lo) thru \(hi)}
                end tell
            end tell
            """
        }
    }
}

// MARK: - Content (appended by task 3.3)

extension KeynoteScripts {

    static func setSlideBody(documentName: String, slideIndex: Int, body: String) -> String {
        """
        tell application "Keynote"
            tell document \(KeynoteController.quoted(documentName))
                tell slide \(slideIndex)
                    set object text of default body item to \(KeynoteController.quoted(body))
                end tell
            end tell
        end tell
        """
    }

    static func addTextItem(documentName: String, slideIndex: Int, text: String) -> String {
        """
        tell application "Keynote"
            tell document \(KeynoteController.quoted(documentName))
                tell slide \(slideIndex)
                    make new text item with properties {object text: \(KeynoteController.quoted(text))}
                    return count of text items
                end tell
            end tell
        end tell
        """
    }

    static func setTextItem(documentName: String, slideIndex: Int, itemIndex: Int, text: String) -> String {
        """
        tell application "Keynote"
            tell document \(KeynoteController.quoted(documentName))
                tell slide \(slideIndex)
                    set object text of text item \(itemIndex) to \(KeynoteController.quoted(text))
                end tell
            end tell
        end tell
        """
    }

    static func listTextItems(documentName: String, slideIndex: Int) -> String {
        """
        tell application "Keynote"
            tell document \(KeynoteController.quoted(documentName))
                tell slide \(slideIndex)
                    return object text of every text item
                end tell
            end tell
        end tell
        """
    }

    static func addImage(documentName: String, slideIndex: Int, path: String) -> String {
        """
        tell application "Keynote"
            tell document \(KeynoteController.quoted(documentName))
                tell slide \(slideIndex)
                    make new image with properties {file: POSIX file \(KeynoteController.quoted(path))}
                    return count of images
                end tell
            end tell
        end tell
        """
    }
}
