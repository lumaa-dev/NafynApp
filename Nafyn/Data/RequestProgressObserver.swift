// Made by Lumaa

import Foundation
import Safyn

/// Owns a single ``NafynDownloadSocket`` for one visible ``RequestRow``, exposing its latest
/// ``DownloadProgressEvent`` as observable state. Auto-disconnects once a terminal stage arrives.
///
/// `@unchecked Sendable` mirrors Safyn's own `NafynDownloadSocket`: every mutation is funneled through
/// `Task { @MainActor in ... }` from the socket's callback, so `progress`/`socket` are never touched
/// from more than one execution context at a time.
@Observable
final class RequestProgressObserver: @unchecked Sendable {
    private(set) var progress: DownloadProgressEvent? = nil
    private var socket: NafynDownloadSocket? = nil

    func connect(server: NafynServer, requestId: String) {
        guard self.socket == nil, let socket = try? server.downloadSocket(requestId: requestId) else { return }

        socket.onEvent = { [weak self] event in
            guard let self else { return }

            Task { @MainActor [self] in
                self.progress = event
                if event.stage == .completed || event.stage == .failed {
                    self.disconnect()
                }
            }
        }
        socket.connect()
        self.socket = socket
    }

    func disconnect() {
        self.socket?.disconnect()
        self.socket = nil
    }

    deinit {
        self.socket?.disconnect()
    }
}
