package pixo.font

import pixo.raster.{Int26_6, Point26_6}

class GlyphPoint {
    var point = Point26_6()
    var ov = false
}


// Flags for simple (non-compound) glyphs.
// See https://www.microsoft.com/typography/OTSPEC/glyf.htm
let flagOnCurve = UInt8(0x0001)
let flagXShortVector = UInt8(0x0002)
let flagYShortVector = UInt8(0x0004)
let flagRepeat = UInt8(0x0008)
let flagXIsSameOrPShortV = UInt8(0x0010)
let flagYIsSameOrPShortV = UInt8(0x0020)



// Flags for compound glyphs.
// See https://www.microsoft.com/typography/OTSPEC/glyf.htm
let flagArg1And2AreWords = UInt16(0x0001)
let flagArgsAreXYValues = UInt16(0x0002)
let flagRoundXYToGrid = UInt16(0x0004)
let flagWeHaveAScale = UInt16(0x0008)
let flagReserved4 = UInt16(0x0010)
let flagMoreComponents = UInt16(0x0020)
let flagWeHaveAnXAndYScale = UInt16(0x0040)
let flagWeHaveATwoByTwo = UInt16(0x0080)
let flagWeHaveInstructions = UInt16(0x0100)
let flagUseMyMetrics = UInt16(0x0200)
let flagOverlapCompound = UInt16(0x0400)
let flagScaledComponentOffset = UInt16(0x0800)
let flagUnscaledComponentOffset = UInt16(0x1000)



// matrix f2.14 to i26_6
func transformArgs(args: Array<Point26_6>, m: Array<Int16>) {
    const half = 1 << 13
    for ((i, v) in args.enumerate()) {
        args[i] = Point26_6(
            Int32(m[4]) + Int32((Int64(v.x) * Int64(m[0]) + half) >> 14) + Int32((Int64(v.y) * Int64(m[2]) + half) >> 14),
            Int32(m[5]) + Int32((Int64(v.x) * Int64(m[1]) + half) >> 14) + Int32((Int64(v.y) * Int64(m[3]) + half) >> 14),
        )
    }
}

@OverflowWrapping
func translateArgs(args: Array<Point26_6>, dx: Int26_6, dy: Int26_6) {
    for ((i, v) in args.enumerate()) {
        args[i] = Point26_6(v.x + dx, v.y + dy)
    }
}
