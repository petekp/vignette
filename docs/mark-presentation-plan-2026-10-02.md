# Mark presentation

`MarkLayers` should own its bitmap selection and visibility. The editor should pass the drawing and the presentation it needs. Today `EditorPicture` receives mutable `MarkLayers.Text` records and changes desired bitmaps, pending detail, layer visibility, and clearing. That makes the editor depend on the text-cache implementation.

Replace the mutable planning closure with an immutable presentation value. Keep the existing queues, renderer, adoption cache, and stale-work checks.

Use two cases:

```swift
enum Presentation {
    case whole(scale: CGFloat, region: CGRect)
    case viewport(Viewport)
}
```

The viewport carries resolution, visible image region, fitted resolution, bitmap-pixel budget, zoom motion, and gesture state. It separately names the note being typed, the note covered until a current bitmap arrives, and the note hidden while its typing view settles. These are distinct behaviors in the existing editor.

`show` accepts the drawing, styles, presentation, and optional adopted marks. `MarkLayers` calculates layouts internally. It preserves unbalanced line breaks while typing and balanced line breaks after typing. Its private planner reads cache state and chooses whole and detail targets, resolution reuse, and visibility. `Text` becomes private. Preserve the existing layout cache inside this owner so each refresh does not remeasure every note. Keep mutable cache state confined to its actor or queue.

Keep `onTextDrawn`, `isDrawn`, `bitmapPixels`, `park`, and `clear`. Preserve late `adopt(from:)` after image readiness and `restyle` for marks already shown in cards and flights. They report production presentation outcomes. Keep the editor and flight queue separate from card work, so card rasterization cannot delay the note being edited.

The implementation must preserve these contracts:

- Cards and flights can adopt the fitted editor bitmap.
- Moving zooms keep their resolution until rest.
- Moving a note can slide its bitmap when its line breaks remain the same.
- Offscreen notes use fitted resolution.
- Each note retains at most two bounded bitmaps, including work awaiting display.
- The typing view stays until the replacement bitmap can appear in the same transaction.
- Parked or replaced records cannot display stale work. Style changes require matching styles before reuse.

The current editor and card pixel tests cover adoption, stale work, typing continuity, and card bitmap bounds. Keep them through the new interface. Offscreen viewport downgrade and the editor bitmap limit during replacement need additional observable verification. Avoid tests that reproduce the private target-selection algorithm. Native verification covers typing settlement, zoom and pan, live restyling, flight adoption, reversal, and a lone-card return. Record frame continuity where a still image cannot prove it.

Implement this after pending-drawing ownership is settled. That work may change the handover boundary, but presentation must continue to own parked layers. Keeping those decisions separate prevents storage state from becoming another bitmap-cache input.

State: interface plan ready. App behavior and the mutable planning API are unchanged.
