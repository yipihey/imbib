---
layout: default
title: Share Extension
---

# Share Extension

Save papers to imBib directly from Safari, Chrome, or any app with a Share button.

---

## Overview

The Share Extension lets you capture papers while browsing:

1. Visit a paper page (ADS, arXiv, journal)
2. Tap the Share button
3. Select imBib
4. Paper is saved to your library

No need to copy URLs or switch apps.

---

## Installation

### macOS

1. Open **System Settings**
2. Go to **Privacy & Security** → **Extensions** → **Share Menu**
3. Find **imBib** and enable it
4. The extension appears in Safari's Share menu

If imBib doesn't appear:
- Make sure imBib has been launched at least once
- Try restarting Safari
- Check that imBib is in `/Applications`

### iOS

The Share Extension is automatically available:

1. Open Safari and navigate to a paper
2. Tap the **Share** button
3. Scroll the app row and tap **More**
4. Enable **imBib** in the list
5. Tap **Done**

imBib now appears in your Share sheet.

---

## Using the Extension

### From Safari (macOS)

1. Navigate to a paper page
2. Click the **Share** button in the toolbar (or **File → Share**)
3. Select **imBib**
4. Review the extracted metadata
5. Choose a destination library
6. Click **Save**

### From Safari (iOS)

1. Navigate to a paper page
2. Tap the **Share** button
3. Tap **imBib** in the app row
4. Review the extracted metadata
5. Choose a destination library
6. Tap **Save**

### From Other Apps

Any app with a Share button can send URLs to imBib:
- Chrome, Firefox, Arc
- PDF viewers
- Email clients
- Note-taking apps

---

## Supported URLs

The extension recognizes papers from:

| Source | URL Pattern | Example |
|--------|-------------|---------|
| **NASA ADS** | `ui.adsabs.harvard.edu/abs/...` | Abstract pages |
| **arXiv** | `arxiv.org/abs/...` | Abstract pages |
| **DOI** | `doi.org/10.xxxx/...` | DOI resolver |
| **Journals** | Various publisher sites | Direct article pages |

### URL Extraction

The extension extracts:
- **URL**: The page address
- **Title**: The page title (usually paper title)
- **Metadata**: Fetched from ADS/arXiv/Crossref

---

## What Happens After Sharing

1. **URL Analysis**: imBib identifies the paper source
2. **Metadata Fetch**: Full metadata is retrieved from ADS/Crossref
3. **Library Addition**: Paper is added to your chosen library
4. **PDF Queue**: Paper is queued for PDF download (if available)

The paper appears in your library immediately. PDF download happens in the background.

---

## Tips

### Quick Access (iOS)

Move imBib to the front of your Share sheet:
1. Tap Share
2. Hold and drag the imBib icon left
3. It will stay in that position

### Batch Saving

Save multiple papers efficiently:
1. Open each paper in a new tab
2. Use the Share Extension on each
3. Papers queue and sync in the background

### Offline Use

Shared papers are queued if you're offline. They'll sync when connectivity returns.

---

## Troubleshooting

### Extension Not Appearing

**macOS:**
- Ensure imBib is in `/Applications`, not `~/Downloads`
- Launch imBib at least once
- Check System Settings → Extensions → Share Menu
- Restart Safari

**iOS:**
- Ensure imBib is installed (not just in TestFlight)
- Tap **More** in the Share sheet and enable imBib
- Restart Safari

### "URL Not Recognized"

The extension works best with:
- ADS abstract pages
- arXiv abstract pages
- DOI resolver URLs

For other pages, try:
- Navigate to the abstract page instead of PDF
- Use Quick Lookup in imBib with the DOI

### Paper Not Importing

If metadata isn't found:
- The paper may not be indexed by ADS/Crossref
- Try sharing the DOI resolver URL directly
- Import manually via Quick Lookup (`Cmd-Shift-L`)

### Duplicate Papers

imBib deduplicates by DOI, arXiv ID, and bibcode. If you see duplicates:
- The same paper may have different identifiers
- Check if it's the same paper with different metadata

---

## Privacy

The Share Extension:
- Only processes URLs you explicitly share
- Sends queries to ADS/Crossref to fetch metadata
- Does not track browsing history
- Does not collect analytics

All data stays on your device (and iCloud if sync is enabled).
