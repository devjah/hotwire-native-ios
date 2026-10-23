import Foundation

extension HTTPCookieStorage {
    /// Makes the cookies sent to `url` match `cookies`, removing any that are no longer present.
    ///
    /// The cookies are set first, which overwrites each stored cookie that is still
    /// present in place; only the ones `cookies` no longer has are deleted after that.
    /// URLSession reads this storage from its own threads, and a native request that
    /// read it between deleting a cookie and setting it again would go out without
    /// the session cookie.
    func replaceCookies(for url: URL, with cookies: [HTTPCookie]) {
        setCookies(cookies, for: url, mainDocumentURL: url)

        let current = Set(cookies.map(StoredCookieIdentity.init))
        self.cookies(for: url)?
            .filter { !current.contains(StoredCookieIdentity($0)) }
            .forEach(deleteCookie)
    }
}

/// What cookie storage tells cookies apart by: setting a cookie replaces the stored
/// one with the same name, domain and path.
private struct StoredCookieIdentity: Hashable {
    let name: String
    let domain: String
    let path: String

    init(_ cookie: HTTPCookie) {
        name = cookie.name
        domain = cookie.domain
        path = cookie.path
    }
}
