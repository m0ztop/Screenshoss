<h1 align="center">
  <img src="Assets/macapp.png" alt="Screenshoss app icon" width="48" height="48" valign="middle">
  Screenshoss
</h1>

<p align="center">
  A free macOS screenshot shelf that keeps your Desktop clean.
</p>

![Screenshoss running on macOS](docs/assets/screenshoss-hero.png)

Screenshoss is a free macOS screenshot shelf. It watches for Mac screenshots, moves them out of the Desktop, and keeps them in a fast hover panel at the top of the screen.

## What It Does

- Collects new macOS screenshots automatically.
- Keeps your Desktop clean by moving screenshots into the Screenshoss screenshots folder.
- Opens from a small notch-style shelf at the top of the screen.
- Shows recent screenshots in a compact grid.
- Supports folders, drag-and-drop organization, rename, delete, favorite, copy, Finder reveal, and Preview open.
- Includes a favorites view for screenshots you want to keep close.
- Runs locally. No account, cloud sync, analytics, or network service is required.
- Ships as a universal macOS app for Apple Silicon and Intel Macs.

## Download

Download the latest packaged app from [`dist/Screenshoss.dmg`](dist/Screenshoss.dmg).

You can also download [`dist/Screenshoss.app.zip`](dist/Screenshoss.app.zip) if you prefer the zipped app bundle.

## Install

1. Download `Screenshoss.dmg`.
2. Open the DMG.
3. Drag `Screenshoss.app` into `Applications`.
4. Open Screenshoss.

This early build is ad-hoc signed and not notarized yet, so macOS may show an extra confirmation the first time you open it. If that happens, right-click the app and choose **Open**.

## How It Works

When you take a screenshot with macOS, Screenshoss imports supported screenshot image files from your Desktop into:

```text
~/Library/Application Support/Screenshoss/Screenshots
```

On first launch, Screenshoss does not create any custom folders. The shelf starts with **Recent** and the `+` button.

When you create a folder in the app, it maps directly to a subfolder inside the Screenshoss screenshots location:

```text
~/Library/Application Support/Screenshoss/Screenshots/<Your Folder Name>
```

The **Recent** pill shows screenshots that are still in the main Screenshots folder. When you drag a screenshot into a custom folder, it leaves Recent and appears in that folder.

## Using The Shelf

- Hover the notch at the top of the screen to open the screenshot shelf.
- Click a screenshot to select it and see details on the right.
- Double-click a screenshot to open it in Preview.
- Press Space while a screenshot is selected to open macOS Quick Look.
- Shift-click to select a range of screenshots, or Command-click to add/remove individual screenshots.
- Drag screenshots onto folder pills to organize them.
- Drag one selected screenshot to move the whole selection into a folder.
- Click `X` to hide the shelf. This does not quit Screenshoss.
- Use the status bar camera icon to show Screenshoss again.
- Right-click the status bar icon to open the menu with **Open Screenshoss**, **Open Screenshots Folder**, and **Quit Screenshoss**.

## Edit Or Build From Source

If you want to inspect or edit the app:

1. Click **Code** on GitHub.
2. Choose **Download ZIP**.
3. Unzip the project.
4. Open the folder in Xcode or your editor.

Requirements:

- macOS 13 or later
- Xcode with Swift 6.3 support

Run tests:

```bash
swift test
```

Build a fresh universal app, DMG, and app zip:

```bash
scripts/package_dmg.sh
```

The release files will be written to `dist/`.

## Privacy

Screenshoss is local-first. Screenshot files stay on your Mac unless you manually share them. The app does not require a login or upload your screenshots.

## License

MIT. Free to use, modify, and share.
