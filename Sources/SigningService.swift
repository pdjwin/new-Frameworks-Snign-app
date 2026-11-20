import Foundation
import RorkSign
import CryptoKit

struct SigningResult {

    var success = 0
    var failed = 0
    var skipped = 0
    var replaced = 0

    var messages: [String] = []
}

final class SigningService {

    static let shared = SigningService()

    private init() {}

    typealias ProgressHandler = (String, Double) -> Void

    func signFolder(
        sourceURL: URL,
        destinationURL: URL,
        p12URL: URL,
        profileURL: URL,
        password: String,
        bundleIdentifier: String,
        deleteFailedCopies: Bool,
        progress: @escaping ProgressHandler
    ) throws -> SigningResult {

        var result = SigningResult()

        guard !bundleIdentifier.isEmpty else {
            throw NSError(
                domain: "NX2AppleSigner",
                code: 1001,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Bundle ID를 입력해주세요."
                ]
            )
        }

        let sourceAccess =
            sourceURL.startAccessingSecurityScopedResource()

        let destinationAccess =
            destinationURL.startAccessingSecurityScopedResource()

        let p12Access =
            p12URL.startAccessingSecurityScopedResource()

        let profileAccess =
            profileURL.startAccessingSecurityScopedResource()

        defer {
            if sourceAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }

            if destinationAccess {
                destinationURL.stopAccessingSecurityScopedResource()
            }

            if p12Access {
                p12URL.stopAccessingSecurityScopedResource()
            }

            if profileAccess {
                profileURL.stopAccessingSecurityScopedResource()
            }
        }

        let profileData = try Data(contentsOf: profileURL)
        let credentialData = try Data(contentsOf: p12URL)

        progress("인증서 검증 중", 0.02)

        _ = try RorkSigner.validatedTeamIdentifier(
            provisioningProfileData: profileData,
            credentialData: credentialData,
            password: password
        )

        let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]

        let workspace = documents
            .appendingPathComponent("Workspace")
            .appendingPathComponent(UUID().uuidString)

        let copiedSource = workspace
            .appendingPathComponent("Source")

        let failedFolder = documents
            .appendingPathComponent("FailedCopies")

        try FileManager.default.createDirectory(
            at: workspace,
            withIntermediateDirectories: true
        )

        defer {

            try? FileManager.default.removeItem(
                at: workspace
            )
        }

        progress("원본 폴더 복사 중", 0.05)

        try FileManager.default.copyItem(
            at: sourceURL,
            to: copiedSource
        )

        let frameworks = findFrameworks(
            in: copiedSource
        )

        guard !frameworks.isEmpty else {
            throw NSError(
                domain: "NX2AppleSigner",
                code: 1002,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "선택한 폴더에서 Framework를 찾지 못했습니다."
                ]
            )
        }

        let total = frameworks.count

        for (index, frameworkURL) in frameworks.enumerated() {

            let currentProgress =
                0.10 + (Double(index) / Double(total)) * 0.80

            progress(
                "서명 중: \(frameworkURL.lastPathComponent)",
                currentProgress
            )

            let relativePath = String(
                frameworkURL.path.dropFirst(
                    copiedSource.path.count
                )
            )

            let outputURL = destinationURL
                .appendingPathComponent(relativePath)

            let outputParent = outputURL.deletingLastPathComponent()

            do {

                try FileManager.default.createDirectory(
                    at: outputParent,
                    withIntermediateDirectories: true
                )

                var options = FrameworkSigningOptions()

                options.codeDirectoryIdentifier =
                    bundleIdentifier

                try RorkSigner.signFrameworkWithCredential(
                    at: frameworkURL,
                    provisioningProfileData: profileData,
                    credentialData: credentialData,
                    password: password,
                    options: options
                )

                if FileManager.default.fileExists(
                    atPath: outputURL.path
                ) {

                    let existingHash = try directoryHash(
                        outputURL
                    )

                    let newHash = try directoryHash(
                        frameworkURL
                    )

                    if existingHash == newHash {

                        result.skipped += 1

                        result.messages.append(
                            "건너뜀: \(outputURL.lastPathComponent)"
                        )

                        continue
                    }

                    let backupURL = workspace
                        .appendingPathComponent(
                            "Backup-\(UUID().uuidString)"
                        )

                    try FileManager.default.moveItem(
                        at: outputURL,
                        to: backupURL
                    )

                    do {

                        try FileManager.default.copyItem(
                            at: frameworkURL,
                            to: outputURL
                        )

                        try FileManager.default.removeItem(
                            at: backupURL
                        )

                        result.replaced += 1

                        result.messages.append(
                            "교체 완료: \(outputURL.lastPathComponent)"
                        )

                    } catch {

                        try? FileManager.default.removeItem(
                            at: outputURL
                        )

                        try FileManager.default.moveItem(
                            at: backupURL,
                            to: outputURL
                        )

                        throw error
                    }

                } else {

                    try FileManager.default.copyItem(
                        at: frameworkURL,
                        to: outputURL
                    )

                    result.success += 1

                    result.messages.append(
                        "저장 완료: \(outputURL.lastPathComponent)"
                    )
                }

            } catch {

                result.failed += 1

                result.messages.append(
                    "실패: \(frameworkURL.lastPathComponent) - \(error.localizedDescription)"
                )

                if !deleteFailedCopies {

                    try? FileManager.default.createDirectory(
                        at: failedFolder,
                        withIntermediateDirectories: true
                    )

                    let failedURL = failedFolder
                        .appendingPathComponent(
                            frameworkURL.lastPathComponent
                        )

                    try? FileManager.default.copyItem(
                        at: frameworkURL,
                        to: failedURL
                    )
                }
            }
        }

        progress("작업 완료", 1.0)

        result.messages.append(
            "전체 결과: 성공 \(result.success), 교체 \(result.replaced), 건너뜀 \(result.skipped), 실패 \(result.failed)"
        )

        return result
    }

    private func findFrameworks(
        in directory: URL
    ) -> [URL] {

        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [
                .isDirectoryKey
            ],
            options: [
                .skipsHiddenFiles
            ]
        ) else {
            return []
        }

        var frameworks: [URL] = []

        for case let url as URL in enumerator {

            if url.pathExtension == "framework" {

                frameworks.append(url)

                enumerator.skipDescendants()
            }
        }

        return frameworks
    }

    private func directoryHash(
        _ directory: URL
    ) throws -> String {

        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [
                .isRegularFileKey
            ],
            options: [
                .skipsHiddenFiles
            ]
        )

        var combinedData = Data()

        while let fileURL = enumerator?.nextObject() as? URL {

            let values = try fileURL.resourceValues(
                forKeys: [.isRegularFileKey]
            )

            guard values.isRegularFile == true else {
                continue
            }

            let relativePath = String(
                fileURL.path.dropFirst(
                    directory.path.count
                )
            )

            combinedData.append(
                Data(relativePath.utf8)
            )

            combinedData.append(
                try Data(contentsOf: fileURL)
            )
        }

        let digest = SHA256.hash(
            data: combinedData
        )

        return digest.map {
            String(format: "%02x", $0)
        }.joined()
    }
}
