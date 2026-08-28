import Foundation

struct StationMetadataClient {
    private static let endpoint = URL(
        string: "https://coderadio-admin-v2.freecodecamp.org/api/nowplaying_static/coderadio.json"
    )!

    let load: () async throws -> CodeRadioResponse

    static func live(session: URLSession = .codeRadioMetadata) -> StationMetadataClient {
        StationMetadataClient {
            var request = URLRequest(url: endpoint)
            request.timeoutInterval = 10
            request.cachePolicy = .reloadIgnoringLocalCacheData

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode)
            else {
                throw URLError(.badServerResponse)
            }

            return try JSONDecoder.codeRadio.decode(CodeRadioResponse.self, from: data)
        }
    }
}

private extension URLSession {
    static let codeRadioMetadata: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()
}
