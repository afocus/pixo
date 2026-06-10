package pixo.font

import std.collection.ArrayList
import pixo.raster.{Int26_6, Point26_6, Rectangle26_6}

// const platformIDUnicode = 0
// const platformIDMac = 1
// const platformIDWindows = 3
// const encodingIDUnicode2BMPOnly = 3
// const encodingIDUnicode2FullRepertoire = 4
// const encodingIDMacRoman = 0
// const encodingIDWindowsSymbol = 0
// const encodingIDWindowsUCS2 = 1
// const encodingIDWindowsUCS4 = 10

func supportedCmapFormat(format: Int64, platformID: Int64, encodingID: Int64) {
    match (format) {
        case 0 => platformID == 1 && encodingID == 0
        case 4 | 6 | 10 => true
        case _ => false
    }
}

func platformEncodingWidth(platformID: Int64, encodingID: Int64): Int64 {
    match ((platformID, encodingID)) {
        case (0, 3) => 2
        case (0, 4) => 4
        case (3, 0) => 2
        case (3, 1) => 2
        case (3, 10) => 4
        case (1, 0) => 1
        case _ => 0
    }
}

type glyphIndexFunc = (Rune) -> UInt16

@OverflowWrapping
func cmapFormat0(r: BinReader): glyphIndexFunc {
    r.skip(2 + 2 + 2) //format,length,language
    let buf = r.readBytes(256).clone()
    return {
        rn: Rune =>
            let code = UInt32(rn)
            UInt16(buf[Int64(code)])
    }
}

@OverflowWrapping
func cmapFormat4(r: BinReader): glyphIndexFunc {
    r.skip(2 + 2 + 2) //format,length,language
    let segCount = Int64(r.readUInt16() / 2)
    r.skip(6) // searchRange,entrySelector,rangeShift

    // 读取每个段的末尾码、起始码、delta 和偏移
    let ends = Array(segCount, {
        i => UInt16(r.readUInt16())
    })
    // reservedPad
    r.skip(2)
    let starts = Array(segCount, {
        i => UInt16(r.readUInt16())
    })
    let deltas = Array(segCount, {
        i => Int16(r.readUInt16())
    })

    // 记录偏移表起始位置，后面用于跳转
    let rangeStart = r.tell()
    let rangeOffsets = Array(segCount, {
        i => UInt16(r.readUInt16())
    })

    return {
        rn: Rune =>
            let code = UInt16(UInt32(rn))
            for (i in 0..segCount) {
                if (code < starts[i] || code > ends[i]) {
                    continue
                }
                if (rangeOffsets[i] == 0) {
                    // 直接使用 delta 计算字形索引
                    return (UInt16(deltas[i]) + code) & 0xFFFF
                } else {
                    // 通过偏移表查找字形索引
                    let offsetInArray = (rangeOffsets[i]) / 2 + (code - starts[i])
                    let pos = rangeStart + i * 2
                    // r.seek(pos + Int64(rangeOffsets[i] + offsetInArray*2))
                    // let glyph = r.readUInt16()
                    // 避免并发下seek错误
                    let glyph = u16(r.buf[pos + Int64(rangeOffsets[i] + offsetInArray * 2)..])
                    if (glyph != 0) {
                        return (glyph + UInt16(deltas[i])) & 0xFFFF
                    }
                    return 0
                }
            }
            0
    }
}

@OverflowWrapping
func cmapFormat6(r: BinReader): glyphIndexFunc {
    r.skip(2 + 2 + 2) // format,length,language
    let firstCode = r.readUInt16()
    let entryCount = Int64(r.readUInt16())
    let entrys = Array(entryCount, {
        i => r.readUInt16()
    })
    return {
        rn: Rune =>
            let code = UInt16(UInt32(rn))
            if (code < firstCode) {
                return 0
            }
            let c = Int64(code - firstCode)
            if (c >= entryCount) {
                return 0
            }
            entrys[c]
    }
}

@OverflowWrapping
func cmapFormat12(r: BinReader): glyphIndexFunc {
    r.seek(2 + 2 + 4 + 4) // format,reserved,length,length
    let numGroups = Int64(r.readUInt32())
    let groups = Array(numGroups, {
        i => (r.readUInt32(), // startChar
            r.readUInt32(), // endChar
            r.readUInt32() // startGlyph
        )
    })
    return {
        rn: Rune =>
            let code = UInt32(rn)
            for (i in 0..numGroups) {
                let (start, end, glyph) = groups[i]
                if (code >= start && code <= end) {
                    return UInt16(glyph + (code - start))
                }
            }
            0
    }
}

/////////////////

type GlyphPoint = (x: Int16, y: Int16, ov: Bool)

class GlyphBuffer {
    let paths = ArrayList<PathElement>()
    var index = 0

    @OverflowWrapping
    func bounds(): Rectangle26_6 {
        var r = Rectangle26_6(
            Point26_6((1 << 31) - 1, (1 << 31) - 1),
            Point26_6(-(1 << 31), -(1 << 31)),
        )
        for (seg in paths) {
            for (i in 0..seg.args.size) {
                r.max.x = max(r.max.x, seg.args[i].x)
                r.max.y = max(r.max.y, seg.args[i].y)
                r.min.x = min(r.min.x, seg.args[i].x)
                r.min.y = min(r.min.y, seg.args[i].y)
            }
        }
        r
    }
}

// class GlyphShapes{
//     let points = ArrayList<GlyphPoint>()
//     let contours = ArrayList<Int64>()
// }

// // Flags for simple (non-compound) glyphs.
// // See https://www.microsoft.com/typography/OTSPEC/glyf.htm
let flagOnCurve = UInt8(0x0001)
let flagXShortVector = UInt8(0x0002)
let flagYShortVector = UInt8(0x0004)
let flagRepeat = UInt8(0x0008)
let flagXIsSameOrPShortV = UInt8(0x0010)
let flagYIsSameOrPShortV = UInt8(0x0020)

@OverflowWrapping
func loadSimpleGlyh(tr: BinReader, buf: GlyphBuffer): Unit {
    // https://learn.microsoft.com/zh-cn/typography/opentype/spec/glyf#simple-glyph-description
    let numContours = Int64(tr.readInt16())
    tr.seek(10)
    // 每个轮廓的终点索引
    let endPts = Array(numContours, {_ => Int64(tr.readUInt16())})
    // 总点数 = 最后一个终点索引 + 1
    let numPoints = endPts[numContours - 1] + 1
    // 跳过 TrueType 指令（hinting data）
    let hintingSize = Int64(tr.readUInt16())
    tr.skip(hintingSize)

    // 读取标志数组（可能包含重复标志）
    let flags = Array<UInt8>(numPoints, repeat: 0)
    let xCoordinates = Array<Int16>(numPoints, repeat: 0)
    let yCoordinates = Array<Int16>(numPoints, repeat: 0)

    var preX: Int16 = 0
    var preY: Int16 = 0
    var i = 0
    while (i < numPoints) {
        let base = i
        let flag = tr.readUInt8()
        flags[i] = flag
        i++
        if ((flag & flagRepeat) != 0) {
            let repeat = Int64(tr.readUInt8())
            for (j in 0..repeat) {
                flags[i] = flag
                i++
            }
        }
    }

    let tmpp = tr.tell()
    for (i in 0..numPoints) {
        let flag = flags[i]
        let dx: Int16 = if ((flag & flagXShortVector) != 0) {
            let v = Int16(tr.readUInt8())
            if ((flag & flagXIsSameOrPShortV) != 0) {
                v
            } else {
                -v
            }
        } else {
            if ((flag & flagXIsSameOrPShortV) != 0) {
                0
            } else {
                Int16(tr.readUInt16())
            }
        }
        preX += dx
        xCoordinates[i] = preX
    }

    for (i in 0..numPoints) {
        let flag = flags[i]
        let dy: Int16 = if ((flag & flagYShortVector) != 0) {
            let v = Int16(tr.readUInt8())
            if ((flag & flagYIsSameOrPShortV) != 0) {
                v
            } else {
                -v
            }
        } else {
            if ((flag & flagYIsSameOrPShortV) != 0) {
                0
            } else {
                Int16(tr.readUInt16())
            }
        }
        preY += dy
        yCoordinates[i] = preY
    }

    let points = Array<GlyphPoint>(numPoints, {
        i => (xCoordinates[i], yCoordinates[i], (flags[i] & flagOnCurve) != 0)
    })

    var startId = 0
    buf.index = buf.paths.size

    for (endId in endPts) {
        normalizeContour(buf.paths, points[startId..endId + 1])
        startId = endId + 1
    }
}

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

// // f2dot14 辅助函数
// func f2dot14(v:Int16):Float32 {
// 	return Float32(v) / 16384.0
// }

@OverflowWrapping
func loadCompoundGlyh(f: TrueType, tr: BinReader, buf: GlyphBuffer, depth: Int64): Unit {
    if (depth > 20) {
        return
    }
    tr.seek(10)
    while (true) {
        let flag = tr.readUInt16()
        if ((flag & flagArgsAreXYValues) == 0) {
            // 不支持点位
            return
        }
        let subIndex = tr.readUInt16()
        var m = Array<Int16>(6, repeat: 0)
        if ((flag & flagArg1And2AreWords) != 0) {
            m[4] = Int16(tr.readUInt8())
            m[5] = Int16(tr.readUInt8())
        } else {
            m[4] = Int16(tr.readUInt16())
            m[5] = Int16(tr.readUInt16())
        }

        var hasTransfrom = true
        match {
            case (flag & flagWeHaveAScale) != 0 =>
                let scale = tr.readInt16()
                m[0] = scale
                m[3] = scale
            case (flag & flagWeHaveAnXAndYScale) != 0 =>
                m[0] = tr.readInt16()
                m[3] = tr.readInt16()
            case (flag & flagWeHaveATwoByTwo) != 0 =>
                m[0] = tr.readInt16()
                m[1] = tr.readInt16()
                m[2] = tr.readInt16()
                m[3] = tr.readInt16()
            case _ => hasTransfrom = false
        }

        // 递归获取子字形
        f.loadGlyph(subIndex, buf, depth: depth + 1)
        for (i in buf.index..buf.paths.size) {
            let ele = buf.paths[i]
            if (hasTransfrom) {
                transformArgs(buf.paths[i].args, m)
            } else {
                translateArgs(buf.paths[i].args, Int32(m[4]), Int32(m[5]))
            }
        }
        if ((flag & flagMoreComponents) == 0) {
            return
        }
    }
}

// matrix f2.14 to i26_6
@OverflowWrapping
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

public struct PathElement {
    PathElement(let op: UInt8, let args: Array<Point26_6>) {}
    // public func toString():String{
    //     // "(${args})"
    //     "${op} ${args}"
    // }
}

// @OverflowWrapping
// func calcPathElementBounds(segs:Array<PathElement>):Rectangle26_6{
//     var r = Rectangle26_6(
//         Point26_6((1 << 31) - 1,(1 << 31) - 1),
//         Point26_6(-(1 << 31),-(1 << 31)),
//     )
//     for(seg in segs){
//         for(i in 0..seg.args.size){
//             r.max.x = max(r.max.x,seg.args[i].x)
//             r.max.y = max(r.max.y,seg.args[i].y)
//             r.min.x = min(r.min.x,seg.args[i].x)
//             r.min.y = min(r.min.y,seg.args[i].y)
//         }
//     }
//     r
// }

@OverflowWrapping
func normalizeContour(segs: ArrayList<PathElement>, ps: Array<GlyphPoint>) {
    if (ps.size < 3) {
        return
    }
    var preoff: ?GlyphPoint = None
    let firstOn = ps[0]
    segs.add(
        PathElement(
            b'M',
            Point26_6(Int32(firstOn[0]), Int32(firstOn[1]))
        )
    )

    for (i in 1..ps.size) {
        let p = ps[i]
        if (p[2]) {
            if (let Some(op) <- preoff) {
                segs.add(
                    PathElement(
                        b'Q',
                        Point26_6(Int32(op[0]), Int32(op[1])),
                        Point26_6(Int32(p[0]), Int32(p[1]))
                    )
                )
            } else {
                segs.add(
                    PathElement(
                        b'L',
                        Point26_6(Int32(p[0]), Int32(p[1]))
                    )
                )
            }
            preoff = None
        } else {
            // off
            if (let Some(op) <- preoff) {
                let mid = (Int32(op[0] + p[0]) / 2, Int32(op[1] + p[1]) / 2)
                segs.add(
                    PathElement(
                        b'Q',
                        Point26_6(Int32(op[0]), Int32(op[1])),
                        Point26_6(Int32(mid[0]), Int32(mid[1])),
                    )
                )
            }
            preoff = p
        }
    }
    // 闭合
    if (let Some(op) <- preoff) {
        segs.add(
            PathElement(
                b'Q',
                Point26_6(Int32(op[0]), Int32(op[1])),
                Point26_6(Int32(firstOn[0]), Int32(firstOn[1])),
            )
        )
    } else {
        segs.add(
            PathElement(
                b'L',
                Point26_6(Int32(firstOn[0]), Int32(firstOn[1]))
            )
        )
    }
}
