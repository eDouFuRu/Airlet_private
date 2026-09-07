import Foundation
import Darwin

/// Explicit opt-in only. Prints timing/count metadata, never the lyric text.
/// A source timestamp is not evidence that someone has listened to its timing.
@main struct NetEaseLyricsLiveProbe {
    static func main() async {
        guard CommandLine.arguments.contains("--live") else {
            emit(["network_requested": false, "status": "skipped", "instruction": "Pass --live to run the anonymous production client lookup."])
            return
        }
        let track = LyricsTrack(source: "com.netease.163music", title: "远走高飞", artist: "林忆莲", album: "2001莲", duration: 222.693333)
        do {
            let document = try await NetEaseLyricsClient().lookup(track)
            var result: [String: Any] = ["network_requested": true, "matched": document != nil,
                                        "cue_count": document?.cues.count ?? 0,
                                        "tested_at": ISO8601DateFormatter().string(from: Date())]
            if let document {
                let nonempty = document.cues.filter { !$0.text.isEmpty }
                result["nonempty_cue_count"] = nonempty.count
                result["han_cue_count"] = nonempty.filter { OriginalLyricLanguage.containsHan($0.text) }.count
                result["romanized_document"] = OriginalLyricLanguage.isRomanizedMandarin(document, track: track)
                result["instrumental"] = document.instrumental
                if let first = nonempty.first { result["first_nonempty_cue_seconds"] = first.time }
                if let vocal = nonempty.first(where: { !isCredit($0.text, track: track) }) {
                    result["first_vocal_candidate_seconds"] = vocal.time
                }
                result["timing_evidence"] = "Source LRC timestamps only; vocal candidate excludes common credits and has not been aurally verified."
            }
            emit(result)
        } catch {
            var result: [String: Any] = ["network_requested": true, "status": "lookup_failed",
                                        "tested_at": ISO8601DateFormatter().string(from: Date())]
            switch error {
            case NetEaseLyricsError.response(let code): result["error_type"] = "http"; result["error_code"] = code
            case NetEaseLyricsError.service(let code): result["error_type"] = "service"; result["error_code"] = code
            case NetEaseLyricsError.oversizedResponse: result["error_type"] = "oversized_response"
            case NetEaseLyricsError.rateLimited: result["error_type"] = "rate_limited"
            case NetEaseLyricsError.insecureRedirect: result["error_type"] = "insecure_redirect"
            case let error as URLError: result["error_type"] = "network"; result["error_code"] = error.code.rawValue
            case is CancellationError: result["error_type"] = "cancelled"
            case is DecodingError: result["error_type"] = "decoding"
            default: result["error_type"] = "unknown"
            }
            emit(result)
            exit(1)
        }
    }

    private static func isCredit(_ line: String, track: LyricsTrack) -> Bool {
        let normalized = LyricsTrack.normalized(line)
        if normalized == LyricsTrack.normalized(track.title) || normalized == LyricsTrack.normalized(track.title + " - " + track.artist) { return true }
        return normalized.range(of: "(?i)(?:作词|作曲|编曲|制作|producer|composer|lyricist|arrang|曲\\s*[:：]|词\\s*[:：])", options: .regularExpression) != nil
    }

    private static func emit(_ result: [String: Any]) {
        let data = try! JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
