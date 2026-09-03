import Foundation
import VizionCore

/// The deployed VIZION web app's route handlers are the model proxy (ADR-0002):
/// `/api/enhance` (SSE), `/api/media` (JSON), `/api/account` (DELETE). Every
/// request carries the Supabase access token as a Bearer header; the server
/// verifies it against Supabase Auth before any route runs (ADR-0003).
final class VizionAPI: Sendable {
  typealias TokenProvider = @Sendable () async throws -> String

  let baseURL: URL
  private let tokenProvider: TokenProvider
  private let session: URLSession

  init(baseURL: URL, tokenProvider: @escaping TokenProvider, session: URLSession? = nil) {
    self.baseURL = baseURL
    self.tokenProvider = tokenProvider
    if let session {
      self.session = session
    } else {
      let configuration = URLSessionConfiguration.default
      // Long enhancements stream for minutes; idle is bounded server-side.
      configuration.timeoutIntervalForRequest = 90
      configuration.timeoutIntervalForResource = 320
      configuration.waitsForConnectivity = true
      self.session = URLSession(configuration: configuration)
    }
  }

  private func request(_ method: String, path: String, body: Data?, accept: String) async throws -> URLRequest {
    var request = URLRequest(url: baseURL.appending(path: path))
    request.httpMethod = method
    request.setValue("Bearer \(try await tokenProvider())", forHTTPHeaderField: "Authorization")
    request.setValue(accept, forHTTPHeaderField: "Accept")
    request.setValue("VIZION-iOS/\(AppVersion.marketing) (\(AppVersion.build))", forHTTPHeaderField: "User-Agent")
    if let body {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = body
    }
    return request
  }

  /// Decode a non-200 JSON gate failure into the shared failure type.
  private static func failure(status: Int, data: Data, fallback: String) -> EnhanceFailure {
    let body = (try? JSONDecoder().decode(APIErrorBody.self, from: data)) ?? APIErrorBody(error: nil)
    let message = body.error ?? (status == 401 ? "Your session expired — sign in again." : fallback)
    return APIErrorBody(error: message, notConfigured: body.notConfigured, capReached: body.capReached)
      .failure(status: status, fallback: fallback)
  }

  // MARK: /api/enhance

  /// Live events from the enhance stream. Gate failures (401/400/413/429/503)
  /// arrive as plain JSON with real statuses and are thrown as
  /// `EnhanceFailure`; a cancelled task throws `EnhanceFailure.cancelled`.
  func enhance(_ body: EnhanceRequest) -> AsyncThrowingStream<EnhanceStreamEvent, any Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          let payload = try JSONEncoder().encode(body)
          let request = try await self.request("POST", path: "/api/enhance", body: payload, accept: "text/event-stream")
          let (bytes, response) = try await self.session.bytes(for: request)
          let http = response as? HTTPURLResponse
          let status = http?.statusCode ?? 0
          let contentType = http?.value(forHTTPHeaderField: "Content-Type") ?? ""
          guard status == 200, contentType.contains("event-stream") else {
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            throw Self.failure(status: status, data: data, fallback: "Enhancement failed.")
          }
          var parser = SSEParser()
          var chunk: [UInt8] = []
          chunk.reserveCapacity(1024)
          for try await byte in bytes {
            chunk.append(byte)
            // Flush on a frame-boundary candidate or a full buffer.
            if byte == 0x0A || chunk.count >= 1024 {
              for event in parser.feed(chunk) { continuation.yield(event) }
              chunk.removeAll(keepingCapacity: true)
            }
            try Task.checkCancellation()
          }
          for event in parser.feed(chunk) { continuation.yield(event) }
          for event in parser.finish() { continuation.yield(event) }
          continuation.finish()
        } catch is CancellationError {
          continuation.finish(throwing: EnhanceFailure.cancelled)
        } catch let error as URLError where error.code == .cancelled {
          continuation.finish(throwing: EnhanceFailure.cancelled)
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  // MARK: /api/media

  func analyze(_ body: MediaAnalysisRequest) async throws -> MediaAnalysisResponse {
    let request = try await request("POST", path: "/api/media", body: try JSONEncoder().encode(body), accept: "application/json")
    let (data, response) = try await session.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard status == 200 else { throw Self.failure(status: status, data: data, fallback: "Extraction failed.") }
    return try JSONDecoder().decode(MediaAnalysisResponse.self, from: data)
  }

  // MARK: /api/account

  /// Permanently delete the signed-in account (App Store 5.1.1(v)). 204 on success.
  func deleteAccount() async throws {
    let request = try await request("DELETE", path: "/api/account", body: nil, accept: "application/json")
    let (data, response) = try await session.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard status == 204 || status == 200 else {
      throw Self.failure(status: status, data: data, fallback: "Couldn't delete your account.")
    }
  }
}
