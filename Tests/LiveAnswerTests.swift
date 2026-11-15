import XCTest

final class LiveAnswerTests: XCTestCase {
    func testAnAnswerKeepsItsReplyAndDropsMarksThatPointAtNothing() throws {
        let answer = try LiveAnswer(json: [
            "say": "  The total is wrong.  ",
            "marks": [
                ["kind": "circle", "line": "t3", "words": "$197.85", "label": "Should be $194.24"],
                ["kind": "arrow", "box": [0.5, 0.75, 0.8, 0.5]],
                ["kind": "arrow"],
                ["kind": "underline", "line": "t1"],
            ],
        ])
        XCTAssertEqual(answer.say, "The total is wrong.")
        XCTAssertEqual(answer.marks, [
            AnswerMark(kind: .circle, line: "t3", words: "$197.85", label: "Should be $194.24"),
            AnswerMark(kind: .arrow, box: CGRect(x: 0.5, y: 0.75, width: 0.5, height: 0.25)),
        ], "a box is cut to the picture; a mark with no target or an unknown kind is dropped")
        XCTAssertEqual(try LiveAnswer(responder: ["say": "Here.", "marks": [["kind": "arrow", "box": [500, 750, 800, 500]]]]).marks,
                       [AnswerMark(kind: .arrow, box: CGRect(x: 0.5, y: 0.75, width: 0.5, height: 0.25))],
                       "the responder's boxes are in thousandths, as its schema asks")
        XCTAssertFalse(answer.steps)
        XCTAssertTrue(try LiveAnswer(json: ["say": "Two clicks.", "marks": [], "steps": true]).steps)
        XCTAssertThrowsError(try LiveAnswer(json: ["say": " ", "marks": []]))
        XCTAssertThrowsError(try LiveAnswer(json: ["marks": []]))
    }

    func testTheStrictSchemaRequiresEveryPropertyAndLetsOnlyTheOptionalOnesBeNull() throws {
        func object(_ text: String) throws -> [String: Any] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        }
        func check(plain: [String: Any], strict: [String: Any], at path: String) throws {
            let properties = try XCTUnwrap(strict["properties"] as? [String: [String: Any]], path)
            let plainProperties = try XCTUnwrap(plain["properties"] as? [String: [String: Any]], path)
            XCTAssertEqual(Set(properties.keys), Set(plainProperties.keys), path)
            XCTAssertEqual(Set(try XCTUnwrap(strict["required"] as? [String], path)), Set(properties.keys), "\(path): strict mode requires every key")
            let optional = Set(plainProperties.keys).subtracting(try XCTUnwrap(plain["required"] as? [String], path))
            for (key, field) in properties {
                let types = (field["type"] as? [String]) ?? [field["type"] as? String].compactMap { $0 }
                XCTAssertEqual(types.contains("null"), optional.contains(key), "\(path).\(key): only an optional field may be null")
                XCTAssertEqual(types.filter { $0 != "null" }, [plainProperties[key]?["type"] as? String].compactMap { $0 }, "\(path).\(key)")
                var bare = field, plainBare = try XCTUnwrap(plainProperties[key])
                bare["type"] = nil
                plainBare["type"] = nil
                if let items = field["items"] as? [String: Any], items["properties"] != nil {
                    try check(plain: try XCTUnwrap(plainBare["items"] as? [String: Any]), strict: items, at: "\(path).\(key)")
                    bare["items"] = nil
                    plainBare["items"] = nil
                }
                XCTAssertEqual(bare as NSDictionary, plainBare as NSDictionary, "\(path).\(key): only the type changes")
            }
        }
        try check(plain: try object(LiveAnswer.schema), strict: try object(LiveAnswer.strictSchema), at: "answer")
    }

    func testTheResponderReadsANullFieldAsAbsent() throws {
        let null = NSNull()
        let answer = try LiveAnswer(responder: [
            "say": "Here.", "steps": null, "actions": null,
            "marks": [["kind": "circle", "line": "t2", "words": null, "box": null, "label": null, "zoom": null],
                      ["kind": "arrow", "line": null, "words": null, "box": [500, 750, 800, 500], "label": "This one", "zoom": null]],
        ])
        XCTAssertEqual(answer, LiveAnswer(say: "Here.", marks: [
            AnswerMark(kind: .circle, line: "t2"),
            AnswerMark(kind: .arrow, box: CGRect(x: 0.5, y: 0.75, width: 0.5, height: 0.25), label: "This one"),
        ]))
        XCTAssertEqual(try LiveAnswer(responder: ["say": "Nothing to mark.", "marks": null]), LiveAnswer(say: "Nothing to mark."))
    }

    func testTheReplyHelperRefusesAMarkItWouldDropAndNamesIt() throws {
        let good: [String: Any] = ["kind": "circle", "words": "$72k", "box": [0.25, 0.5, 0.125, 0.0625]]
        let kept = try LiveAnswer(json: ["say": "Here.", "marks": [good]], strict: true)
        XCTAssertEqual(kept.marks, [AnswerMark(kind: .circle, words: "$72k", box: CGRect(x: 0.25, y: 0.5, width: 0.125, height: 0.0625))],
                       "words and a box together are kept, so the box can stand in when the words are not found")
        let refused: [(Any, String)] = [
            ([good, ["kind": "underline", "words": "Total"]], "mark 2"),
            ([good, good, ["kind": "arrow", "box": [1.2, 0.5, 0.1, 0.1]]], "mark 3"),
            ([["kind": "arrow"]], "mark 1"),
            (Array(repeating: good, count: LiveAnswer.maxMarks + 1), "at most"),
        ]
        for (marks, named) in refused {
            XCTAssertThrowsError(try LiveAnswer(json: ["say": "Here.", "marks": marks], strict: true)) { error in
                XCTAssertTrue("\(error)".contains(named), "\(error)")
            }
            XCTAssertNoThrow(try LiveAnswer(json: ["say": "Here.", "marks": marks]), "the responder's answer still drops them and is shown")
        }
    }

    func testOnlyAFocusZoomsAndItSurvivesTheReplysBundle() throws {
        let answer = try LiveAnswer(json: ["say": "Look here.", "marks": [["kind": "focus", "words": "1 px", "zoom": true],
                                                                          ["kind": "circle", "words": "Share", "zoom": true]]])
        XCTAssertEqual(answer.marks.map(\.zoom), [true, false], "a circle has nothing to magnify")
        let again = try JSONDecoder().decode(LiveAnswer.self, from: JSONEncoder().encode(answer))
        XCTAssertEqual(again.marks, answer.marks)
    }

    func testTheReplyStreamsInAsTheAnswersJSONArrives() throws {
        // `say` streams in ahead of the marks only when the schema lists it first.
        for schema in [LiveAnswer.schema, LiveAnswer.strictSchema] {
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(schema.utf8)))
            let fields = schema[try XCTUnwrap(schema.range(of: #""properties""#)).upperBound...]
            XCTAssertLessThan(try XCTUnwrap(fields.range(of: #""say""#)).lowerBound, try XCTUnwrap(fields.range(of: #""marks""#)).lowerBound)
        }
        let pieces = ["{\"say\": \"The", " total", " is \\\"$197", ".85\\\"\\nnot", " $194\\u00b7", "\", \"marks\": []}"]
        var json = "", seen: [String] = []
        XCTAssertNil(LiveAnswer.partialSay(in: "{\"say\": \""))
        for piece in pieces {
            json += piece
            if let say = LiveAnswer.partialSay(in: json), say != seen.last { seen.append(say) }
        }
        XCTAssertEqual(seen, ["The", "The total", "The total is \"$197", "The total is \"$197.85\"\nnot", "The total is \"$197.85\"\nnot $194·"])

        let three = "The row has no padding. Its field sits on the line, e.g. under 1.5 rows. Give it the rows' padding."
        let four = three + " Or check its margin."
        XCTAssertEqual(LiveAnswer.partialSay(in: "{\"say\": \"" + three + " Or ch"), three, "a fourth sentence never shows as it streams")
        XCTAssertEqual(try LiveAnswer(responder: ["say": four, "marks": []]).say, three, "the answer ends where its streamed reply stopped")
        XCTAssertEqual(try LiveAnswer(json: ["say": four, "marks": []]).say, four, "a session's answer keeps every sentence")
    }
}
