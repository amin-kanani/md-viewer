# MD Viewer

A lightweight, native macOS app for viewing rendered Markdown files.

## Features

- Renders `.md` / `.markdown` / `.mdown` / `.mkd` files as styled HTML — headings, paragraphs, emphasis/strong/strikethrough, inline code, fenced code blocks, blockquotes, ordered/unordered/task lists, links, images, tables, and thematic breaks
- Table of Contents sidebar — every heading gets a GitHub-style anchor id, so the collapsible outline in the sidebar (and any in-document `[text](#heading)` link) jumps straight to that section
- Light/dark mode with a toolbar toggle — choose between system (follows your macOS appearance), light, or dark
- Live reload — the preview updates instantly when the file changes on disk, including atomic saves from external editors
- Multiple ways to open a file:
  - `File → Open…` (⌘O)
  - Double-click or "Open With" in Finder
  - Drag a file onto the app icon in the Dock
  - Drop a file onto an already-open window
- External links open in your default browser instead of navigating away inside the preview
- Print support — print the rendered document straight from the toolbar
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
  MarkdownView.swift         Main view; sidebar + toolbar (theme toggle, print) and drag & drop
  TableOfContentsView.swift  Sidebar listing the document's headings; tap to scroll to a section
  Heading.swift              A single extracted heading (id/level/text) used by the TOC sidebar
  RenderState.swift          Watches the file on disk and re-renders on change
  MarkdownRenderer.swift     Wraps the converted HTML with CSS (light/dark mode)
  MarkdownToHTML.swift       Dependency-free Markdown → HTML converter; also assigns heading anchor ids
  MarkdownWebView.swift      WKWebView wrapper; routes clicked links to the default browser (except in-page anchors), scrolls to headings, and handles print
  ThemeMode.swift            Light / dark / system appearance enum
AppResources/                Info.plist and app icon (AppIcon.icns)
DMGResources/                Background image used when styling the DMG
build.sh                     Builds and packages MD Viewer.app
make-dmg.sh                  Packages MD Viewer.app into a distributable MD Viewer.dmg
```

## How it works

MD Viewer is a SwiftUI `DocumentGroup(viewing:)` app: it reads a Markdown file into a `MarkdownDocument`, converts it to HTML with a small hand-written parser (`MarkdownToHTML`), and renders that HTML inside a `WKWebView`. While converting, each heading is assigned a unique, GitHub-style anchor id, which powers both the Table of Contents sidebar and any in-document `#heading` links. A `DispatchSource` file-system monitor watches the file on disk and re-renders automatically when it changes, so edits made in another app appear without reopening.

## Limitations

- Viewer only — there is no editing UI, and the app never writes to your file
- The bundled Markdown converter covers the GitHub-flavored subset used by most real-world documents, rather than full CommonMark spec compliance (for example, raw HTML passthrough isn't supported)
