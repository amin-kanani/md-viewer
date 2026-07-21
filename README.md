# MD Viewer

A lightweight, native macOS app for viewing rendered Markdown files.

## Features

- Renders `.md` / `.markdown` / `.mdown` / `.mkd` files as styled HTML — headings, paragraphs, emphasis/strong/strikethrough, inline code, fenced code blocks, blockquotes, ordered/unordered/task lists, links, images, tables, and thematic breaks
- Automatic light/dark mode to match your system appearance
- Live reload — the preview updates instantly when the file changes on disk, including atomic saves from external editors
- Multiple ways to open a file:
  - `File → Open…` (⌘O)
  - Double-click or "Open With" in Finder
  - Drag a file onto the app icon in the Dock
  - Drop a file onto an already-open window
- External links open in your default browser instead of navigating away inside the preview
- Read-only viewer — it never modifies your source file
- Ships with its own dependency-free Markdown → HTML renderer, so there are no third-party packages to fetch

## Requirements

- macOS 13 (Ventura) or later
- Swift 5.10+ toolchain to build from source (Xcode 15+, or the Command Line Tools)

## Installation

### Build from source

```bash
git clone https://github.com/amin-kanani/md-viewer.git
cd md-viewer
./build.sh
```

This compiles the app and packages it as `MD Viewer.app` in the project root, ad-hoc code-signs it, and registers it with Launch Services so Finder/"Open With" picks it up. Then launch it:

```bash
open "MD Viewer.app"                     # launch normally
open "MD Viewer.app" path/to/file.md     # open a specific file directly
```

### Create a shareable DMG

```bash
./make-dmg.sh
```

Packages `MD Viewer.app` (built above) into a styled `MD Viewer.dmg` — a Finder window with the app next to an `Applications` shortcut for drag-to-install — that you can share with others.

> **Note:** the app is only ad-hoc signed (no Apple Developer account is involved). Recipients will see a Gatekeeper "unidentified developer" warning on first launch; they can right-click → Open (or approve it under System Settings → Privacy & Security) once to bypass it.

## Project structure

```
Package.swift               Swift package manifest (executable target)
Sources/MDViewer/
  MDViewerApp.swift          App entry point (SwiftUI DocumentGroup)
  MarkdownDocument.swift     Read-only FileDocument for .md files
  MarkdownView.swift         Main view; handles drag & drop
  RenderState.swift          Watches the file on disk and re-renders on change
  MarkdownRenderer.swift     Wraps the converted HTML with CSS (light/dark mode)
  MarkdownToHTML.swift       Dependency-free Markdown → HTML converter
  MarkdownWebView.swift      WKWebView wrapper; routes clicked links to the default browser
AppResources/                Info.plist and app icon (AppIcon.icns)
DMGResources/                Background image used when styling the DMG
build.sh                     Builds and packages MD Viewer.app
make-dmg.sh                  Packages MD Viewer.app into a distributable MD Viewer.dmg
```

## How it works

MD Viewer is a SwiftUI `DocumentGroup(viewing:)` app: it reads a Markdown file into a `MarkdownDocument`, converts it to HTML with a small hand-written parser (`MarkdownToHTML`), and renders that HTML inside a `WKWebView`. A `DispatchSource` file-system monitor watches the file on disk and re-renders automatically when it changes, so edits made in another app appear without reopening.

## Limitations

- Viewer only — there is no editing UI, and the app never writes to your file
- The bundled Markdown converter covers the GitHub-flavored subset used by most real-world documents, rather than full CommonMark spec compliance (for example, raw HTML passthrough isn't supported)
