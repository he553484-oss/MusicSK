import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class MockProtocol: URLProtocol {
    static var requests: [String] = []
    static var rejectDetails = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        let params = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        let call = params["__call"] ?? ""
        Self.requests.append(call + ":" + (params["bitrate"] ?? ""))
        let status: Int
        let body: String
        if call == "search.getResults" {
            status = 200
            body = #"{"results":[null,{"id":"track","title":"Song","more_info":{}},{"id":"","title":"Bad"}]}"#
        } else if call == "song.getDetails" {
            status = Self.rejectDetails ? 503 : 200
            body = #"{"songs":[{"id":"track","more_info":{"encrypted_media_url":"opaque"}}]}"#
        } else if call == "song.generateAuthToken", params["bitrate"] == "160" {
            status = 200
            body = #"{"auth_url":"https://cdn.example.test/audio.mp4"}"#
        } else {
            status = 403
            body = #"{"error":"unavailable"}"#
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct Verify {
    static func main() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockProtocol.self]
        let session = URLSession(configuration: configuration)
        let hits = await JioSaavn.search(" Song ", session: session)
        precondition(hits.count == 1 && hits[0].videoId == "saavn:track")
        precondition(MockProtocol.requests == ["search.getResults:"])
        MockProtocol.requests = []
        let empty = await JioSaavn.search("  ", session: session)
        precondition(empty.isEmpty && MockProtocol.requests.isEmpty)
        let emptyId = await JioSaavn.streamURL(for: "saavn:", session: session)
        precondition(emptyId == nil && MockProtocol.requests.isEmpty)
        let result = await JioSaavn.streamURL(for: "saavn:track", session: session)
        precondition(result?.url == "https://cdn.example.test/audio.mp4" && result?.kbps == 160)
        precondition(MockProtocol.requests == ["song.getDetails:", "song.generateAuthToken:320", "song.generateAuthToken:160"])
        MockProtocol.requests = []
        MockProtocol.rejectDetails = true
        let unavailable = await JioSaavn.streamURL(for: "track", session: session)
        precondition(unavailable == nil && MockProtocol.requests == ["song.getDetails:"])
        print("JioSaavn stream resolution checks passed")
    }
}
