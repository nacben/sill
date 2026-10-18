# Clipboard images (generation 2)

Both updated apps share copied images as well as text. On iOS, tap the system Paste button in the clipboard chip or Settings to send a copy to the Mac, then use Command-V in the destination app. Copying an image on the Mac sends it to subscribed image-capable devices automatically while sharing is on.

## Compatibility and wire limits

Kind 32 and the existing optional `image: Data?` stay unchanged. A host advertises `WindowList.clipboard = 2`. An updated device subscribes with `{"accepts":2}` only when that host supports generation 2. A legacy `{}` subscription receives text only. Every subsequent device text or image message retains its accepts flag. Changing host capabilities forces a new subscription.

`ClipboardImage` downsamples source PNG, JPEG, TIFF and HEIC/HEIF representations with ImageIO, applies orientation, and re-encodes without source metadata. Transparent images use PNG and opaque images JPEG. Output is at most 2048 pixels per side and 700 KiB, shrinking further for noisy images. The base64 JSON remains within the existing 1 MiB message cap. Sources over 32 MiB or 100 million pixels are rejected. Receivers check both compressed size and dimensions, format and decodability before writing to their pasteboards. Animation is reduced to its first frame. Files referenced only by URL are not opened.

A valid image wins over text supplied alongside it; a failed image does not silently paste a file name or caption. Existing 256 KiB text limits and four messages per second remain in effect. Stop still wins over content and rate limiting.

## Privacy and asynchronous work

The Mac checks concealed, transient, remote and own-write markers before reading either image or text. The general pasteboard is read only when macOS permits background reads. Device copies are written with currentHostOnly, and a launch marker prevents echoes. Images are forwarded only to other image-capable subscribers.

iOS reads only hasImages/hasStrings and changeCount automatically. Actual contents come from the system Paste button's NSItemProviders after a tap; image conversion runs off the main queue. Disconnecting, turning sharing off, changing the clipboard or timing out invalidates a pending paste. Received images use localOnly and the same ten-minute expiry as text; the handled change count and last-sent bytes prevent echoes. Clipboard contents are never logged.

## Checks

`Tests/checks/clipboard-images/run.sh` exercises actual image encoding and policy rules without touching the system clipboard. `Tests/checks/clipboard/run.sh` retains the text, privacy, subscription and receipt regression checks. `Tests/clipboard-images/run.sh` uses three loopback clients and a private named Mac pasteboard to check native writes, image delivery, legacy filtering, concealment and stop. It never accesses the general pasteboard. Release builds compile both host and iOS paths.
