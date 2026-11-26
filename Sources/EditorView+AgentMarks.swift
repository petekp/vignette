import AppKit

extension EditorView {
    func join(_ marks: [Mark]) -> Drawing? {
        handOver(.agentMarks(marks))
    }

    func takeBackAgentMarks() -> (taken: TakenBackMarks, drawing: Drawing)? {
        guard let step = core.newestAgentMarks else { return nil }
        let taken = TakenBackMarks(step: step, redo: core.redoSteps)
        return handOver(.takeBackAgentMarks).map { (taken, $0) }
    }

    func putBackAgentMarks(_ taken: TakenBackMarks) -> Drawing? {
        handOver(.putBackAgentMarks(taken))
    }
}
