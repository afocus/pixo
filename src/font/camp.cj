package pixo.font


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

// 字形查找函数 返回在GlyphData中的索引
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

// public struct PathElement {
//     PathElement(let op: UInt8, let args: Array<Point26_6>) {}
//     // public func toString():String{
//     //     // "(${args})"
//     //     "${op} ${args}"
//     // }
// }

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

// @OverflowWrapping
// func normalizeContour(segs: ArrayList<PathElement>, ps: Array<GlyphPoint>) {
//     if (ps.size < 3) {
//         return
//     }
//     var preoff: ?GlyphPoint = None
//     let firstOn = ps[0]
//     segs.add(
//         PathElement(
//             b'M',
//             Point26_6(Int32(firstOn[0]), Int32(firstOn[1]))
//         )
//     )

//     for (i in 1..ps.size) {
//         let p = ps[i]
//         if (p[2]) {
//             if (let Some(op) <- preoff) {
//                 segs.add(
//                     PathElement(
//                         b'Q',
//                         Point26_6(Int32(op[0]), Int32(op[1])),
//                         Point26_6(Int32(p[0]), Int32(p[1]))
//                     )
//                 )
//             } else {
//                 segs.add(
//                     PathElement(
//                         b'L',
//                         Point26_6(Int32(p[0]), Int32(p[1]))
//                     )
//                 )
//             }
//             preoff = None
//         } else {
//             // off
//             if (let Some(op) <- preoff) {
//                 let mid = (Int32(op[0] + p[0]) / 2, Int32(op[1] + p[1]) / 2)
//                 segs.add(
//                     PathElement(
//                         b'Q',
//                         Point26_6(Int32(op[0]), Int32(op[1])),
//                         Point26_6(Int32(mid[0]), Int32(mid[1])),
//                     )
//                 )
//             }
//             preoff = p
//         }
//     }
//     // 闭合
//     if (let Some(op) <- preoff) {
//         segs.add(
//             PathElement(
//                 b'Q',
//                 Point26_6(Int32(op[0]), Int32(op[1])),
//                 Point26_6(Int32(firstOn[0]), Int32(firstOn[1])),
//             )
//         )
//     } else {
//         segs.add(
//             PathElement(
//                 b'L',
//                 Point26_6(Int32(firstOn[0]), Int32(firstOn[1]))
//             )
//         )
//     }
// }
