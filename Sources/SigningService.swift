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

    // MARK: - Logging

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

    // MARK: - Main Signing

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

        // MARK: Security Scope

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
            "원본 폴더 확인 완료",
            progress: 0.02,
            handler: progress
        )

        // MARK: Certificate Validation

        let profileData = try Data(contentsOf: profileURL)
        let credentialData = try Data(contentsOf: p12URL)

        log(
            "인증서 검증 중",
            progress: 0.03,
            handler: progress
        )

        let teamID = try RorkSigner.validatedTeamIdentifier(
            provisioningProfileData: profileData,
            credentialData: credentialData,
            password: password
        )

        log(
            "인증서 검증 완료 - Team ID: \(teamID)",
            progress: 0.05,
            handler: progress
        )

        // MARK: Workspace

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
        }

        // MARK: Source File Enumeration

        log(
            "원본 파일 목록 검색 중",
            progress: 0.06,
            handler: progress
        )

        guard let enumerator = fm.enumerator(
            at: sourceURL,
            includingPropertiesForKeys: [
                .isRegularFileKey
            ],
            options: []
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

        while let fileURL = enumerator.nextObject() as? URL {

            let values = try fileURL.resourceValues(
                forKeys: [.isRegularFileKey]
            )

            if values.isRegularFile == true {
                sourceFiles.append(fileURL)
            }
        }

        // 경로 순서를 고정하여 복사 순서 안정화
        sourceFiles.sort {
            relativePath(of: $0, under: sourceURL)
                < relativePath(of: $1, under: sourceURL)
        }

        let totalFiles = sourceFiles.count

        log(
            "검색 완료: \(totalFiles)개 파일",
            progress: 0.08,
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

        // MARK: Copy Source

        log(
            "원본 복사 시작",
            progress: 0.10,
            handler: progress
        )

        try fm.createDirectory(
            at: copiedSource,
            withIntermediateDirectories: true
        )

        for (index, fileURL) in sourceFiles.enumerated() {

            let relativeURL = relativePath(
                of: fileURL,
                under: sourceURL
            )

            let targetURL = copiedSource
                .appendingPathComponent(relativeURL)

            let ratioBefore =
                Double(index) / Double(totalFiles)

            let currentProgress =
                0.10 + ratioBefore * 0.20

            log(
                "복사 중: \(index + 1)/\(totalFiles) - \(relativeURL)",
                progress: currentProgress,
                handler: progress
            )

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

            let ratioAfter =
                Double(index + 1) / Double(totalFiles)

            log(
                "복사 완료: \(index + 1)/\(totalFiles) - \(relativeURL)",
                progress: 0.10 + ratioAfter * 0.20,
                handler: progress
            )
        }

        log(
            "원본 복사 완료: \(totalFiles)개 파일",
            progress: 0.30,
            handler: progress
        )

        // MARK: Find Frameworks

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

        // MARK: Duplicate Check

        let groupedFrameworks = Dictionary(
            grouping: frameworks,
            by: { $0.lastPathComponent }
        )

        let duplicateNames = groupedFrameworks.filter {
            $0.value.count > 1
        }

        for name in duplicateNames.keys.sorted() {

            log(
                "동일 이름 Framework 발견: \(name) - 처리 제외",
                progress: 0.35,
                handler: progress
            )
        }

        let validFrameworks = frameworks.filter {
            groupedFrameworks[$0.lastPathComponent]?.count == 1
        }

        result.failed +=
            frameworks.count - validFrameworks.count

        let totalFrameworks = validFrameworks.count

        // MARK: Framework Signing

        for (index, frameworkURL) in validFrameworks.enumerated() {

            let frameworkName =
                frameworkURL.lastPathComponent

            let baseProgress =
                0.36 +
                (
                    Double(index)
                    / Double(max(totalFrameworks, 1))
                ) * 0.60

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

                // MARK: Output Location

                let outputURL = destinationURL
                    .appendingPathComponent(
                        frameworkName,
                        isDirectory: true
                    )

                log(
                    "저장 대상: \(outputURL.lastPathComponent)",
                    progress: baseProgress + 0.20,
                    handler: progress
                )

                // MARK: Existing Framework Check

                if fm.fileExists(atPath: outputURL.path) {

                    log(
                        "기존 Framework 검사: \(frameworkName)",
                        progress: baseProgress + 0.25,
                        handler: progress
                    )

                    let existingHash = try directoryHash(
                        outputURL
                    )

                    let newHash = try directoryHash(
                        frameworkURL
                    )

                    // 동일한 결과라면 기존 파일 유지
                    if existingHash == newHash {

                        result.skipped += 1

                        log(
                            "동일 파일 확인 - 기존 파일 유지 및 스킵: \(frameworkName)",
                            progress: baseProgress + 0.30,
                            handler: progress
                        )

                        continue
                    }

                    // MARK: Backup Existing Framework

                    let backupURL = workspace
                        .appendingPathComponent(
                            "Backup-\(UUID().uuidString)",
                            isDirectory: true
                        )

                    log(
                        "기존 Framework 백업: \(frameworkName)",
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
                            "기존 Framework 교체 완료: \(frameworkName)",
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

                    // MARK: New Framework

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
                        "새 Framework 저장 완료: \(frameworkName)",
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
                        .appendingPathComponent(
                            frameworkName,
                            isDirectory: true
                        )

                    if !fm.fileExists(
                        atPath: failedURL.path
                    ) {

                        try? fm.copyItem(
                            at: frameworkURL,
                            to: failedURL
                        )
                    }

                    log(
                        "실패한 Framework 보존: \(frameworkName)",
                        progress: baseProgress + 0.35,
                        handler: progress
                    )
                }
            }
        }

        // MARK: Finish

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

    // MARK: - Relative Path

    private func relativePath(
        of url: URL,
        under root: URL
    ) -> String {

        let rootPath = root.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path

        guard filePath.hasPrefix(rootPath) else {
            return url.lastPathComponent
        }

        var relative = String(
            filePath.dropFirst(rootPath.count)
        )

        if relative.hasPrefix("/") {
            relative.removeFirst()
        }

        return relative
    }

    // MARK: - Find Frameworks

    private func findFrameworks(
        in directory: URL
    ) -> [URL] {

        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [
                .isDirectoryKey
            ],
            options: []
        ) else {
            return []
        }

        var frameworks: [URL] = []

        for case let url as URL in enumerator {

            if url.pathExtension.lowercased() == "framework" {

                frameworks.append(url)

                enumerator.skipDescendants()
            }
        }

        return frameworks.sorted {
            $0.path < $1.path
        }
    }

    // MARK: - Stable Directory Hash

    private func directoryHash(
        _ directory: URL
    ) throws -> String {

        let fm = FileManager.default

        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isDirectoryKey
            ],
            options: []
        ) else {

            throw NSError(
                domain: "NX2AppleSigner",
                code: 1008,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Framework 비교를 위한 파일 목록을 읽을 수 없습니다."
                ]
            )
        }

        var fileEntries: [(path: String, url: URL)] = []

        while let fileURL = enumerator.nextObject() as? URL {

            let values = try fileURL.resourceValues(
                forKeys: [
                    .isRegularFileKey,
                    .isDirectoryKey
                ]
            )

            // 서명 폴더는 비교 대상에서 제외
            if fileURL.lastPathComponent == "_CodeSignature" {

                enumerator.skipDescendants()
                continue
            }

            guard values.isRegularFile == true else {
                continue
            }

            let relative = relativePath(
                of: fileURL,
                under: directory
            )

            fileEntries.append(
                (
                    path: relative,
                    url: fileURL
                )
            )
        }

        // 파일 열거 순서가 달라도 동일한 결과가 나오도록 정렬
        fileEntries.sort {
            $0.path < $1.path
        }

        var hasher = SHA256()

        for entry in fileEntries {

            let pathData = Data(
                entry.path.utf8
            )

            let fileData = try Data(
                contentsOf: entry.url,
                options: [.mappedIfSafe]
            )

            // 경로와 데이터 경계 구분
            var pathLength = UInt64(pathData.count).bigEndian
            var dataLength = UInt64(fileData.count).bigEndian

            withUnsafeBytes(of: &pathLength) {
                hasher.update(data: Data($0))
            }

            hasher.update(data: pathData)

            withUnsafeBytes(of: &dataLength) {
                hasher.update(data: Data($0))
            }

            hasher.update(data: fileData)
        }

        let digest = hasher.finalize()

        return digest.map {
            String(format: "%02x", $0)
        }.joined()
    }
}
