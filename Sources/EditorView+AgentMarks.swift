import AppKit

extension EditorView {
    func join(_ marks: [Mark], pins: [AgentPin] = [], by author: AgentAuthor = AgentAuthor()) -> Drawing? {
        handOver(.agentMarks(marks, pins: pins, by: author))
    }

    func name(_ sender: String, of session: AgentAddress) -> Drawing? {
        handOver(.sessionNamed(sender, of: session))
    }
}
