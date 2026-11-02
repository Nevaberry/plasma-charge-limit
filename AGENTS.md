# Publishing to KDE Store

- Use Chrome to publish updates at https://store.kde.org/p/2376310.
- Always name the latest stable archive **charge-limit.plasmoid**, without a version in the filename. Keep the actual version in `package/metadata.json` and the store's version fields.
- Replace the existing stable file entry through its **Update** file chooser when uploading a release; do not delete it and create a new file entry for each version.
- After editing the release or its file version/description, use the product editor's **Save** button to publish the changes.
- The file row's **Update** button opens a file chooser to replace the uploaded file. It does not save edited text. Use it only when replacing the package, not after editing the version, description, or changelog.
- Save release notes with **Save Changelog**, then save the product with **Save**.
- Record the existing file entry and download count before uploading. Verify the stable filename, version, package checksum, and download count afterward. Never assume that a fixed filename or **Update** preserves the per-file counter, and never remove the product listing.
- On 2026-10-26, replacing `charge-limit-1.4.0.plasmoid` (file ID `1792354955`, 61 downloads) through **Update** with `charge-limit.plasmoid` created file ID `1793044016` with 0 downloads. Report any counter reset honestly; do not promise preservation based on the filename alone.
