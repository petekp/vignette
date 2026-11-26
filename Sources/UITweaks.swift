import Foundation

/// Layout, styling, timing, and backdrop parameters. All in points and seconds. In settings.json they
/// are one flat `ui` object. Here each area's tweaks are a group, in the file named as the area's
/// `TweakCatalog` file is, and a tweak reads as `ui.cardMaxWidth` whichever group holds it.
@dynamicMemberLookup
struct UITweaks: Equatable {
    var stack = Stack()
    var labs = Labs()
    var annotator = Annotator()
    var editor = Editor()
    var liveInk = LiveInk()

    subscript<T>(dynamicMember path: WritableKeyPath<Stack, T>) -> T {
        get { stack[keyPath: path] }
        set { stack[keyPath: path] = newValue }
    }
    subscript<T>(dynamicMember path: WritableKeyPath<Labs, T>) -> T {
        get { labs[keyPath: path] }
        set { labs[keyPath: path] = newValue }
    }
    subscript<T>(dynamicMember path: WritableKeyPath<Annotator, T>) -> T {
        get { annotator[keyPath: path] }
        set { annotator[keyPath: path] = newValue }
    }
    subscript<T>(dynamicMember path: WritableKeyPath<Editor, T>) -> T {
        get { editor[keyPath: path] }
        set { editor[keyPath: path] = newValue }
    }
    subscript<T>(dynamicMember path: WritableKeyPath<LiveInk, T>) -> T {
        get { liveInk[keyPath: path] }
        set { liveInk[keyPath: path] = newValue }
    }
}
