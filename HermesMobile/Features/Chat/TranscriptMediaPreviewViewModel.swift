import Foundation
import os
import SwiftUI

@MainActor
@Observable
final class TranscriptMediaPreviewViewModel {
    private let reference: TranscriptMediaReference
    private let apiClient: APIClient
    private var didLoad = false
    private var originalData: Data?

    private(set) var previewData: Data?
    private(set) var textContent: String?
    private(set) var videoFileURL: URL?
    private(set) var originalByteCount: Int?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var lastError: Error?

    /// Mirror of `videoFileURL` that `deinit` (nonisolated) can read. A lock —
    /// not `nonisolated(unsafe)` — so a future capture of this view model by
    /// non-main-actor code can't silently turn the deinit read into a race.
    @ObservationIgnored private let temporaryVideoFileURLForCleanup = OSAllocatedUnfairLock<URL?>(initialState: nil)

    deinit {
        if let url = temporaryVideoFileURLForCleanup.withLock({ $0 }) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    init(server: URL, reference: TranscriptMediaReference, apiClient: APIClient? = nil) {
        self.reference = reference
        self.apiClient = apiClient ?? APIClient(baseURL: server)
    }

    var canSaveImageToPhotos: Bool {
        reference.isRasterImageCandidate && previewData != nil
    }

    func load(force: Bool = false) async {
        guard force || !didLoad else { return }
        didLoad = true
        previewData = nil
        textContent = nil
        removeTemporaryVideoFile()
        originalByteCount = nil

        guard reference.isRasterImageCandidate
            || reference.isTextDocumentCandidate
            || reference.isVideoCandidate else {
            errorMessage = String(localized: "Preview is not available for this media type.")
            return
        }

        isLoading = true
        errorMessage = nil
        lastError = nil
        defer {
            isLoading = false
        }

        do {
            if reference.isVideoCandidate {
                let fileURL = Self.temporaryVideoFileDestination(for: reference)
                try await apiClient.downloadTranscriptMedia(for: reference, to: fileURL)
                videoFileURL = fileURL
                temporaryVideoFileURLForCleanup.withLock { $0 = fileURL }
                let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
                originalByteCount = (attributes?[.size] as? NSNumber)?.intValue
                return
            }

            let data = try await apiClient.transcriptMediaData(for: reference)
            originalData = data
            originalByteCount = data.count
            if reference.isRasterImageCandidate {
                if let downsampled = await ImagePreviewDownsampler.previewDataAsync(
                    from: data,
                    maxPixelSize: ImagePreviewDownsampler.filePreviewMaxPixelSize
                ) {
                    previewData = downsampled
                } else {
                    errorMessage = String(localized: "Could not decode this image.")
                }
            } else if let decodedText = Self.decodedText(from: data) {
                textContent = decodedText
            } else {
                errorMessage = String(localized: "Could not decode this text file.")
            }
        } catch {
            lastError = error
            errorMessage = error.localizedDescription
        }
    }

    func originalImageData() async throws -> Data {
        if let originalData {
            return originalData
        }

        let data = try await apiClient.transcriptMediaData(for: reference)
        originalData = data
        originalByteCount = data.count
        return data
    }

    private func removeTemporaryVideoFile() {
        guard let videoFileURL else { return }
        try? FileManager.default.removeItem(at: videoFileURL)
        self.videoFileURL = nil
        temporaryVideoFileURLForCleanup.withLock { $0 = nil }
    }

    /// AVPlayer needs a file URL rather than raw bytes, so the download is
    /// streamed to a uniquely named temp file. The file is removed on reload
    /// and deinit; the OS also purges the temp directory. The "mp4" fallback
    /// is defensive only — video candidates always carry a known extension.
    private static func temporaryVideoFileDestination(
        for reference: TranscriptMediaReference
    ) -> URL {
        let ext = reference.pathExtension
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("transcript-media-\(UUID().uuidString)")
            .appendingPathExtension(ext.isEmpty ? "mp4" : ext)
    }

    private static func decodedText(from data: Data) -> String? {
        for encoding in [String.Encoding.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, .isoLatin1, .ascii] {
            if let value = String(data: data, encoding: encoding) {
                return value
            }
        }

        return nil
    }
}
