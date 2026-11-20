import Foundation

final class SettingsStore: ObservableObject {

    static let shared = SettingsStore()

    @Published var bundleIdentifier: String {
        didSet {
            UserDefaults.standard.set(
                bundleIdentifier,
                forKey: "bundleIdentifier"
            )
        }
    }

    @Published var deleteFailedCopies: Bool {
        didSet {
            UserDefaults.standard.set(
                deleteFailedCopies,
                forKey: "deleteFailedCopies"
            )
        }
    }

    @Published var password: String {
        didSet {
            KeychainStore.shared.save(
                key: "p12Password",
                value: password
            )
        }
    }

    @Published var sourceBookmark: Data?
    @Published var destinationBookmark: Data?
    @Published var p12Bookmark: Data?
    @Published var profileBookmark: Data?

    private init() {

        bundleIdentifier =
            UserDefaults.standard.string(
                forKey: "bundleIdentifier"
            ) ?? ""

        deleteFailedCopies =
            UserDefaults.standard.bool(
                forKey: "deleteFailedCopies"
            )

        password =
            KeychainStore.shared.load(
                key: "p12Password"
            ) ?? ""

        sourceBookmark =
            UserDefaults.standard.data(
                forKey: "sourceBookmark"
            )

        destinationBookmark =
            UserDefaults.standard.data(
                forKey: "destinationBookmark"
            )

        p12Bookmark =
            UserDefaults.standard.data(
                forKey: "p12Bookmark"
            )

        profileBookmark =
            UserDefaults.standard.data(
                forKey: "profileBookmark"
            )
    }

    func saveBookmark(
        url: URL,
        key: String
    ) {

        do {

            let data = try url.bookmarkData()

            UserDefaults.standard.set(
                data,
                forKey: key
            )

        } catch {

            print("Bookmark 저장 실패: \(error)")
        }
    }

    func restoreBookmark(
        key: String
    ) -> URL? {

        guard let data = UserDefaults.standard.data(
            forKey: key
        ) else {
            return nil
        }

        do {

            var isStale = false

            let url = try URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                saveBookmark(
                    url: url,
                    key: key
                )
            }

            return url

        } catch {

            print("Bookmark 복원 실패: \(error)")

            return nil
        }
    }
}
