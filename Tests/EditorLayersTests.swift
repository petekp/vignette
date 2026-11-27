import AppKit
import XCTest

@MainActor
final class EditorLayersTests: XCTestCase {
    func testTheEditorsMarksKeepItsPinsForAFlightWithoutDrawingThem() throws {
        let pixels = PixelSize(width: 1000, height: 600)
        let pin = Pin(id: UUID(), number: 1, place: .point(CGPoint(x: 500, y: 300)), comments: [Pin.Comment(text: "Here")])
        let drawing = Drawing(key: "/tmp/Screenshot test.png", pixels: pixels, pointScale: 1, marks: [], pins: [pin])
        let picture = EditorPicture()
        picture.open(nil, pixels: pixels)
        let geometry = EditorGeometry(pixels: pixels, pointScale: 1, style: .standard, metrics: .standard, zoom: 1, layouts: TextLayoutCache(),
                                      markStyle: .standard)
        picture.show(drawing, typing: nil, covered: nil, geometry: geometry,
                     resolution: EditorPicture.Resolution(scale: 2, visible: pixels.bounds, pixels: 2_400_000, fit: 2, moving: false), gesture: false)

        let shown = try XCTUnwrap(picture.marks.drawing)
        XCTAssertEqual(shown.pins.map(\.id), [pin.id])
        XCTAssertEqual(picture.marks.layer.sublayers ?? [], [], "the editor draws its pins itself")
        let flight = MarkLayers(pixels: pixels, queue: MarkLayers.textQueue)
        flight.show(shown, scale: 2, bound: pixels.bounds, style: .standard, markStyle: .standard, adopting: [picture.marks])
        XCTAssertEqual(flight.layer.sublayers?.count, 1, "a flight made from the editor's marks draws the pin")
    }
}
