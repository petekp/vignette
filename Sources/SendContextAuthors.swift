import Foundation
import ImageIO
import Vision

/// The Claude Code sessions whose edited files hold the text in a picture: the candidates for the
/// session a drawing is about, which can differ from the session the window shows
/// (docs/session-detection-exploration-2026-10-08.md, Result 9). Only ids and scores leave here,
/// never the text.
extension SendContext {
    struct AuthorLimits {
        /// Bytes per file. A bigger file is skipped.
        var maxFile = 1_000_000
        /// Bytes read in all, per record.
        var maxTotal = 50_000_000
        /// A file-history folder changed this recently makes its session a candidate.
        var recent: TimeInterval = 12 * 3600
        var top = 5
    }

    /// Vision's reading as Result 9 made it: accurate, without language correction, every
    /// observation's top candidate, with no confidence floor.
    static func recognisedLines(_ image: CGImage) -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        // Live ink's own Vision reads can run at the same moment; this asks Vision to spend less here.
        request.preferBackgroundProcessing = true
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }

    /// The screenshot decoded no larger than the largest screen, upright.
    static func decoded(_ file: URL, maxPixels: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
        var options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true]
        if maxPixels > 0 { options[kCGImageSourceThumbnailMaxPixelSize] = maxPixels }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// A line's words: lowercased, runs of ASCII letters and digits.
    private static func phraseWords(_ line: String) -> [String] {
        var words: [String] = [], word = ""
        for scalar in line.lowercased().unicodeScalars {
            switch scalar.value {
            case 0x61...0x7A, 0x30...0x39: word.unicodeScalars.append(scalar)
            default:
                guard !word.isEmpty else { continue }
                words.append(word)
                word = ""
            }
        }
        if !word.isEmpty { words.append(word) }
        return words
    }

    /// What is searched for a line: the whole line from 6 characters, runs of two words from 10 and
    /// of three from 12, its words joined by single spaces. A line cut off with an ellipsis loses its
    /// last word, which may be partial.
    static func phrases(ofLine line: String) -> Set<String> {
        var words = phraseWords(line)
        var end = Substring(line)
        while let last = end.last, last.isWhitespace { end.removeLast() }
        if end.hasSuffix("…") || end.hasSuffix("...") { words.removeLast(min(1, words.count)) }
        var out = Set<String>()
        let whole = words.joined(separator: " ")
        if whole.count >= 6 { out.insert(whole) }
        for (size, least) in [(2, 10), (3, 12)] where words.count >= size {
            for start in 0...(words.count - size) {
                let run = words[start..<(start + size)].joined(separator: " ")
                if run.count >= least { out.insert(run) }
            }
        }
        return out
    }

    /// Phrases indexed by their first word's hash, so a search allocates nothing per word.
    struct PhraseIndex {
        let phrases: [String]
        let words: [[[UInt8]]]
        let byFirst: [UInt64: [Int]]
        /// A bit per first word's hash, checked before the dictionary.
        let filter: [UInt64]

        init(_ set: Set<String>) {
            phrases = Array(set)
            words = phrases.map { $0.split(separator: " ").map { Array($0.utf8) } }
            var byFirst: [UInt64: [Int]] = [:]
            var filter = [UInt64](repeating: 0, count: 1024)
            for (index, phrase) in words.enumerated() {
                guard let first = phrase.first else { continue }
                let hash = first.reduce(Self.basis) { Self.mix($0, $1) }
                byFirst[hash, default: []].append(index)
                filter[Int((hash >> 6) & 1023)] |= 1 << (hash & 63)
            }
            self.byFirst = byFirst
            self.filter = filter
        }

        // FNV-1a, 64 bit.
        static let basis: UInt64 = 0xcbf2_9ce4_8422_2325
        static func mix(_ hash: UInt64, _ byte: UInt8) -> UInt64 { (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }

        static func isWord(_ byte: UInt8) -> Bool {
            (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)
        }

        static func lower(_ byte: UInt8) -> UInt8 { byte >= 0x41 && byte <= 0x5A ? byte | 0x20 : byte }

        /// The phrases `text` holds: their words in order, in any case, each pair apart by 1 to 8
        /// characters that are not ASCII letters or digits and not a line break, and the whole touching
        /// no ASCII letter, digit or `_` at either end. Two differences from Result 9's `rg -o`: a
        /// non-ASCII letter at an end does not stop a match, and overlapping phrases are all found.
        func held(in text: Data) -> Set<String> {
            var found = [Bool](repeating: false, count: phrases.count)
            var left = words.filter { !$0.isEmpty }.count
            guard left > 0 else { return [] }
            text.withUnsafeBytes { raw in
                let bytes = raw.bindMemory(to: UInt8.self)
                let count = bytes.count
                var i = 0
                while i < count, left > 0 {
                    guard Self.isWord(bytes[i]) else { i += 1; continue }
                    let start = i
                    var hash = Self.basis
                    while i < count, Self.isWord(bytes[i]) {
                        hash = Self.mix(hash, Self.lower(bytes[i]))
                        i += 1
                    }
                    guard start == 0 || bytes[start - 1] != UInt8(ascii: "_"),
                          filter[Int((hash >> 6) & 1023)] & (1 << (hash & 63)) != 0,
                          let candidates = byFirst[hash] else { continue }
                    for index in candidates where !found[index] && matches(words[index], bytes, start: start, end: i) {
                        found[index] = true
                        left -= 1
                    }
                }
            }
            return Set(phrases.indices.filter { found[$0] }.map { phrases[$0] })
        }

        /// Whether `phrase` starts at the word `start..<end`.
        private func matches(_ phrase: [[UInt8]], _ bytes: UnsafeBufferPointer<UInt8>, start: Int, end: Int) -> Bool {
            let count = bytes.count
            func same(_ word: [UInt8], from: Int, to: Int) -> Bool {
                guard to - from == word.count else { return false }
                for k in 0..<word.count where Self.lower(bytes[from + k]) != word[k] { return false }
                return true
            }
            guard same(phrase[0], from: start, to: end) else { return false }
            var position = end
            for word in phrase.dropFirst() {
                // The gap, counted in Unicode scalars: every byte but a UTF-8 continuation byte.
                var j = position, scalars = 0
                while j < count, !Self.isWord(bytes[j]) {
                    if bytes[j] == UInt8(ascii: "\n") { return false }
                    if bytes[j] & 0xC0 != 0x80 { scalars += 1 }
                    if scalars > 8 { return false }
                    j += 1
                }
                guard j < count, scalars >= 1 else { return false }
                let wordStart = j
                while j < count, Self.isWord(bytes[j]) { j += 1 }
                guard same(word, from: wordStart, to: j) else { return false }
                position = j
            }
            return position == count || bytes[position] != UInt8(ascii: "_")
        }
    }

    /// Each candidate's files to read, newest first. A file over `maxFile` is skipped. When the rest
    /// come to more than `maxTotal`, the budget is shared max-min fairly: a candidate needing less
    /// than an even share reads everything, and what it leaves goes to the others.
    static func readPlan(_ files: [(id: String, files: [(url: URL, size: Int, modified: Date)])],
                         maxFile: Int, maxTotal: Int) -> (reads: [String: [URL]], capped: Bool) {
        var capped = false
        let kept = files.map { candidate in
            let small = candidate.files.filter { $0.size <= maxFile }
            if small.count < candidate.files.count { capped = true }
            return (id: candidate.id, files: small.sorted { $0.modified > $1.modified })
        }
        let sizes = kept.map { $0.files.reduce(0) { $0 + $1.size } }
        guard sizes.reduce(0, +) > maxTotal else {
            return (Dictionary(kept.map { ($0.id, $0.files.map(\.url)) }) { $0 + $1 }, capped)
        }
        // A first-come stop would starve the sessions found only by their recent file-history, as
        // Result 9's author was.
        var share = [Int](repeating: 0, count: kept.count)
        var open = Set(kept.indices.filter { sizes[$0] > 0 })
        var left = maxTotal
        while !open.isEmpty {
            let even = left / open.count
            let satisfied = open.filter { sizes[$0] <= even }
            guard !satisfied.isEmpty else {
                for index in open { share[index] = even }
                break
            }
            for index in satisfied {
                share[index] = sizes[index]
                left -= sizes[index]
            }
            open.subtract(satisfied)
        }
        var reads: [String: [URL]] = [:]
        for (index, candidate) in kept.enumerated() {
            var used = 0
            var urls: [URL] = []
            for file in candidate.files {
                guard used + file.size <= share[index] else { break }
                used += file.size
                urls.append(file.url)
            }
            reads[candidate.id, default: []] += urls
        }
        return (reads, true)
    }

    /// Each session's score: over the lines it holds any phrase of, 1 divided by the number of
    /// sessions holding that line. Sessions scoring 0 are left out; ties go by id.
    static func rank(lines: [Set<String>], held: [String: Set<String>], top: Int = 5) -> [(id: String, score: Double)] {
        var scores: [String: Double] = [:]
        for phrases in lines where !phrases.isEmpty {
            let holders = held.filter { !$0.value.isDisjoint(with: phrases) }.map(\.key)
            for id in holders { scores[id, default: 0] += 1 / Double(holders.count) }
        }
        return scores
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(top).map { (id: $0.key, score: $0.value) }
    }

    /// The listed sessions in the order given, then the sessions whose `<fileHistory>/<id>` folder
    /// changed within `recent` of `now`, newest first. Codex threads keep no file-history.
    static func authorCandidates(listed: [String], fileHistory: URL, now: Date, recent: TimeInterval) -> [String] {
        var seen = Set<String>()
        var out = listed.filter { UUID(uuidString: $0) != nil && seen.insert($0).inserted }
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey]
        let folders = (try? FileManager.default.contentsOfDirectory(at: fileHistory, includingPropertiesForKeys: Array(keys))) ?? []
        let changed = folders.compactMap { folder -> (id: String, date: Date)? in
            guard UUID(uuidString: folder.lastPathComponent) != nil, let values = try? folder.resourceValues(forKeys: keys),
                  values.isDirectory == true, let date = values.contentModificationDate,
                  now.timeIntervalSince(date) <= recent else { return nil }
            return (folder.lastPathComponent, date)
        }
        for folder in changed.sorted(by: { $0.date > $1.date }) where seen.insert(folder.id).inserted { out.append(folder.id) }
        return out
    }

    /// Claude Code's folder as the rest of the app finds it, so a test launch never gets the
    /// person's own (`AgentPlugin.roots`).
    static func claudeRoot(home: URL = URL(fileURLWithPath: NSHomeDirectory()),
                           environment: [String: String] = ProcessInfo.processInfo.environment,
                           personHome: URL = AgentPlugin.personHome) -> URL? {
        AgentPlugin.roots(home: home, environment: environment, personHome: personHome)
            .first { AgentPlugin.client(of: $0, environment: environment) == .claude }
    }

    /// `authors`, the top sessions by score; `authorLines`, the lines long enough to search; and
    /// `authorCapped` when a limit left files unread.
    static func authorFields(lines: [String], listed: [String], claudeRoot: URL, now: Date, limits: AuthorLimits) -> [String: Any] {
        let searched = lines.map(phrases(ofLine:)).filter { !$0.isEmpty }
        guard !searched.isEmpty else { return ["authors": [Any](), "authorLines": 0] }
        let index = PhraseIndex(searched.reduce(into: Set<String>()) { $0.formUnion($1) })
        let fileHistory = claudeRoot.appendingPathComponent("file-history")
        let candidates = authorCandidates(listed: listed, fileHistory: fileHistory, now: now, recent: limits.recent)
        let plan = readPlan(candidates.map { (id: $0, files: files(in: fileHistory.appendingPathComponent($0))) },
                            maxFile: limits.maxFile, maxTotal: limits.maxTotal)
        var holds: [String: Set<String>] = [:]
        for id in candidates {
            var found = Set<String>()
            for file in plan.reads[id] ?? [] {
                guard let data = try? Data(contentsOf: file) else { continue }
                found.formUnion(index.held(in: data))
                if found.count == index.phrases.count { break }
            }
            holds[id] = found
        }
        let authors = rank(lines: searched, held: holds, top: limits.top).map { author -> [String: Any] in
            // As a decimal, since JSONSerialization writes the Double 1.38 as 1.3799999999999999.
            ["id": author.id,
             "score": NSDecimalNumber(mantissa: UInt64((author.score * 100).rounded()), exponent: -2, isNegative: false)]
        }
        var out: [String: Any] = ["authors": authors, "authorLines": searched.count]
        if plan.capped { out["authorCapped"] = true }
        return out
    }

    /// The regular files under a session's file-history folder. Links are not followed.
    private static func files(in folder: URL) -> [(url: URL, size: Int, modified: Date)] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        guard let walk = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else { return [] }
        var out: [(url: URL, size: Int, modified: Date)] = []
        for case let file as URL in walk {
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isSymbolicLink != true,
                  values.isRegularFile == true else { continue }
            out.append((file, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast))
        }
        return out
    }
}
