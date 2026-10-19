# SnippetFormPalette — specification

**Tagline:** Summon a snippet palette by hotkey, fill in a small form of variables, and paste the finished text.

**Category:** Menu Bar Utility

**Inspired by (paid):** Typinator ($29.99/year)

**Frameworks:** SwiftUI, AppKit, Carbon, ApplicationServices, ServiceManagement

**Donation URL (Support button):** https://ko-fi.com/leodavidai

## Spec

What the paid app does and evidence of demand. Typinator by Ergonis is a long-established Mac text expansion tool. Comparison guides list its plans from 29.99 dollars per year, with a one-time license around 49.99 dollars, and it is regularly named as a fast, reliable option for power users, particularly because of its fill-in fields and powerful placeholders. The idea we rebuild is not background abbreviation typing, which is covered by other tools, but an explicit palette for templates that need variables, such as customer replies, meeting notes, or commit messages. Our clean-room version is called SnippetFormPalette.

Feature set. Users define templates with a title and body. The body can include named placeholders written in double curly braces, for example the customer name or the order number. A placeholder can have a default value, written after a colon, and a type that is text, multi-line text, date, or choice from a comma separated list. When a template is chosen, the app shows a small form with one input per placeholder, plus a live preview of the final text. Pressing Command plus Return pastes the result into the previously active app, and Option plus Return only copies it. Built-in variables need no input: today's date in a chosen format, the current time, and the clipboard contents. Templates can be tagged and sorted by how recently they were used. The palette remembers the last values entered for each placeholder if the user turns on that setting.

UI spec. The app is a MenuBarExtra with Open Palette, Manage Templates, Settings, and Quit. The palette is a centered floating panel, 520 by 420 points, opened by a global hotkey, default Option plus Space. Step one is a search field with a result list. Step two replaces the list with the form on the left half and the live preview on the right half, with a Back button. The template manager is a regular window with a list on the left and an editor on the right showing title, tags, and body, with an Insert Placeholder menu and a parse report listing the placeholders detected. Empty state: No templates yet, with a button that adds three examples. Settings fields: hotkey recorder, date format, remember last values toggle, Close after paste toggle, and Launch at login.

Technical approach. Parse placeholders with a regular expression through NSRegularExpression, and build the form dynamically in SwiftUI using a ForEach over parsed fields with a switch on the field type. Date placeholders use DateFormatter with the user's chosen format and optional day offsets. The panel is a nonactivating NSPanel hosting SwiftUI that becomes key for typing. Before opening, store the frontmost application from NSWorkspace so focus can be returned. Paste by writing to the pasteboard, reactivating the previous app, and posting Command plus V with CGEvent, which requires Accessibility permission requested through AXIsProcessTrustedWithOptions with a short explanation. Save the original pasteboard and restore it after about 200 milliseconds when the user enables that option. Templates are stored as JSON in Application Support, and settings in UserDefaults. Launch at login uses SMAppService.mainApp.

Edge cases and error handling. Unclosed or nested braces are shown in the parse report and treated as literal text. Duplicate placeholder names share a single input. If a choice placeholder has no options, fall back to a text input. A missing Accessibility permission degrades to copy only with a toast. Empty required fields are highlighted, and the paste button is disabled until they are filled unless a default exists. Keep the panel responsive with templates up to 20 thousand characters, and support import and export of templates as a JSON file.
