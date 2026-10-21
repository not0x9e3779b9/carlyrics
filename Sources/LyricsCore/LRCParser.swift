import Foundation

public struct LRCParser: Sendable {
    public init() {}

    /// Invalid lines are reported and skipped. Empty timed lines deliberately mark instrumental gaps.
    /// A positive file offset adds milliseconds to all timestamps; negative results clamp to zero.
    public func parse(_ input: String) -> LyricsDocument {
        var metadata = LyricsMetadata()
        var entries: [(timestamp: TimeInterval, text: String)] = []
        var warnings: [LRCWarning] = []
        let source = input.replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        for (lineIndex, original) in source.components(separatedBy: "\n").enumerated() {
            let raw = original.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { continue }
            var remaining = raw[...]
            var timestamps: [TimeInterval] = []
            var recognizedMetadata = false
            var invalidToken = false

            while remaining.first == "[" {
                guard let end = remaining.firstIndex(of: "]") else {
                    invalidToken = true
                    break
                }
                let start = remaining.index(after: remaining.startIndex)
                let token = String(remaining[start..<end]).trimmingCharacters(in: .whitespaces)
                remaining = remaining[remaining.index(after: end)...]
                if let timestamp = Self.timestamp(token) {
                    timestamps.append(timestamp)
                } else if let colon = token.firstIndex(of: ":"),
                          token.first?.isNumber != true {
                    let key = token[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                    let value = token[token.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                    recognizedMetadata = true
                    switch key {
                    case "ti": metadata.title = value
                    case "ar": metadata.artist = value
                    case "al": metadata.album = value
                    case "by": metadata.author = value
                    case "offset":
                        if let offset = Int(value) {
                            metadata.offsetMilliseconds = offset
                        } else {
                            invalidToken = true
                        }
                    default: metadata.additional[key] = value
                    }
                } else {
                    invalidToken = true
                }
                remaining = remaining.drop(while: { $0.isWhitespace })
            }

            if invalidToken {
                warnings.append(.init(lineNumber: lineIndex + 1, message: "Ignored a malformed LRC tag."))
            }
            if !timestamps.isEmpty {
                let text = remaining.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
                for timestamp in timestamps { entries.append((timestamp, text)) }
            } else if !recognizedMetadata && !invalidToken {
                warnings.append(.init(lineNumber: lineIndex + 1, message: "Ignored a line without a timestamp."))
            }
        }

        let offset = Double(metadata.offsetMilliseconds) / 1_000
        return LyricsDocument(
            lines: entries.map { .init(timestamp: max(0, $0.timestamp + offset), text: $0.text) },
            metadata: metadata,
            warnings: warnings
        )
    }

    private static func timestamp(_ token: String) -> TimeInterval? {
        let parts = token.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty,
              parts[0].allSatisfy({ $0.isASCII && $0.isNumber }),
              let minutes = Double(parts[0]), minutes.isFinite else { return nil }
        let secondsParts = parts[1].split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(secondsParts.count), !secondsParts[0].isEmpty,
              secondsParts[0].allSatisfy({ $0.isASCII && $0.isNumber }),
              let seconds = Double(secondsParts[0]), seconds < 60 else { return nil }
        var fraction: Double = 0
        if secondsParts.count == 2 {
            let digits = secondsParts[1]
            guard (1...3).contains(digits.count), digits.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let value = Double(digits) else { return nil }
            fraction = value / pow(10, Double(digits.count))
        }
        let result = minutes * 60 + seconds + fraction
        return result.isFinite ? result : nil
    }
}
