import AppKit

extension EditorView {
    func join(_ marks: [Mark], pins: [AgentPin] = [], from agent: String? = nil, at: Date = Date()) -> Drawing? {
        handOver(.agentMarks(marks, pins: pins, from: agent, at: at))
    }
}
