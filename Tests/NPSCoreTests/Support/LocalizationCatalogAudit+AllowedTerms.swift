extension LocalizationCatalogAudit {
  /// Keys whose correct translation is spelled like the English source in that
  /// language (loanwords and terms macOS itself uses, such as "Status" or the
  /// Italian "File" menu). Each entry was reviewed; add new ones only after
  /// confirming the word is the standard term, not an untranslated leftover.
  static let sourceIdenticalTermsByLocale: [String: Set<String>] = [
    "da-DK": ["downloads.column.status", "error.download.byteCount", "inspector.type"],
    "de-DE": [
      "downloads.column.download", "downloads.column.status", "inspector.region",
      "section.downloads", "section.updates", "table.region",
    ], "es-ES": ["toolbar.inspector"],
    "fr-FR": [
      "downloads.column.actions", "inspector.console", "inspector.type", "section.avatars",
      "table.console",
    ],
    "it-IT": [
      "downloads.column.download", "inspector.console", "menu.file", "table.console",
      "toolbar.inspector",
    ],
    "nb-NO": [
      "downloads.column.status", "error.download.byteCount", "inspector.region", "inspector.type",
      "table.region",
    ],
    "nl-NL": [
      "action.download", "action.downloadRAP", "downloads.column.download",
      "downloads.column.status", "downloads.count", "error.download.byteCount", "inspector.console",
      "inspector.type", "menu.help", "section.avatars", "section.downloads", "section.games",
      "section.updates", "table.console",
    ], "pl-PL": ["inspector.region", "table.region"],
    "pt-BR": [
      "downloads.column.download", "downloads.column.status", "inspector.console",
      "section.downloads", "table.console",
    ],
    "sv-SE": [
      "downloads.column.status", "error.download.byteCount", "inspector.region", "table.region",
    ],
  ]

  static func allowedSourceIdenticalKeys(for localization: String) -> Set<String> {
    sourceIdenticalTermsByLocale.first {
      $0.key.caseInsensitiveCompare(localization) == .orderedSame
    }?.value ?? []
  }
}
