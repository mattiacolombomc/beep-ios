import Foundation

/// Which version of an identity provider's page the login asks for on iPhone and iPad.
///
/// CIE and the SPID providers show a QR code only to a browser that says it is a computer
/// and whose page is wide; a phone gets an "open the app" button instead. The Politecnico
/// cannot complete a CIE login started from the CieID app, so CIE defaults to the QR code,
/// while SPID keeps the phone version, whose app shortcut works. The Mac is always a computer.
nonisolated enum LoginSite {
    static let cieDesktopKey = "settings.login.cieDesktop"
    static let spidDesktopKey = "settings.login.spidDesktop"
    static let cieDesktopDefault = true
    static let spidDesktopDefault = false

    /// Page width, in CSS points, at which CieID and PosteID both show their QR code
    /// (measured: CieID from 800, PosteID not at 834 on iPad and yes at 1024).
    static let desktopWidth = 1024

    /// Page width of the phone version on a screen wider than a phone (iPad, an open iPhone Duo).
    /// PosteID shows its "open the app" link only below 768 points.
    static let phoneWidth = 540

    /// What an iPhone's web view says it is. On iPad the phone version is asked with this, because
    /// some providers (CieID) offer their app only to a browser that says it is an iPhone.
    static let phoneUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"

    private static let polimiDomain = "polimi.it"
    private static let cieDomain = "servizicie.interno.gov.it"

    enum Provider: Equatable {
        case polimi, cie, other
    }

    static func provider(for url: URL) -> Provider {
        guard let host = url.host()?.lowercased() else { return .other }
        if belongs(host, to: polimiDomain) { return .polimi }
        if belongs(host, to: cieDomain) { return .cie }
        return .other
    }

    /// `nil` leaves the choice to the system: the Politecnico's own pages are not touched.
    static func wantsDesktop(_ url: URL, cie: Bool, spid: Bool) -> Bool? {
        switch provider(for: url) {
        case .polimi: nil
        case .cie: cie
        case .other: spid
        }
    }

    static func cieDesktop(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: cieDesktopKey) as? Bool ?? cieDesktopDefault
    }

    static func spidDesktop(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: spidDesktopKey) as? Bool ?? spidDesktopDefault
    }

    /// Runs on every page of the login. Asking for the desktop or the phone site changes what the
    /// browser says it is, not how wide the page is laid out, and the providers look at both:
    /// a page served as desktop is widened here, a page served as phone on a wide screen is narrowed.
    static let viewportScript = """
    (function () {
      var host = location.hostname;
      if (host === '\(polimiDomain)' || host.endsWith('.\(polimiDomain)')) return;
      var desktop = /Macintosh/.test(navigator.userAgent);
      var width = desktop ? \(desktopWidth) : \(phoneWidth);
      if (desktop ? window.innerWidth >= width : window.innerWidth <= width) return;
      var meta = document.querySelector('meta[name="viewport"]');
      if (!meta) {
        meta = document.createElement('meta');
        meta.name = 'viewport';
        document.head.appendChild(meta);
      }
      meta.content = 'width=' + width;
    })();
    """

    private static func belongs(_ host: String, to domain: String) -> Bool {
        host == domain || host.hasSuffix("." + domain)
    }
}
