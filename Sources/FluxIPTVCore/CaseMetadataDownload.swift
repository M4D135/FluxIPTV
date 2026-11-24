import Foundation
import Dispatch
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Small public-metadata requests with a limit enforced as chunks arrive.
/// Redirects are checked before URLSession receives permission to follow them.
public enum CaseMetadataDownload {
    private static let byteLimit = 2 * 1024 * 1024
    private static let totalTimeout: TimeInterval = 18
    private static let hosts: Set<String> = ["fr.wikipedia.org", "www.wikidata.org", "www.allocine.fr", "allocine.fr"]

    public static func data(from request: URLRequest) async throws -> Data {
        try Task.checkCancellation()
        let transfer = try Transfer(request: request)
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                transfer.start(continuation)
            }
        }, onCancel: {
            transfer.cancel()
        })
    }

    private static func canonicalURL(_ url: URL?) -> URL? {
        guard let url, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https", let host = parts.host?.lowercased(),
              hosts.contains(host), parts.user == nil, parts.password == nil,
              parts.port == nil || parts.port == 443 else { return nil }
        parts.scheme = "https"; parts.host = host
        return parts.url
    }

    private static func isAllocine(_ host: String) -> Bool {
        host == "www.allocine.fr" || host == "allocine.fr"
    }

    /// Keep one ephemeral transport for the process. Per-request sessions can
    /// crash in FoundationNetworking's curl teardown on Linux; sharing also
    /// reuses connections on Apple platforms. Only active transfers are retained.
    private final class Transport: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        static let shared = Transport()
        private let lock = NSLock()
        private var transfers: [Int: Transfer] = [:]
        private var session: URLSession!

        private override init() {
            super.init()
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 10
            configuration.timeoutIntervalForResource = CaseMetadataDownload.totalTimeout
            configuration.httpMaximumConnectionsPerHost = 2
            configuration.urlCache = nil; configuration.httpCookieStorage = nil
            configuration.urlCredentialStorage = nil; configuration.httpShouldSetCookies = false
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 1
            session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        }

        func task(with request: URLRequest, transfer: Transfer) -> URLSessionDataTask {
            // No completion-handler overload: that would buffer the full body.
            let task = session.dataTask(with: request)
            lock.lock(); transfers[task.taskIdentifier] = transfer; lock.unlock()
            return task
        }

        func remove(_ task: URLSessionTask) {
            lock.lock(); transfers.removeValue(forKey: task.taskIdentifier); lock.unlock()
        }

        private func transfer(for task: URLSessionTask) -> Transfer? {
            lock.lock(); defer { lock.unlock() }
            return transfers[task.taskIdentifier]
        }

        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            guard let transfer = transfer(for: task) else { completionHandler(nil); return }
            transfer.urlSession(session, task: task, willPerformHTTPRedirection: response,
                                newRequest: request, completionHandler: completionHandler)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                        didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            guard let transfer = transfer(for: dataTask) else { completionHandler(.cancel); return }
            transfer.urlSession(session, dataTask: dataTask, didReceive: response, completionHandler: completionHandler)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            transfer(for: dataTask)?.urlSession(session, dataTask: dataTask, didReceive: data)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            transfer(for: task)?.urlSession(session, task: task, didCompleteWithError: error)
        }
    }

    /// Delegate callbacks, task cancellation and the deadline can race. Every
    /// mutable field belongs to this lock; finish is the sole completion gate.
    private final class Transfer: @unchecked Sendable {
        private let request: URLRequest
        private let originHost: String
        private let allocineID: String?
        private let allocineSeries: Bool
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Data, Error>?
        private var terminal: Result<Data, Error>?
        private var task: URLSessionDataTask?
        private var deadline: DispatchWorkItem?
        private var buffer = Data()
        private var responseAccepted = false
        private var redirectCount = 0

        init(request: URLRequest) throws {
            guard let url = CaseMetadataDownload.canonicalURL(request.url), let host = url.host,
                  (request.httpMethod ?? "GET").uppercased() == "GET",
                  request.httpBody == nil, request.httpBodyStream == nil else { throw URLError(.unsupportedURL) }
            originHost = host
            if CaseMetadataDownload.isAllocine(host) {
                if let id = CaseDescriptionParser.allocineIdentifier(url, series: false) {
                    allocineID = id; allocineSeries = false
                } else if let id = CaseDescriptionParser.allocineIdentifier(url, series: true) {
                    allocineID = id; allocineSeries = true
                } else { throw URLError(.unsupportedURL) }
            } else { allocineID = nil; allocineSeries = false }
            var clean = request
            clean.url = url; clean.timeoutInterval = 10
            clean.cachePolicy = .reloadIgnoringLocalCacheData
            clean.httpShouldHandleCookies = false
            for name in ["Authorization", "Proxy-Authorization", "Cookie"] {
                clean.setValue(nil, forHTTPHeaderField: name)
            }
            self.request = clean
        }

        func start(_ continuation: CheckedContinuation<Data, Error>) {
            lock.lock()
            // Cancellation is allowed to arrive before the continuation exists.
            if let terminal {
                lock.unlock(); continuation.resume(with: terminal); return
            }
            self.continuation = continuation
            let task = Transport.shared.task(with: request, transfer: self)
            let deadline = DispatchWorkItem { [weak self] in self?.finish(URLError(.timedOut)) }
            self.task = task; self.deadline = deadline
            lock.unlock()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + CaseMetadataDownload.totalTimeout, execute: deadline)
            // If cancellation won immediately above, this task is already
            // cancelled; resuming it cannot start a replacement request.
            task.resume()
        }

        func cancel() { finish(CancellationError()) }

        private func permits(_ rawURL: URL?) -> URL? {
            guard let url = CaseMetadataDownload.canonicalURL(rawURL), let host = url.host,
                  host == originHost || (CaseMetadataDownload.isAllocine(host) && CaseMetadataDownload.isAllocine(originHost)) else { return nil }
            if let allocineID {
                guard CaseDescriptionParser.allocineIdentifier(url, series: allocineSeries) == allocineID else { return nil }
            }
            return url
        }

        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            lock.lock()
            let active = terminal == nil
            if active { redirectCount += 1 }
            let withinLimit = redirectCount <= 5
            lock.unlock()
            guard active else { completionHandler(nil); return }
            guard withinLimit else { finish(URLError(.httpTooManyRedirects)); completionHandler(nil); return }
            guard permits(response.url) != nil, let target = permits(request.url),
                  (request.httpMethod ?? "GET").uppercased() == "GET" else {
                finish(URLError(.unsupportedURL)); completionHandler(nil); return
            }
            var approved = request
            approved.url = target; approved.httpShouldHandleCookies = false
            approved.timeoutInterval = 10
            for name in ["Authorization", "Proxy-Authorization", "Cookie"] {
                approved.setValue(nil, forHTTPHeaderField: name)
            }
            completionHandler(approved)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                        didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode), permits(http.url) != nil else {
                finish(URLError(.badServerResponse)); completionHandler(.cancel); return
            }
            guard response.expectedContentLength <= Int64(CaseMetadataDownload.byteLimit) else {
                finish(URLError(.dataLengthExceedsMaximum)); completionHandler(.cancel); return
            }
            lock.lock()
            let active = terminal == nil
            if active { responseAccepted = true }
            lock.unlock()
            completionHandler(active ? .allow : .cancel)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            lock.lock()
            guard terminal == nil else { lock.unlock(); return }
            guard responseAccepted else { lock.unlock(); finish(URLError(.badServerResponse)); return }
            // Subtraction avoids overflow; buffer never exceeds this bound.
            guard data.count <= CaseMetadataDownload.byteLimit - buffer.count else {
                lock.unlock(); finish(URLError(.dataLengthExceedsMaximum)); return
            }
            buffer.append(data)
            lock.unlock()
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            finish(error)
        }

        private func finish(_ error: Error?) {
            lock.lock()
            guard terminal == nil else { lock.unlock(); return }
            let result: Result<Data, Error>
            if let error { result = .failure(error) }
            else if responseAccepted { result = .success(buffer) }
            else { result = .failure(URLError(.badServerResponse)) }
            terminal = result
            let continuation = self.continuation, task = self.task, deadline = self.deadline
            self.continuation = nil; self.task = nil; self.deadline = nil
            buffer = Data()
            lock.unlock()
            deadline?.cancel()
            if let task { Transport.shared.remove(task); task.cancel() }
            continuation?.resume(with: result)
        }
    }
}
