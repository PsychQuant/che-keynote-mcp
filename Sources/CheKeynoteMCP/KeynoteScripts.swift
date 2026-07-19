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
}
