import SwiftUI
import UniformTypeIdentifiers

enum SignerPage: String, CaseIterable, Identifiable {

    case framework = "Framework"
    case destination = "저장 위치"
    case certificate = "인증서"
    case signing = "서명 실행"
    case logs = "작업 로그"

    var id: String {
        rawValue
    }

    var icon: String {

        switch self {

        case .framework:
            return "shippingbox"

        case .destination:
            return "folder.badge.checkmark"

        case .certificate:
            return "key.horizontal"

        case .signing:
            return "signature"

        case .logs:
            return "terminal"
        }
    }
}

struct ContentView: View {

    @StateObject private var settings =
        SettingsStore.shared

    @State private var selectedPage: SignerPage = .framework

    @State private var sourceURL: URL?
    @State private var destinationURL: URL?
    @State private var p12URL: URL?
    @State private var profileURL: URL?

    @State private var showSourcePicker = false
    @State private var showDestinationPicker = false
    @State private var showP12Picker = false
    @State private var showProfilePicker = false

    @State private var isSigning = false

    @State private var progressValue = 0.0
    @State private var progressText = "대기 중"

    @State private var logs: [String] = []

    @State private var successCount = 0
    @State private var failedCount = 0
    @State private var skippedCount = 0
    @State private var replacedCount = 0

    var body: some View {

        GeometryReader { geometry in

            let sidebarWidth = min(
                max(geometry.size.width * 0.25, 180),
                250
            )

            ZStack {

                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                HStack(spacing: 0) {

                    sidebar
                        .frame(width: sidebarWidth)

                    Divider()

                    detail
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height
            )
        }
        .fileImporter(
            isPresented: $showSourcePicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in

            handlePicker(
                result,
                key: "sourceBookmark"
            ) { sourceURL = $0 }
        }
        .fileImporter(
            isPresented: $showDestinationPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in

            handlePicker(
                result,
                key: "destinationBookmark"
            ) { destinationURL = $0 }
        }
        .fileImporter(
            isPresented: $showP12Picker,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in

            handlePicker(
                result,
                key: "p12Bookmark"
            ) { p12URL = $0 }
        }
        .fileImporter(
            isPresented: $showProfilePicker,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in

            handlePicker(
                result,
                key: "profileBookmark"
            ) { profileURL = $0 }
        }
        .onAppear {

            restoreSavedPaths()
        }
    }

    private var sidebar: some View {

        VStack(alignment: .leading, spacing: 8) {

            HStack(spacing: 10) {

                Image(systemName: "signature")
                    .font(.system(size: 24, weight: .semibold))

                VStack(alignment: .leading, spacing: 2) {

                    Text("NX2Apple")
                        .font(.headline)

                    Text("Framework Signer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 24)

            ForEach(SignerPage.allCases) { page in

                Button {

                    selectedPage = page

                } label: {

                    HStack(spacing: 12) {

                        Image(systemName: page.icon)
                            .frame(width: 24)

                        Text(page.rawValue)
                            .lineLimit(1)

                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 15, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .foregroundStyle(
                        selectedPage == page
                        ? Color.accentColor
                        : Color.primary
                    )
                    .background {

                        if selectedPage == page {

                            RoundedRectangle(
                                cornerRadius: 10
                            )
                            .fill(
                                Color.accentColor.opacity(0.12)
                            )
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 4) {

                Text("NX2Apple Signer")
                    .font(.caption)
                    .fontWeight(.semibold)

                Text("Version 1.0")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .background(
            Color(uiColor: .secondarySystemGroupedBackground)
        )
    }

    private var detail: some View {

        VStack(spacing: 0) {

            HStack {

                Text(selectedPage.rawValue)
                    .font(.system(size: 23, weight: .bold))

                Spacer()

                if isSigning {

                    ProgressView()
                        .scaleEffect(0.9)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            Divider()

            ScrollView {

                VStack(alignment: .leading, spacing: 20) {

                    switch selectedPage {

                    case .framework:
                        frameworkPage

                    case .destination:
                        destinationPage

                    case .certificate:
                        certificatePage

                    case .signing:
                        signingPage

                    case .logs:
                        logsPage
                    }
                }
                .frame(maxWidth: 850)
                .frame(maxWidth: .infinity)
                .padding(24)
            }
        }
    }

    private var frameworkPage: some View {

        VStack(alignment: .leading, spacing: 18) {

            sectionTitle(
                "원본 Framework",
                subtitle: "서명할 Framework가 포함된 원본 폴더를 선택합니다."
            )

            selectionCard(
                title: "원본 폴더",
                value: sourceURL?.lastPathComponent ?? "선택되지 않음",
                icon: "folder",
                buttonTitle: "폴더 선택"
            ) {
                showSourcePicker = true
            }

            infoBox(
                "원본 폴더는 수정하지 않습니다. 서명 작업은 별도의 작업용 복사본에서 진행됩니다."
            )
        }
    }

    private var destinationPage: some View {

        VStack(alignment: .leading, spacing: 18) {

            sectionTitle(
                "저장 위치",
                subtitle: "서명이 완료된 Framework를 저장할 위치입니다."
            )

            selectionCard(
                title: "저장 폴더",
                value: destinationURL?.lastPathComponent ?? "선택되지 않음",
                icon: "folder.badge.checkmark",
                buttonTitle: "폴더 선택"
            ) {
                showDestinationPicker = true
            }

            infoBox(
                "기존 파일과 내용이 다르면 기존 파일을 백업한 다음 교체합니다. 교체에 실패하면 기존 파일을 복원합니다."
            )
        }
    }

    private var certificatePage: some View {

        VStack(alignment: .leading, spacing: 18) {

            sectionTitle(
                "인증서 설정",
                subtitle: "Framework 서명에 필요한 인증서와 프로파일을 선택합니다."
            )

            selectionCard(
                title: "P12 인증서",
                value: p12URL?.lastPathComponent ?? "선택되지 않음",
                icon: "key",
                buttonTitle: "P12 선택"
            ) {
                showP12Picker = true
            }

            selectionCard(
                title: "MobileProvision",
                value: profileURL?.lastPathComponent ?? "선택되지 않음",
                icon: "doc.badge.gearshape",
                buttonTitle: "프로파일 선택"
            ) {
                showProfilePicker = true
            }

            VStack(alignment: .leading, spacing: 8) {

                Text("P12 비밀번호")
                    .font(.headline)

                SecureField(
                    "비밀번호 입력",
                    text: $settings.password
                )
                .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {

                Text("Bundle Identifier")
                    .font(.headline)

                TextField(
                    "com.example.application",
                    text: $settings.bundleIdentifier
                )
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            }

            infoBox(
                "비밀번호는 iOS Keychain에 저장됩니다."
            )
        }
    }

    private var signingPage: some View {

        VStack(alignment: .leading, spacing: 18) {

            sectionTitle(
                "서명 실행",
                subtitle: "설정한 경로와 인증서로 Framework 서명을 진행합니다."
            )

            VStack(alignment: .leading, spacing: 12) {

                summaryRow(
                    "원본",
                    sourceURL?.lastPathComponent
                )

                summaryRow(
                    "저장 위치",
                    destinationURL?.lastPathComponent
                )

                summaryRow(
                    "P12",
                    p12URL?.lastPathComponent
                )

                summaryRow(
                    "프로파일",
                    profileURL?.lastPathComponent
                )

                summaryRow(
                    "Bundle ID",
                    settings.bundleIdentifier
                )
            }
            .padding(16)
            .background(cardBackground)

            Toggle(
                "실패한 Framework 복사본 삭제",
                isOn: $settings.deleteFailedCopies
            )

            VStack(alignment: .leading, spacing: 8) {

                HStack {

                    Text(progressText)
                        .font(.subheadline)

                    Spacer()

                    Text(
                        "\(Int(progressValue * 100))%"
                    )
                    .font(.subheadline.monospacedDigit())
                }

                ProgressView(value: progressValue)
            }
            .padding(16)
            .background(cardBackground)

            Button {

                startSigning()

            } label: {

                HStack {

                    Spacer()

                    Image(systemName: "signature")

                    Text(
                        isSigning
                        ? "서명 진행 중"
                        : "서명 시작"
                    )
                    .fontWeight(.semibold)

                    Spacer()
                }
                .padding(16)
                .foregroundStyle(.white)
                .background(
                    isSigning
                    ? Color.gray
                    : Color.accentColor
                )
                .clipShape(
                    RoundedRectangle(cornerRadius: 12)
                )
            }
            .disabled(isSigning)
        }
    }

    private var logsPage: some View {

        VStack(alignment: .leading, spacing: 14) {

            sectionTitle(
                "작업 로그",
                subtitle: "서명 과정에서 발생한 작업 결과를 확인합니다."
            )

            HStack(spacing: 10) {

                countCard(
                    "성공",
                    value: successCount,
                    color: .green
                )

                countCard(
                    "교체",
                    value: replacedCount,
                    color: .blue
                )

                countCard(
                    "건너뜀",
                    value: skippedCount,
                    color: .orange
                )

                countCard(
                    "실패",
                    value: failedCount,
                    color: .red
                )
            }

            VStack(alignment: .leading, spacing: 8) {

                ForEach(
                    Array(logs.enumerated()),
                    id: \.offset
                ) { _, message in

                    Text(message)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                        .padding(8)
                        .background(
                            Color(uiColor: .tertiarySystemGroupedBackground)
                        )
                        .clipShape(
                            RoundedRectangle(cornerRadius: 6)
                        )
                }
            }
        }
    }

    private var cardBackground: some View {

        RoundedRectangle(cornerRadius: 12)
            .fill(
                Color(uiColor: .secondarySystemGroupedBackground)
            )
    }

    private func sectionTitle(
        _ title: String,
        subtitle: String
    ) -> some View {

        VStack(alignment: .leading, spacing: 5) {

            Text(title)
                .font(.headline)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func selectionCard(
        title: String,
        value: String,
        icon: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {

        VStack(alignment: .leading, spacing: 12) {

            HStack(spacing: 10) {

                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 3) {

                    Text(title)
                        .font(.headline)

                    Text(value)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)
            }

            Button(
                buttonTitle,
                action: action
            )
            .buttonStyle(.bordered)
        }
        .padding(16)
        .background(cardBackground)
    }

    private func infoBox(
        _ text: String
    ) -> some View {

        HStack(alignment: .top, spacing: 10) {

            Image(systemName: "info.circle")
                .foregroundStyle(.blue)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.blue.opacity(0.08)
        )
        .clipShape(
            RoundedRectangle(cornerRadius: 10)
        )
    }

    private func summaryRow(
        _ title: String,
        _ value: String?
    ) -> some View {

        HStack {

            Text(title)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value ?? "선택되지 않음")
                .lineLimit(1)
                .multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }

    private func countCard(
        _ title: String,
        value: Int,
        color: Color
    ) -> some View {

        VStack(spacing: 5) {

            Text("\(value)")
                .font(.title2.bold())
                .foregroundStyle(color)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(cardBackground)
    }

    private func handlePicker(
        _ result: Result<[URL], Error>,
        key: String,
        completion: (URL) -> Void
    ) {

        switch result {

        case .success(let urls):

            guard let url = urls.first else {
                return
            }

            completion(url)

            settings.saveBookmark(
                url: url,
                key: key
            )

        case .failure(let error):

            logs.append(
                "파일 선택 실패: \(error.localizedDescription)"
            )
        }
    }

    private func restoreSavedPaths() {

        sourceURL = settings.restoreBookmark(
            key: "sourceBookmark"
        )

        destinationURL = settings.restoreBookmark(
            key: "destinationBookmark"
        )

        p12URL = settings.restoreBookmark(
            key: "p12Bookmark"
        )

        profileURL = settings.restoreBookmark(
            key: "profileBookmark"
        )
    }

    private func startSigning() {

        guard let sourceURL,
              let destinationURL,
              let p12URL,
              let profileURL else {

            logs.append(
                "오류: 모든 경로를 선택해주세요."
            )

            selectedPage = .logs

            return
        }

        guard !settings.bundleIdentifier.isEmpty else {

            logs.append(
                "오류: Bundle ID를 입력해주세요."
            )

            selectedPage = .certificate

            return
        }

        isSigning = true

        progressValue = 0
        progressText = "작업 준비 중"

        logs.removeAll()

        successCount = 0
        failedCount = 0
        skippedCount = 0
        replacedCount = 0

        selectedPage = .logs

        DispatchQueue.global(
            qos: .userInitiated
        ).async {

            do {

                let result = try SigningService.shared.signFolder(
                    sourceURL: sourceURL,
                    destinationURL: destinationURL,
                    p12URL: p12URL,
                    profileURL: profileURL,
                    password: settings.password,
                    bundleIdentifier: settings.bundleIdentifier,
                    deleteFailedCopies: settings.deleteFailedCopies
                ) { message, progress in

                    DispatchQueue.main.async {

                        self.progressText = message
                        self.progressValue = progress
                    }
                }

                DispatchQueue.main.async {

                    self.successCount = result.success
                    self.failedCount = result.failed
                    self.skippedCount = result.skipped
                    self.replacedCount = result.replaced

                    self.logs.append(
                        contentsOf: result.messages
                    )

                    self.isSigning = false
                }

            } catch {

                DispatchQueue.main.async {

                    self.logs.append(
                        "작업 실패: \(error.localizedDescription)"
                    )

                    self.isSigning = false
                }
            }
        }
    }
}
