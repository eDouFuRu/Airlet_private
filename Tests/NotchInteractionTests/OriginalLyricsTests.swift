import XCTest
@testable import NotchInteractionCore

final class OriginalLyricsTests: XCTestCase {
    private let track = LyricsTrack(source: "com.netease.163music", title: "远走高飞", artist: "林忆莲", album: "2001莲", duration: 222.693333)

    func testNetEaseMatchesExactReleaseAndMillisecondDuration() throws {
        let json = #"{"code":200,"result":{"songs":[{"id":42,"name":"远走高飞","artists":[{"name":"林憶蓮"}],"album":{"name":"2001 莲"},"duration":222693}]}}"#
        let response = try JSONDecoder().decode(NetEaseSearchResponse.self, from: Data(json.utf8))
        XCTAssertEqual(NetEaseSongRecord.bestMatch(response.result?.songs ?? [], track: track)?.id, 42)
    }
    func testWrongReleaseCoverAndSimilarTitleAreRejected() {
        let variants: [(String, String, String, Double)] = [
            ("远走高飞", "林忆莲", "精选", 222693), ("远走高飞", "林忆莲", "2001莲", 224000),
            ("远走高飞", "别的歌手", "2001莲", 222693), ("远走高飞 (Live)", "林忆莲", "2001莲", 222693)]
        for (title, artist, album, duration) in variants {
            let item = NetEaseSongRecord(id: 42, name: title, artists: [.init(name: artist)], album: .init(name: album), duration: duration)
            XCTAssertFalse(item.matches(track))
        }
    }
    func testDifferentSongIDsWithEquallyCloseTimingRemainAmbiguous() {
        let first = NetEaseSongRecord(id: 42, name: track.title, artists: [.init(name: track.artist)], album: .init(name: track.album), duration: 222693)
        let second = NetEaseSongRecord(id: 43, name: track.title, artists: first.artists, album: first.album, duration: first.duration)
        XCTAssertNil(NetEaseSongRecord.bestMatch([first, second], track: track))
        XCTAssertEqual(NetEaseSongRecord.bestMatch([first, first], track: track)?.id, 42)
    }
    func testMissingDurationNeverBorrowsAnotherClock() {
        let unknown = LyricsTrack(source: track.source, title: track.title, artist: track.artist, album: track.album, duration: 0)
        let record = NetEaseSongRecord(id: 42, name: track.title, artists: [.init(name: track.artist)], album: .init(name: track.album), duration: 222693)
        XCTAssertNil(NetEaseSongRecord.bestMatch([record], track: unknown))
    }
    func testOnlyOriginalLRCIsDecodedNotChineseTranslationOrPhonetics() throws {
        let json = #"{"code":200,"lrc":{"lyric":"[00:05.240]Original English"},"romalrc":{"lyric":"[00:01]pin yin"},"tlyric":{"lyric":"[00:02]中文翻译"}}"#
        let response = try JSONDecoder().decode(NetEaseLyricResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.document?.line(at: 5.239), "")
        XCTAssertEqual(response.document?.line(at: 5.24), "Original English")
        XCTAssertEqual(response.document?.cues.count, 1)
    }
    func testTranslatedLyricsAloneDoNotBecomeOriginalLyrics() throws {
        let json = #"{"code":200,"tlyric":{"lyric":"[00:02]中文翻译"},"romalrc":{"lyric":"[00:02]pin yin"}}"#
        XCTAssertNil(try JSONDecoder().decode(NetEaseLyricResponse.self, from: Data(json.utf8)).document)
    }
    func testRomanizationDetectionDoesNotUseChineseArtistAsEnglishLanguageSignal() {
        let pinyin = LyricsDocument(cues: (0..<4).map { LyricCue(time: Double($0), text: "wo men zai zhe li deng ni hui lai") })
        let english = LyricsDocument(cues: (0..<4).map { LyricCue(time: Double($0), text: "We are walking under silver clouds together tonight") })
        XCTAssertTrue(OriginalLyricLanguage.isRomanizedMandarin(pinyin, track: track))
        XCTAssertFalse(OriginalLyricLanguage.isRomanizedMandarin(english, track: track))
        XCTAssertEqual(LyricsTextPresentation.render(line: "Hello, don't change my words", simplifiedChinese: true), "Hello, don't change my words")
    }
    func testChineseTextAndOtherOriginalScriptsAreNotRomanization() {
        for line in ["我们在这里等你回来", "君の願いを聞いている", "우리는 여기에서 기다려요", "Nous marchons sous les nuages ce soir"] {
            let doc = LyricsDocument(cues: (0..<4).map { LyricCue(time: Double($0), text: line) })
            XCTAssertFalse(OriginalLyricLanguage.isRomanizedMandarin(doc, track: track))
        }
    }
    func testJapaneseDocumentProtectsKanjiOnlyLinesFromChineseConversion() {
        let doc = LyricsDocument(cues: [LyricCue(time: 0, text: "君の願い"), LyricCue(time: 2, text: "運命")])
        XCTAssertFalse(doc.permitsChineseSimplification)
        XCTAssertEqual(LyricsTextPresentation.render(line: "君の願い", simplifiedChinese: true), "君の願い")
        XCTAssertTrue(LyricsDocument(cues: [LyricCue(time: 0, text: "願你快樂"), LyricCue(time: 2, text: "Hello")]).permitsChineseSimplification)
    }
    func testDuplicatePhoneticLineIsRemovedInEitherOrder() {
        for lrc in ["[00:01]你好世界\n[00:01]ni hao shi jie", "[00:01]ni hao shi jie\n[00:01]你好世界"] {
            XCTAssertEqual(LRCParser.parse(lrc), [LyricCue(time: 1, text: "你好世界")])
        }
        XCTAssertEqual(LRCParser.parse("[00:01]你好世界\n[00:01]Hello world"), [LyricCue(time: 1, text: "你好世界 · Hello world")])
    }
}
