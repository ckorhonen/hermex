import Foundation

extension APIClient {
    func transcriptMediaData(for reference: TranscriptMediaReference) async throws -> Data {
        switch reference.source {
        case let .localPath(path):
            return try await mediaData(path: path)
        case let .remoteURL(url):
            return try await remoteTranscriptMediaData(from: url)
        }
    }

    /// Streams transcript media straight to `destination` (see
    /// `downloadFile`). Session/header selection mirrors
    /// `transcriptMediaData`: the authed session for the user's own server,
    /// the cookie-less public session for third-party URLs.
    func downloadTranscriptMedia(
        for reference: TranscriptMediaReference,
        to destination: URL
    ) async throws {
        switch reference.source {
        case let .localPath(path):
            try await downloadFile(
                from: Endpoint.media(path: path).url(relativeTo: baseURL),
                to: destination,
                using: session,
                mapsUnauthorized: true
            )
        case let .remoteURL(url):
            if Self.isSameOrigin(url, as: baseURL) {
                try await downloadFile(from: url, to: destination, using: session, mapsUnauthorized: true)
            } else {
                try await downloadFile(from: url, to: destination, using: publicMediaSession, mapsUnauthorized: false)
            }
        }
    }
}
