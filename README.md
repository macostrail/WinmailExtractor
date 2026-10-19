# Winmail Extractor

<p align="center">
  <img src="WinmailExtractor/Design/WinmailExtractor-AppIcon-Source.png" width="128" alt="Winmail Extractor icon">
</p>

A native macOS application designed to extract attachments from `winmail.dat` (Microsoft TNEF format) files.

## Download

Download the latest `WinmailExtractor-*-macOS.zip` from [GitHub Releases](https://github.com). Once downloaded, extract the archive and move the app to your "Applications" folder.

*Note: The current release version is not notarized with an Apple Developer ID. If macOS displays a security warning upon the first launch, right-click (or Control-click) the application in Finder and select "Open".*

The distributed version is a Universal Binary that natively supports both Apple Silicon and Intel Macs.

## Features

- **Automatic Extraction:** Simply open a `winmail.dat` file in Finder to automatically extract attachments directly to `~/Downloads`.
- **Completion Notifications:** Displays a system popup notification showing the names of the successfully extracted files.
- **Conflict Resolution:** Safely appends sequential numbers to filenames if a file with the same name already exists, preventing accidental overwrites.
- **Robust Encoding Support:** Full support for Japanese filenames, Unicode MAPI properties, and various Windows code pages.
- **Flexible UI Controls:** Allows manual file selection, drag-and-drop, and custom destination folder selection directly from the main app window.

## Usage

1. Open `WinmailExtractor.xcodeproj` using Xcode.
2. Run the `WinmailExtractor` scheme, or use **Product -> Archive** to export the compiled application.
3. In Finder, right-click any `winmail.dat` file, select **Open With**, and choose **Winmail Extractor**.
4. From now on, simply double-clicking a `winmail.dat` file will automatically extract its contents to `~/Downloads` in the background without opening the main window. A popup will notify you of the completed extraction and show the saved filenames.

If you launch the Winmail Extractor application directly, the main graphical interface will open as usual. You can then use the "Select winmail.dat..." button or drag-and-drop files from Finder to choose a custom save destination. If a file with the identical name already exists in the target folder, the app automatically appends a number (e.g., `filename (2).ext`) to preserve your existing files.

To set this app as the default handler for all TNEF files, right-click a `winmail.dat` file in Finder, select **Get Info**, choose **Winmail Extractor** under the "Open with" section, and click **Change All...**.

## Requirements

- macOS 13 Ventura or later
- Apple Silicon or Intel Mac
- For development: Xcode 15 or later

## Development Commands

You can run the built-in unit tests via the command line using:

```sh
xcodebuild -project WinmailExtractor.xcodeproj \
  -scheme WinmailExtractor \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO test
```

The TNEF parsing logic is strictly based on Microsoft's official [MS-OXTNEF] specification documentation.

[MS-OXTNEF]: https://microsoft.com

