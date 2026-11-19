import Foundation
import SappaCore

/// The network side of the core's `HttpTransport`: URLSession with the system's default
/// certificate checks, no cookies, no cache. The core calls `send` from a background thread and
/// expects it to block until the answer arrives.
final class URLSessionTransport: HttpTransport, @unchecked Sendable {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = false
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        session = URLSession(configuration: config)
    }

    func send(request: HttpRequest) throws -> HttpResponse {
        guard let url = URL(string: request.url), url.scheme?.lowercased() == "https" else {
            throw TransportError.Other(detail: "https only")
        }
        precondition(!Thread.isMainThread, "SAPPA core network calls must not run on the main thread")

        var urlRequest = URLRequest(url: url, timeoutInterval: TimeInterval(request.timeoutMs) / 1000)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for header in request.headers {
            urlRequest.setValue(header.value, forHTTPHeaderField: header.name)
        }

        let box = ResultBox()
        let done = DispatchSemaphore(value: 0)
        let task = session.dataTask(with: urlRequest) { data, response, error in
            if let error = error as? URLError {
                box.result = .failure(Self.map(error))
            } else if let error {
                box.result = .failure(.Other(detail: String(describing: type(of: error))))
            } else if let http = response as? HTTPURLResponse {
                box.result = .success(HttpResponse(status: UInt16(clamping: http.statusCode), body: data ?? Data()))
            } else {
                box.result = .failure(.Other(detail: "no http response"))
            }
            done.signal()
        }
        task.resume()
        let deadline = DispatchTime.now() + .milliseconds(Int(request.timeoutMs) + 2_000)
        if done.wait(timeout: deadline) == .timedOut {
            task.cancel()
            throw TransportError.Timeout
        }
        return try box.result.get()
    }

    static func map(_ error: URLError) -> TransportError {
        switch error.code {
        case .timedOut:
            return .Timeout
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
             .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff, .callIsActive:
            return .Offline
        default:
            return .Other(detail: "urlerror \(error.code.rawValue)")
        }
    }
}

private final class ResultBox: @unchecked Sendable {
    var result: Result<HttpResponse, TransportError> = .failure(.Timeout)
}
