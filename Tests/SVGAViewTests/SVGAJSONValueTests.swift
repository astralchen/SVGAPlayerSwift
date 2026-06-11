import Foundation
import Testing
import UIKit
@testable import SVGAView

@Test
func jsonValueDecodesNestedObjectsWithTypedAccessors() throws {
    let data = """
    {
      "type": "rect",
      "args": { "x": 12.5, "y": 8, "width": 40, "height": 20 },
      "styles": { "fill": [1, 0.5, 0, 1], "lineDash": [2, 3, 4] },
      "hidden": false
    }
    """.data(using: .utf8)!

    let jsonObject = try JSONDecoder().decode(SVGAJSONObject.self, from: data)

    #expect(jsonObject.string("type") == "rect")
    #expect(jsonObject.object("args")?.cgFloat("x") == 12.5)
    #expect(jsonObject.object("args")?.cgFloat("height") == 20)
    #expect(jsonObject.object("styles")?.numbers("fill") == [1, 0.5, 0, 1])
    #expect(jsonObject.bool("hidden") == false)
}

@Test
func jsonValueEncodesAndDescribesAsJSON() throws {
    let value = SVGAJSONValue.object([
        "message": .string("hello"),
        "items": .array([
            .number(1.5),
            .bool(true),
            .null
        ])
    ])

    let encoded = try JSONEncoder().encode(value)
    let decoded = try JSONDecoder().decode(SVGAJSONValue.self, from: encoded)

    #expect(decoded == value)
    #expect(value.description == #"{"items":[1.5,true,null],"message":"hello"}"#)
    #expect(value.debugDescription == value.description)
}

@Test
func videoEntityDecodesLegacyJSONThroughEnumBackedObject() throws {
    let data = """
    {
      "movie": {
        "viewBox": { "width": 320, "height": 240 },
        "fps": 30,
        "frames": 2
      },
      "images": {},
      "sprites": [
        {
          "imageKey": "avatar.png",
          "matteKey": "mask.png",
          "frames": [
            {
              "alpha": 0.75,
              "layout": { "x": 1, "y": 2, "width": 100, "height": 50 },
              "transform": { "a": 1, "b": 0, "c": 0, "d": 1, "tx": 10, "ty": 20 },
              "clipPath": "M0,0 L1,1",
              "shapes": [
                {
                  "type": "rect",
                  "args": { "x": 4, "y": 5, "width": 30, "height": 40, "cornerRadius": 6 },
                  "styles": {
                    "fill": [1, 0, 0, 1],
                    "strokeWidth": 2,
                    "lineCap": "round",
                    "lineJoin": "bevel",
                    "miterLimit": 3,
                    "lineDash": [2, 3, 4]
                  }
                }
              ]
            }
          ]
        }
      ]
    }
    """.data(using: .utf8)!

    let jsonObject = try JSONDecoder().decode(SVGAJSONObject.self, from: data)
    let entity = SVGA.VideoEntity(
        jsonObject: jsonObject,
        cacheDir: FileManager.default.temporaryDirectory.path
    )

    #expect(entity.videoSize == CGSize(width: 320, height: 240))
    #expect(entity.fps == 30)
    #expect(entity.frames == 2)
    #expect(entity.sprites.count == 1)
    #expect(entity.sprites[0].imageKey == "avatar.png")
    #expect(entity.sprites[0].matteKey == "mask.png")

    let frame = try #require(entity.sprites.first?.frames.first)
    #expect(frame.alpha == 0.75)
    #expect(frame.layout == CGRect(x: 1, y: 2, width: 100, height: 50))
    #expect(frame.transform == CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 10, ty: 20))
    #expect(frame.clipPath == "M0,0 L1,1")
    #expect(frame.shapes.count == 1)

    let shape = try #require(frame.shapes.first)
    switch shape.args {
    case .rect(let x, let y, let width, let height, let cornerRadius):
        #expect(x == 4)
        #expect(y == 5)
        #expect(width == 30)
        #expect(height == 40)
        #expect(cornerRadius == 6)
    default:
        Issue.record("Expected rect args")
    }

    let styles = try #require(shape.styles)
    #expect(styles.strokeWidth == 2)
    #expect(styles.lineCap == .round)
    #expect(styles.lineJoin == .bevel)
    #expect(styles.miterLimit == 3)
    #expect(styles.lineDash?.dash == 2)
    #expect(styles.lineDash?.gap == 3)
    #expect(styles.lineDash?.phase == 4)
}
