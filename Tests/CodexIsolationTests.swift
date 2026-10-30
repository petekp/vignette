import XCTest

final class CodexIsolationTests: XCTestCase {
    private let prompt = "VIGNETTE-SYSTEM-MARKER"
    private let warmUp = #"Vignette is starting you up. Answer with say "Ready." and no marks."#

    private func message(_ role: String, _ text: String) -> [String: Any] {
        ["type": "message", "role": role, "content": [["type": "input_text", "text": text]]]
    }

    private func request(tools: [Any] = [], input: [[String: Any]]? = nil, instructions: Any? = nil) -> Data {
        var body: [String: Any] = [
            "model": "gpt-6-astra", "stream": true, "tools": tools, "tool_choice": "auto", "parallel_tool_calls": true,
            "reasoning": ["effort": "low"], "store": false, "include": ["reasoning.encrypted_content"],
            "prompt_cache_key": "01a18b87-2130-7c91-9f8a-b41c9dbc12a5",
            "text": ["verbosity": "low", "format": ["type": "json_schema", "strict": true, "schema": ["type": "object"]]],
            "client_metadata": ["session_id": "01a18b87-2130-7c91-9f8a-b41c9dbc12a5"],
            "input": input ?? [message("developer", prompt), message("user", warmUp)],
        ]
        if let instructions { body["instructions"] = instructions }
        return try! JSONSerialization.data(withJSONObject: body)
    }

    private func refusal(_ body: Data) -> String? {
        CodexIsolation.refusal(of: body, prompt: prompt, warmUp: warmUp)
    }

    func testTheRequestCodex0165SendsWithTheSwitchesHoldsOnlyThePromptAndTheWarmUp() {
        XCTAssertNil(refusal(request()))
        XCTAssertNil(refusal(request(instructions: "")))
        XCTAssertNil(refusal(request(instructions: prompt)))
    }

    func testAnythingElseInTheRequestRefusesTheResponder() {
        XCTAssertEqual(refusal(request(tools: [["type": "function", "name": "exec_command"]])), "tools=1")
        XCTAssertEqual(refusal(request(instructions: "You are Codex.")), "instructions of its own")
        XCTAssertEqual(refusal(request(input: [message("developer", prompt), message("user", "# AGENTS.md instructions"), message("user", warmUp)])),
                       "a user message of its own")
        XCTAssertEqual(refusal(request(input: [message("developer", prompt), message("developer", "<permissions instructions>"), message("user", warmUp)])),
                       "a developer message of its own")
        XCTAssertEqual(refusal(request(input: [message("developer", prompt), ["type": "additional_tools", "tools": [["name": "exec"]]], message("user", warmUp)])),
                       "an input item additional_tools")
        XCTAssertEqual(refusal(request(input: [message("developer", prompt),
                                               ["type": "message", "role": "user", "content": [["type": "input_image", "image_url": "data:"]]]])),
                       "an input part that is not text")
        XCTAssertEqual(refusal(request(input: [message("developer", prompt), message("user", warmUp), message("user", warmUp)])), "2 user messages")
        XCTAssertEqual(refusal(request(input: [message("developer", prompt)])), "0 user messages")
        XCTAssertEqual(refusal(Data("{\"tools\":".utf8)), "a request that is not JSON")
    }

    func testTheCatalogKeepsEachModelAndTakesOutWhatAddsTools() throws {
        let catalog = #"{"models":[{"slug":"gpt-6-astra","display_name":"GPT-6-Astra","apply_patch_tool_type":"freeform","tool_mode":"code_mode_only","multi_agent_version":"v2","experimental_supported_tools":["exec"],"use_responses_lite":true,"context_window":258400},{"slug":"gpt-5.5"}]}"#
        let stripped = try XCTUnwrap(CodexIsolation.strippedCatalog(Data(catalog.utf8)))
        let models = try XCTUnwrap((JSONSerialization.jsonObject(with: stripped) as? [String: Any])?["models"] as? [[String: Any]])
        XCTAssertEqual(models.map { $0["slug"] as? String }, ["gpt-6-astra", "gpt-5.5"])
        for model in models {
            XCTAssertTrue(model["apply_patch_tool_type"] is NSNull)
            XCTAssertTrue(model["tool_mode"] is NSNull)
            XCTAssertEqual(model["multi_agent_version"] as? String, "disabled")
            XCTAssertEqual((model["experimental_supported_tools"] as? [Any])?.count, 0)
            XCTAssertEqual(model["use_responses_lite"] as? Bool, false)
        }
        XCTAssertEqual(models[0]["context_window"] as? Int, 258400)
        XCTAssertNil(CodexIsolation.strippedCatalog(Data(#"{"models":[]}"#.utf8)))
        XCTAssertNil(CodexIsolation.strippedCatalog(Data("Error: not signed in".utf8)))
    }

    func testTheCheckProviderKeepsWhatIsPostedToItAndAnswersReady() async throws {
        let provider = try CodexCheckProvider()
        defer { provider.stop() }
        let port: UInt16? = await withCheckedContinuation { continuation in provider.start { continuation.resume(returning: $0) } }
        let listening = try XCTUnwrap(port)
        var post = URLRequest(url: URL(string: "http://127.0.0.1:\(listening)/v1/responses")!)
        post.httpMethod = "POST"
        post.setValue("application/json", forHTTPHeaderField: "content-type")
        let body = request()
        post.httpBody = body
        let (stream, response) = try await URLSession.shared.data(for: post)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let events = String(decoding: stream, as: UTF8.self)
        XCTAssertTrue(events.contains("event: response.completed"))
        XCTAssertTrue(events.contains(#"Ready."#))
        XCTAssertEqual(provider.requests, [body])
    }

    func testARequestIsWholeOnceItsBodyHasArrivedByLengthOrByChunks() throws {
        let head = "POST /v1/responses HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 11\r\n\r\n"
        XCTAssertNil(HTTPRequest(Data((head + "hello").utf8)))
        XCTAssertEqual(HTTPRequest(Data((head + "hello world").utf8))?.body, Data("hello world".utf8))
        let chunked = "POST / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n6\r\n world\r\n"
        XCTAssertNil(HTTPRequest(Data(chunked.utf8)))
        XCTAssertEqual(HTTPRequest(Data((chunked + "0\r\n\r\n").utf8))?.body, Data("hello world".utf8))
        XCTAssertEqual(HTTPRequest(Data("GET /v1/models HTTP/1.1\r\n\r\n".utf8))?.method, "GET")
    }
}
