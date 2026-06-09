//
//  MiniMusixTests.swift
//  MiniMusixTests
//
//  Created by khadar on 6/2/26.
//

import Testing
import Foundation
import SwiftUI
@testable import MiniMusix

struct MiniMusixTests {

    @Test func lrclibSearchFindsCleanedMetadataVariant() async throws {
        MockURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            if path == "/api/search" {
                let response = """
                [
                  {
                    "id": 42,
                    "trackName": "Happier Than Ever",
                    "artistName": "Billie Eilish",
                    "albumName": "Happier Than Ever",
                    "duration": 298,
                    "instrumental": false,
                    "plainLyrics": "When I'm away from you",
                    "syncedLyrics": null
                  }
                ]
                """
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(response.utf8))
            }

            return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let coordinator = LyricsFetchCoordinator(cache: LyricsCacheManager(), session: session)
        let track = NowPlayingTrack(
            identity: TrackIdentity(
                title: "Happier Than Ever - Edit",
                artist: "Billie Eilish feat. FINNEAS",
                album: "",
                duration: 298
            ),
            artworkSystemName: "music.note",
            artwork: nil,
            dominantColor: .blue,
            secondaryColor: .green,
            elapsed: 0,
            playbackState: .playing,
            source: .appleMusic,
            applicationName: nil,
            bundleIdentifier: nil
        )

        let payload = await coordinator.lyrics(for: track, settings: MiniMusixSettings())

        guard case .plain(let lyrics) = payload else {
            Issue.record("Expected plain lyrics, got \(payload)")
            return
        }

        #expect(lyrics == "When I'm away from you")
    }

}

final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
