//
//  CodeRadioTests.swift
//  CodeRadioTests
//
//  Created by uke on 2026/8/27.
//

import Foundation
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

        #expect(response.isOnline)
        #expect(response.listeners.current == 42)
        #expect(response.nowPlaying.song.title == "Test Track")
        #expect(response.station.mounts.first?.bitrate == 128)
        #expect(response.songHistory.first?.song.title == "Previous Track")
    }

}
