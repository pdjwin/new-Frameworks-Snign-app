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

    private func log(
        _ message: String,
        progress: Double,
        handler: ProgressHandler
    ) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"

        let time = formatter.string(from: Date())

        handler(
            "[\(time)] \(message)",
            min(max(progress, 0), 1)
        )
    }

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

        let fm = FileManager.default

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

        log(
            "작업 준비 중",
            progress: 0.01,
            handler: progress
        )

        guard fm.fileExists(atPath: sourceURL.path) else {
            throw NSError(
                domain: "NX2AppleSigner",
                code: 1002,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "원본 폴더를 찾을 수 없습니다."
                ]
            )
        }

        guard fm.fileExists(atPath: destinationURL.path) else {
            throw NSError(
                domain: "NX2AppleSigner",
                code: 1003,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "저장 폴더를 찾을 수 없습니다."
                ]
            )
        }

        log(
            "원본 폴더 확인 완료: \(sourceURL.lastPathComponent)",
            progress: 0.02,
            handler: progress
        )

        let profileData = try Data(contentsOf: profileURL)
        let credentialData = try Data(contentsOf: p12URL)

        log(
            "인증서 검증 중",
            progress: 0.03,
            handler: progress
        )

        _ = try RorkSigner.validatedTeamIdentifier(
            provisioningProfileData: profileData,
            credentialData: credentialData,
            password: password
        )

        log(
            "인증서 검증 완료",
            progress: 0.05,
            handler: progress
        )

        let documents = fm.urls(
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

        try fm.createDirectory(
            at: workspace,
            withIntermediateDirectories: true
        )

        defer {

            try? fm.removeItem(at: workspace)

            log(
                "임시 작업 폴더 정리 완료",
                progress: 1.0,
                handler: progress
            )
        }

        // MARK: - 원본 파일 목록 확인

        log(
            "원본 파일 목록 검색 중",
            progress: 0.06,
            handler: progress
        )

        guard let enumerator = fm.enumerator(
            at: sourceURL,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isDirectoryKey,
                .fileSizeKey
            ],
            options: [
                .skipsHiddenFiles
            ]
        ) else {
            throw NSError(
                domain: "NX2AppleSigner",
                code: 1004,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "원본 폴더를 읽을 수 없습니다."
                ]
            )
        }

        var sourceFiles: [URL] = []
        var totalBytes: Int64 = 0

        while let fileURL = enumerator.nextObject() as? URL {

            let values = try fileURL.resourceValues(
                forKeys: [
                    .isRegularFileKey,
                    .fileSizeKey
                ]
            )

            if values.isRegularFile == true {

                sourceFiles.append(fileURL)

                totalBytes += Int64(
                    values.fileSize ?? 0
                )
            }
        }

        let totalFiles = sourceFiles.count

        let totalGB = Double(totalBytes) / 1_073_741_824

        log(
            "검색 완료: \(totalFiles)개 파일",
            progress: 0.08,
            handler: progress
        )

        log(
            String(
                format: "전체 용량: %.2f GB",
                totalGB
            ),
            progress: 0.09,
            handler: progress
        )

        guard totalFiles > 0 else {
            throw NSError(
                domain: "NX2AppleSigner",
                code: 1005,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "원본 폴더에 파일이 없습니다."
                ]
            )
        }

        // MARK: - 원본 복사

        log(
            "원본 복사 시작",
            progress: 0.10,
            handler: progress
        )

        try fm.createDirectory(
            at: copiedSource,
            withIntermediateDirectories: true
        )

        var copiedBytes: Int64 = 0

        for (index, fileURL) in sourceFiles.enumerated() {

            let relativePath = String(
                fileURL.path.dropFirst(
                    sourceURL.path.count
                )
            )

            let relativeURL = relativePath.hasPrefix("/")
                ? String(relativePath.dropFirst())
                : relativePath

            let targetURL = copiedSource
                .appendingPathComponent(relativeURL)

            try fm.createDirectory(
                at: targetURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            do {

                try fm.copyItem(
                    at: fileURL,
                    to: targetURL
                )

            } catch {

                throw NSError(
                    domain: "NX2AppleSigner",
                    code: 1006,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "파일 복사 실패: \(relativeURL) - \(error.localizedDescription)"
                    ]
                )
            }

            let values = try fileURL.resourceValues(
                forKeys: [.fileSizeKey]
            )

            copiedBytes += Int64(
                values.fileSize ?? 0
            )

            let ratio = Double(index + 1) / Double(totalFiles)

            let currentProgress = 0.10 + ratio * 0.20

            log(
                "복사 중: \(index + 1)/\(totalFiles) - \(relativeURL)",
                progress: currentProgress,
                handler: progress
            )
        }

        log(
            "원본 복사 완료: \(totalFiles)개 파일",
            progress: 0.30,
            handler: progress
        )

        // MARK: - Framework 검색

        log(
            "Framework 검색 중",
            progress: 0.32,
            handler: progress
        )

        let frameworks = findFrameworks(
            in: copiedSource
        )

        guard !frameworks.isEmpty else {
            throw NSError(
                domain: "NX2AppleSigner",
                code: 1007,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Framework를 찾을 수 없습니다."
                ]
            )
        }

        log(
            "Framework 검색 완료: \(frameworks.count)개",
            progress: 0.35,
            handler: progress
        )

        // MARK: - 동일 이름 충돌 검사

        let groupedFrameworks = Dictionary(
            grouping: frameworks,
            by: { $0.lastPathComponent }
        )

        let duplicateNames = groupedFrameworks.filter {
            $0.value.count > 1
        }

        if !duplicateNames.isEmpty {

            for name in duplicateNames.keys {

                log(
                    "동일 이름 Framework 발견: \(name) - 경로 충돌로 처리하지 않음",
                    progress: 0.35,
                    handler: progress
                )
            }
        }

        let validFrameworks = frameworks.filter {
            groupedFrameworks[$0.lastPathComponent]?.count == 1
        }

        result.failed += frameworks.count - validFrameworks.count

        // MARK: - Framework 서명

        let totalFrameworks = validFrameworks.count

        for (index, frameworkURL) in validFrameworks.enumerated() {

            let frameworkName = frameworkURL.lastPathComponent

            let baseProgress = 0.36 +
                (Double(index) / Double(max(totalFrameworks, 1))) * 0.60

            log(
                "서명 시작: \(frameworkName)",
                progress: baseProgress,
                handler: progress
            )

            do {

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

                log(
                    "서명 완료: \(frameworkName)",
                    progress: baseProgress + 0.15,
                    handler: progress
                )

                // 저장 위치에 Framework 이름만 사용
                // 원본 상위 폴더 경로는 포함하지 않음

                let outputURL = destinationURL
                    .appendingPathComponent(frameworkName)

                log(
                    "저장 대상: \(outputURL.lastPathComponent)",
                    progress: baseProgress + 0.20,
                    handler: progress
                )

                if fm.fileExists(
                    atPath: outputURL.path
                ) {

                    log(
                        "기존 파일 검사: \(frameworkName)",
                        progress: baseProgress + 0.25,
                        handler: progress
                    )

                    let existingHash = try directoryHash(
                        outputURL
                    )

                    let newHash = try directoryHash(
                        frameworkURL
                    )

                    if existingHash == newHash {

                        result.skipped += 1

                        log(
                            "동일 파일 확인 - 저장 건너뜀: \(frameworkName)",
                            progress: baseProgress + 0.30,
                            handler: progress
                        )

                        continue
                    }

                    let backupURL = workspace
                        .appendingPathComponent(
                            "Backup-\(UUID().uuidString)"
                        )

                    log(
                        "기존 파일 백업: \(frameworkName)",
                        progress: baseProgress + 0.30,
                        handler: progress
                    )

                    try fm.moveItem(
                        at: outputURL,
                        to: backupURL
                    )

                    do {

                        try fm.copyItem(
                            at: frameworkURL,
                            to: outputURL
                        )

                        try fm.removeItem(
                            at: backupURL
                        )

                        result.replaced += 1

                        log(
                            "기존 파일 교체 완료: \(frameworkName)",
                            progress: baseProgress + 0.35,
                            handler: progress
                        )

                    } catch {

                        try? fm.removeItem(
                            at: outputURL
                        )

                        try fm.moveItem(
                            at: backupURL,
                            to: outputURL
                        )

                        throw error
                    }

                } else {

                    log(
                        "새 Framework 저장 중: \(frameworkName)",
                        progress: baseProgress + 0.30,
                        handler: progress
                    )

                    try fm.copyItem(
                        at: frameworkURL,
                        to: outputURL
                    )

                    result.success += 1

                    log(
                        "저장 완료: \(frameworkName)",
                        progress: baseProgress + 0.35,
                        handler: progress
                    )
                }

            } catch {

                result.failed += 1

                log(
                    "Framework 실패: \(frameworkName) - \(error.localizedDescription)",
                    progress: baseProgress + 0.35,
                    handler: progress
                )

                if !deleteFailedCopies {

                    try? fm.createDirectory(
                        at: failedFolder,
                        withIntermediateDirectories: true
                    )

                    let failedURL = failedFolder
                        .appendingPathComponent(frameworkName)

                    try? fm.copyItem(
                        at: frameworkURL,
                        to: failedURL
                    )

                    log(
                        "실패한 Framework 보존: \(frameworkName)",
                        progress: baseProgress + 0.35,
                        handler: progress
                    )
                }
            }
        }

        log(
            "전체 작업 완료",
            progress: 1.0,
            handler: progress
        )

        result.messages.append(
            "성공: \(result.success)"
        )

        result.messages.append(
            "교체: \(result.replaced)"
        )

        result.messages.append(
            "건너뜀: \(result.skipped)"
        )

        result.messages.append(
            "실패: \(result.failed)"
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
