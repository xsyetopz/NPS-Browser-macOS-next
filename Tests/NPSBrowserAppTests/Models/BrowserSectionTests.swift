import NPSBrowserAppResources
import Testing
@testable import NPSBrowserApp

@Test(.sourceEnglish)
func newCatalogueSourceAndNavigationTitlesAreLocalized() {
  #expect(AppResources.localized("section.psm") != "section.psm")
  #expect(AppResources.localized("source.psmGames") != "source.psmGames")
  #expect(AppResources.localized("source.pspDLCs") != "source.pspDLCs")
  #expect(BrowserSection.allCases.contains(.psm))
}
