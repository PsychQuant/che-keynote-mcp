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
