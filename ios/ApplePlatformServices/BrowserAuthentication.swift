import AuthenticationServices
import Foundation
import UIKit

@MainActor
final class BrowserAuthentication: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var anchor: ASPresentationAnchor?
    private var pending: (id: UUID, continuation: CheckedContinuation<URL, Error>)?

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try Task.checkCancellation()
        cancel()
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows).first(where: \.isKeyWindow) else { throw BrowserError.noWindow }
        let attempt = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                pending = (attempt, continuation)
                anchor = window
                let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { [weak self] callback, error in
                    Task { @MainActor in
                        let result: Result<URL, Error>
                        if let error { result = .failure(error) }
                        else if let callback { result = .success(callback) }
                        else { result = .failure(BrowserError.missingCallback) }
                        self?.finish(attempt: attempt, result: result)
                    }
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = true
                self.session = session
                if !session.start() {
                    finish(attempt: attempt, result: .failure(BrowserError.noWindow))
                }
            }
        } onCancel: { [weak self] in
            Task { @MainActor in self?.cancel(attempt: attempt) }
        }
    }

    func cancel() {
        guard let pending else { return }
        cancel(attempt: pending.id)
    }

    private func cancel(attempt: UUID) {
        finish(attempt: attempt, result: .failure(CancellationError()), cancelSession: true)
    }

    /// All completion paths consume the continuation before touching the session.
    /// A late callback from a canceled attempt cannot clear a newer browser.
    private func finish(attempt: UUID, result: Result<URL, Error>, cancelSession: Bool = false) {
        guard let pending, pending.id == attempt else { return }
        self.pending = nil
        let finishedSession = session
        session = nil
        anchor = nil
        if cancelSession { finishedSession?.cancel() }
        pending.continuation.resume(with: result)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor ?? ASPresentationAnchor()
    }

    enum BrowserError: LocalizedError {
        case noWindow, missingCallback
        var errorDescription: String? { "The authorization browser could not be opened. Try again with the app in the foreground." }
    }
}
