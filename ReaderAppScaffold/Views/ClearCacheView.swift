import SwiftUI

/// 清除缓存页：对照设计稿，含"清除所有数据"、三个带空间占用的缓存开关、"清除选中缓存"
struct ClearCacheView: View {
    @State private var readingCacheSize: Int64 = 0
    @State private var tempCacheSize: Int64 = 0
    @State private var coverCacheSize: Int64 = 0
    @State private var selectReading = true
    @State private var selectTemp = true
    @State private var selectCover = true
    @State private var clearing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Button(role: .destructive) {
                    clearAll()
                } label: {
                    Text("清除所有数据")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(clearing)

                HStack {
                    Text("缓存选项").font(.footnote.bold()).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.leading, 6)

                VStack(spacing: 0) {
                    toggleRow("阅读缓存", size: readingCacheSize, selected: $selectReading)
                    cacheDivider
                    toggleRow("临时文件", size: tempCacheSize, selected: $selectTemp)
                    cacheDivider
                    toggleRow("封面缓存", size: coverCacheSize, selected: $selectCover)
                }
                .glassCard(RoundedRectangle(cornerRadius: 16))

                Button {
                    clearSelected()
                } label: {
                    Text("清除选中缓存")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .disabled(clearing)

                Text("阅读缓存与封面缓存仅保留已入架书籍，清除后再次阅读将重新下载。")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("清除缓存")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshSizes() }
    }

    private var cacheDivider: some View {
        Rectangle().fill(Theme.hairline).frame(height: 0.5).padding(.leading, 14)
    }

    private func toggleRow(_ title: String, size: Int64, selected: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Text(title).font(.subheadline)
            Spacer()
            Text(formatSize(size))
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("", isOn: selected)
                .labelsHidden()
                .tint(Theme.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func formatSize(_ size: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private func refreshSizes() async {
        async let reading = directorySize(ChapterContentCache.shared.directoryURL)
        async let cover = directorySize(ImageLoader.shared.directoryURL)
        async let temp = tempDirectorySize()
        readingCacheSize = await reading
        coverCacheSize = await cover
        tempCacheSize = await temp
    }

    private func directorySize(_ url: URL) async -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }

    private func tempDirectorySize() async -> Int64 {
        await directorySize(FileManager.default.temporaryDirectory)
    }

    private func clearAll() {
        clearing = true
        Task {
            await ChapterContentCache.shared.clearAll()
            await ImageLoader.shared.clearPersistentCache()
            clearTempDirectory()
            await refreshSizes()
            clearing = false
        }
    }

    private func clearSelected() {
        clearing = true
        Task {
            if selectReading { await ChapterContentCache.shared.clearAll() }
            if selectCover { await ImageLoader.shared.clearPersistentCache() }
            if selectTemp { clearTempDirectory() }
            await refreshSizes()
            clearing = false
        }
    }

    private func clearTempDirectory() {
        let temp = FileManager.default.temporaryDirectory
        if let items = try? FileManager.default.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil) {
            for item in items { try? FileManager.default.removeItem(at: item) }
        }
    }
}
