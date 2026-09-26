# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.0.0] - 2026-09-26

A rewrite of the archived app as a maintained native macOS fork, built with
Swift 6 and Swift Package Manager.

### Added

- Universal app for Intel and Apple Silicon Macs.
- Interface localized into the 20 PlayStation 3 system languages: Danish,
  Dutch, English (United Kingdom), English (United States), Finnish, French,
  German, Italian, Japanese, Korean, Norwegian, Polish, Portuguese (Brazil),
  Portuguese (Portugal), Russian, Simplified Chinese, Spanish, Swedish,
  Traditional Chinese, and Turkish.
- Downloads view with Pause, Resume, Restart, Retry Extraction, Remove, and
  Reveal in Finder, offered according to each download's state, plus
  VoiceOver labels and progress values.
- Download verification before a file is installed: HTTP status, content type,
  expected size, SHA-256 when the catalog provides it, and RAP payload size.
- PlayStation Mobile Games and PSP DLC catalogs, with a PlayStation Mobile
  sidebar section.
- Bookmark export to CSV, including bookmarks whose items left the catalog
  (#67).
- Bookmark sorting and filtering.
- Item inspector with labelled details (Title ID, Console, Type, Region, Size,
  Content ID) that can be shown or hidden (⌥⌘I).
- View menu commands to show or hide the sidebar (⌃⌘S) and the inspector.
- Extracted folders named after the game title and title ID.
- Compatibility packs download together with their matching patch, and a
  patch on its own is overlaid onto the existing output.
- Import of the download queue and bookmarks from 1.4.x; the database is
  backed up before it is upgraded, and a failed upgrade leaves it untouched.

### Changed

- Requires macOS 10.15 or later.
- Interface redesigned to the macOS Human Interface Guidelines: an icon-only
  toolbar, a full-height sidebar, and the window title showing the current
  section with its item count.
- Preferences became a Settings window that applies changes immediately and
  shows invalid catalog URLs inline, without Save or Cancel buttons.
- Reload Catalog moved to the File menu (⌘R); the Database menu is gone.
- Catalog feeds default to HTTPS.
- A changed download folder applies to new downloads immediately; queued
  downloads keep the folder they were created with (#49).
- The Concurrent Downloads setting limits simultaneous transfers (#39).
- Download file names are sanitized and never overwrite an existing file; PS3
  packages are named after the game title (adapted from #66).
- Rapid repeated download requests for the same item queue one download.
- Downloads without usable resume data offer Restart instead of failing to
  resume.
- PS3 PKG extraction reports that it is unsupported and keeps the downloaded
  package.
- Extraction runs in the background, so the window stays responsive.
- The bundled `pkg2zip` comes from the maintained
  [lusid1/pkg2zip](https://github.com/lusid1/pkg2zip) fork instead of the
  archived mmozeiko original.
- PS Vita themes now extract, into the background-download layout
  (`bgdl/t/<task>/<title ID>`) that the lusid1 fork uses by default.
- Bookmarks are written to the database as soon as they change.

### Removed

- Xcode project and Carthage dependencies; the app builds with Swift Package
  Manager only (#27, #70).
- The bundled Intel-only `pkg2zip` and `vitanpupdatelinks` executables;
  `pkg2zip` is now built from source for both architectures, and update links
  are computed in the app.
- Game artwork in the details panel.
- Support for macOS 10.11 through 10.14.

### Fixed

- Server error pages and XML documents are no longer saved as package files
  (#76).
- Corrupted downloads are detected by size and checksum and are not installed
  (#47).
- Reveal in Finder is offered only when the completed file exists, including
  after an external volume is reconnected.
- Transfer errors show their actual reason instead of a generic message.

### Security

- App Transport Security allows plain HTTP only for the specific Sony update
  and package hosts; arbitrary loads stay disabled.
- `pkg2zip` output and compatibility archives reject path traversal, absolute
  paths, and symbolic-link escapes.
- The bundled `pkg2zip` fixes the PSP disc ID buffer overflow reported as
  [lusid1/pkg2zip#14](https://github.com/lusid1/pkg2zip/issues/14) and bounds
  the other strings it copies from `PARAM.SFO`.
- The bundled `pkg2zip` also checks the offsets it reads from PS3-hosted PSX
  headers, PSP EDAT, theme and `KEYS.BIN` items, RIF content IDs and the item
  table; reads no uninitialized memory for packages without `PARAM.SFO`; does
  not follow symbolic links when picking a theme download folder; and writes
  `body.bin` once when a Vita package contains both `digs.bin` and `cert.bin`,
  without duplicate ZIP entries.

## [1.4.6] - 2020-06-24

### Fixed

- A 404 page was saved instead of the RAP file when downloading RAPs (#64).

## [1.4.5] - 2019-09-11

### Fixed

- Merged an update to fix localization files (@L1cardo)
- Merged a fix for PSV Themes throwing an error about a missing update URL
(@AnalogMan151)

## [1.4.4] - 2019-06-28

### Added

- Simplified Chinese localization (Thanks L1cardo!)

### Changed

- macOS 10.10 is no longer supported. App now requires 10.11 to run
- Removed the Update Checker functionality, it didn't always work. May
  reimplement this in the future.
- UI tweaks in Preferences window
- NPS URLs have been hardcoded

### Fixed

- Fixed a random crash bug related to loading progress window.
- Fixed app crash if an external path used for storing the downloads is not
  available. Now defaults to Downloads folder.

## [1.4.3] - 2018-08-31

### Added

- Menu option for showing and hiding the sidebar.
- DB migrations for future changes to the database

### Changed

- Code refactoring and cleanup.

### Fixed

- "Show In Finder" button on completed downloads weren't using the correct path
- Bookmarks are now working properly. Bookmarks were being orphaned when the DB
  is refreshed. Now, bookmarks are given a UUID created from the region/
  fileType/titleId/contentId of the item.
- "Compat Patches" label in Preferences was slightly overlapped in OS X 10.10
- Download button was displayed over DL options on OS X 10.10
- Artwork images weren't displaying immediately upon startup on OS X 10.10
- Artwork would sometimes just stop appearing altogether on OS X 10.10
- Buttons to resume/stop/view downloaded items weren't showing on OS X 10.10
- Downloads button was enlarged on macOS 10.14 Mojave

## [1.4.2] - 2018-08-18

### Added

- Application can now check for new application updates automatically and
  download them.
- URL validation on source URLs.
- Game artwork is now fetched directly from the Sony servers. This gives us way
  faster image loading and reduces resource usage.

### Changed

- Reload button is no longer located in the toolbar. There is a menu titled
  "Database" that contains an option to reload. There is also a keyboard
  shortcut available - ⌘R
- Preferences window layout. Is now more legible and is broken up into
  different setting groups.
- Added a minimum window width to prevent toolbar items from collapsing into an
  unusable menu
- Changed how user preferences are stored. No more losing your saved
  configuration after upgrading to the latest version!

### Fixed

- Bug where users running on Mac OS 10.10 Yosemite would have the UI elements
  placed on top of each other, making the app almost impossible to use.
- Changed downloads icon to an image that's compatible with macOS 10.10
- Bug where if a game didn't have an update on PSN it would crash

## [1.4.1] - 2018-08-13

### Changed

- Changed placeholder image for game artwork

### Fixed

- Bug causing app to crash if no game artwork was found on Renascene.
- Some PSV titles that are cart-only with no zrif weren't being filtered out

## [1.4.0] - 2018-08-12

### Added

- **NOW COMPATIBLE WITH OS 10.10+**
- The side panel is now split horizontally, with the game artwork displayed on
  the bottom panel. Artwork is taken from Renascene

### Changed

- Database has been changed over from Core Data to Realm. This allows for the
  database to be Apple-independant and code can be used in future Android and
  Linux ports.
- Massive code refactoring, cleanup, and optimization

### Fixed

- "Game" label for download checkbox now changes to fileType (DLC, Theme, etc)
- Required FW is now properly formatted to the thousandths place if the FW is
  missing the second decimal place. Eg. 3.2 -> 3.20

## [1.3.7] - 2018-08-04

### Added

- Downloads/extractions are separated into folders based on console type

### Changed

- Location label in the Preferences window has been changed to
  "Library Location"
- Removed Update Version column

### Fixed

- Bug where bookmarks weren't being updated properly causing the app to crash.
- Bug where app would crash if NPS library folder was deleted after app started
  up and before a file was being downloaded
- Bug that was displaying the library location in Preferences with
  "/NPS Downloads" attached instead of the path to the library's parent folder.
  This was causing the NPS Downloads folder to be created inside the previous
  NPS Downloads folder.
- Bug where compat patches weren't being downloaded

## [1.3.6] - 2018-08-03

### Added

- On startup the app checks for the folder "NPS Downloads" at the given
  download location specified in Preferences. By default this folder is the
  Downloads folder. If "~/Downloads/NPS Downloads" does not exist it will be
  created.
- Better logging!
- Compat packs will be extracted in the proper order

### Changed

- The button to download the .pkg files is now multi-purpose. Checkboxes will
  determine which files specific to that game will be downloaded
  (base game, updates, compat packs)
- PSV Updates will now no longer be using the NPS TSV file, instead it will be
  looking up the latest "hybrid package" from Sony's servers and downloading
  that. If a hybrid package is not available the latest cumulative package will
  be used. Incremental updates will be handled on the Vita itself.

## 1.3.3 - 2018-07-28

### Fixed

- Compat packs are no longer fetched at the same time as tsv files.

## [1.3.2] - 2018-07-27

### Added

- Column for PSV Updates that shows the app version number
- Local .TSV files can now be used instead of using a URL
- Compat packs for Vita Updates
- Local entries.txt and patch_entries.txt can be used for compat packs instead
  of URL

### Changed

- Updated app icon (made by @Ann0ying)
- App now uses a custom .dmg file to give it a nice background and a convenient
  Applications folder to drop the application into

## [1.3.1] - 2018-07-27

### Added

- Compat Pack support!

### Changed

- Fixed bug where downloads that have been resumed will fail
- Bookmarks and Downloads lists now become hightlighted when selected

## [1.3.0] - 2018-07-01

### Added

- PS3 Game support!
- PS3 DLC support!
- PS3 Theme support!
- PS3 Avatar support!

### Changed

- New preferences window (again). The list of URLs is getting so long the
  window was getting way too tall, so I widened it.
- Fixed bug where completed downloads would show as "stopped" next time the app
  was loaded
- Now using UUID for each item rather than relying on SHA256 value since PS3 is
  missing SHA
- Window can now be made full-height of screen

## [1.2.7] - 2018-06-29

### Added

- PS Vita theme support added
- Ability to hide any items with missing download links

### Changed

- Fixed bug where the preferences window would crop if a long path was selected
  for the download location.
- Now using the forked pkg2zip by Luro02 to unpack PS Vita themes

## [1.2.6] - 2018-06-25

### Added

- A modal window now displays a progress bar showing the progress of fetching
  the data

### Changed

- Preferences UI has been tweaked
- Core Data storage has been improved

## [1.2.5] - 2018-06-22

### Changed

- Fixed items not being downloaded

## [1.2.4] - 2018-06-22

### Added

- The first row of the master view table is auto-selected

### Changed

- Fixed bug that would make the app crash on startup
- Fixed memory leaks
- Fixed bug where bookmark changes weren't being propagated properly

## [1.2.2] - 2018-06-16

### Added

- Notifications when download/extraction is completed.
- Completed downloads move to bottom of download list
- Button added to download list items to allow resuming a cancelled download.
- Arrow keys can now be used to navigate the data table in the master view
- Concurrent download amount can be changed in the preferences window.
- Bookmarks can now be saved with the star button in the details panel
- Download list will now be saved and restored upon application termination

### Changed

- Changed repository name to "NPS-Browser-macOS" to avoid confusion with
  original NPS Browser.
- Changed app name to "NPS Browser"
- Fixed a bug that would crash the app when trying to clear download list witih
  more than 1 item
- UI tweaks
- Application terminates when the red close button is pressed instead of just
  closing the window

## [1.1] - 2018-06-08

### Added

- This CHANGELOG file to document project changes.
- Added icons created by @Ann0ying
- Ability to sort data by column.
- Added a "Last Modified" column.
- "View file" icon in the downloads window now opens location in Finder.

### Changed

- Changed appicons to the new icons created by @Ann0ying
- Incorrect date formatter was being used in NPSBase, resulting in nil
  last_modification_date
- CoreDataIO wasn't storing PSP and PSX fetch data
- Removed personal info from comments

## [1.0] - 2018-06-04

### Added

- README containing usage and build instructions.

[2.0.0]: https://github.com/xsyetopz/NPS-Browser-macOS-next/releases/tag/v2.0.0
[1.4.6]: https://github.com/JK3Y/NPS-Browser-macOS/releases/tag/v1.4.6
[1.4.5]: https://github.com/JK3Y/NPS-Browser-macOS/releases/tag/v1.4.5
[1.4.4]: https://github.com/JK3Y/NPS-Browser-macOS/releases/tag/v1.4.4
[1.4.3]: https://github.com/JK3Y/NPS-Browser-macOS/releases/tag/v1.4.3
[1.4.2]: https://github.com/JK3Y/NPS-Browser-macOS/releases/tag/v1.4.2
[1.4.1]: https://github.com/JK3Y/NPS-Browser-macOS/releases/tag/v1.4.1
[1.4.0]: https://github.com/JK3Y/NPS-Browser-macOS/releases/tag/v1.4.0
[1.3.7]: https://github.com/JK3Y/NPS-Browser-macOS/releases/tag/v1.3.7
[1.3.6]: https://github.com/JK3Y/NPS-Browser-macOS/releases/tag/v1.3.6
[1.3.2]: https://github.com/JK3Y/NPS-Browser-macOS/releases/tag/v1.3.2
[1.3.1]: https://github.com/JK3Y/NPS-Browser-macOS/releases/tag/v1.3.1
[1.3.0]: https://github.com/JK3Y/NPS-Browser-macOS/releases/tag/v1.3.0
[1.2.7]: https://github.com/JK3Y/NPS-Browser-macOS/releases/tag/v1.2.7
[1.2.6]: https://github.com/JK3Y/NPS-Browser-macOS/releases/tag/v1.2.6
[1.2.5]: https://github.com/JK3Y/NPS-Browser-macOS/releases/tag/v1.2.5
[1.2.4]: https://github.com/JK3Y/NPS-Browser-macOS/releases/tag/v1.2.4
[1.2.2]: https://github.com/JK3Y/NPS-Browser-macOS/releases/tag/v1.2.2
[1.1]: https://github.com/JK3Y/NPS-Browser-macOS/releases/tag/v1.1
[1.0]: https://github.com/JK3Y/NPS-Browser-macOS/releases/tag/v1.0
