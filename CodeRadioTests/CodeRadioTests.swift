//
//  CodeRadioTests.swift
//  CodeRadioTests
//
//  Created by uke on 2026/8/27.
//

import Foundation
import ServiceManagement
import Testing
@testable import CodeRadio

struct CodeRadioTests {

    @MainActor
    @Test func decodesNowPlayingResponse() throws {
        let json = #"""
        {
          "station": {
            "mounts": [
              {
                "id": 1,
                "name": "128kbps MP3",
                "url": "https://example.com/radio.mp3",
                "bitrate": 128
              }
            ]
          },
          "listeners": { "current": 42 },
          "now_playing": {
            "played_at": 1000,
            "duration": 180,
            "song": {
              "id": "song-1",
              "title": "Test Track",
              "artist": "Test Artist",
              "album": "Test Album",
              "art": "https://example.com/art.jpg"
            }
          },
          "song_history": [
            {
              "played_at": 900,
              "song": {
                "id": "song-0",
                "title": "Previous Track",
                "artist": "Previous Artist",
                "album": "Previous Album",
                "art": "https://example.com/previous.jpg"
              }
            }
          ],
          "is_online": true
        }
        """#.data(using: .utf8)!

        let response = try JSONDecoder.codeRadio.decode(CodeRadioResponse.self, from: json)

        #expect(response.isOnline == true)
        #expect(response.listeners?.current == 42)
        #expect(response.nowPlaying?.song?.title == "Test Track")
        #expect(response.station?.mounts.first?.bitrate == 128)
        #expect(response.songHistory?.first?.song?.title == "Previous Track")
    }

    @MainActor
    @Test("Partial metadata keeps independently usable fields")
    func decodesPartialMetadata() throws {
        let json = #"""
        {
          "station": { "mounts": "temporarily unavailable" },
          "listeners": { "current": "many" },
          "now_playing": {
            "played_at": "unknown",
            "duration": 0
          },
          "is_online": "unknown",
          "unexpected": { "future": true }
        }
        """#.data(using: .utf8)!

        let response = try JSONDecoder.codeRadio.decode(CodeRadioResponse.self, from: json)

        #expect(response.station?.mounts.isEmpty == true)
        #expect(response.listeners?.current == nil)
        #expect(response.nowPlaying?.playedAt == nil)
        #expect(response.nowPlaying?.duration == nil)
        #expect(response.nowPlaying?.song == nil)
        #expect(response.songHistory == nil)
        #expect(response.isOnline == nil)
    }

    @MainActor
    @Test("Malformed collection entries do not discard usable metadata")
    func skipsMalformedCollectionEntries() throws {
        let json = #"""
        {
          "station": {
            "mounts": [
              {
                "id": 1,
                "name": "128kbps MP3",
                "url": "https://example.com/radio.mp3",
                "bitrate": 128
              },
              { "id": "broken" }
            ]
          },
          "listeners": { "current": 0 },
          "now_playing": {
            "played_at": -1,
            "duration": -5,
            "song": {
              "id": "song-1",
              "title": 42,
              "artist": null,
              "album": false,
              "art": 7
            }
          },
          "song_history": [
            {
              "played_at": 900,
              "song": {
                "id": "song-0",
                "title": "Usable Track",
                "artist": "Usable Artist"
              }
            },
            42
          ]
        }
        """#.data(using: .utf8)!

        let response = try JSONDecoder.codeRadio.decode(CodeRadioResponse.self, from: json)

        #expect(response.station?.mounts.count == 1)
        #expect(response.listeners?.current == 0)
        #expect(response.nowPlaying?.playedAt == nil)
        #expect(response.nowPlaying?.duration == nil)
        #expect(response.nowPlaying?.song?.title == "Unknown title")
        #expect(response.nowPlaying?.song?.artist == "Unknown artist")
        #expect(response.nowPlaying?.song?.album.isEmpty == true)
        #expect(response.nowPlaying?.song?.art == nil)
        #expect(response.songHistory?.compactMap(\.song).map(\.title) == ["Usable Track"])
    }

    @MainActor
    @Test("Structurally unusable metadata still fails decoding")
    func rejectsStructurallyUnusableMetadata() {
        let unusablePayloads = [
            #"["not", "a", "station"]"#,
            #"{}"#,
            #"{ "unexpected": true }"#,
            #"{ "station": 42, "listeners": "many", "is_online": "unknown" }"#,
        ]

        for payload in unusablePayloads {
            #expect(throws: DecodingError.self) {
                try JSONDecoder.codeRadio.decode(
                    CodeRadioResponse.self,
                    from: Data(payload.utf8)
                )
            }
        }
    }

    @MainActor
    @Test func togglesLaunchAtLoginRegistration() {
        let service = FakeLoginItemService()
        let controller = LaunchAtLoginController(service: service)

        controller.setEnabled(true)

        #expect(service.registerCallCount == 1)
        #expect(controller.isRequested)
        #expect(!controller.requiresApproval)

        controller.setEnabled(false)

        #expect(service.unregisterCallCount == 1)
        #expect(!controller.isRequested)
        #expect(controller.errorMessage == nil)
    }

}

@MainActor
private final class FakeLoginItemService: LoginItemServicing {
    var status: SMAppService.Status = .notRegistered
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0

    func register() throws {
        registerCallCount += 1
        status = .enabled
    }

    func unregister() throws {
        unregisterCallCount += 1
        status = .notRegistered
    }
}
