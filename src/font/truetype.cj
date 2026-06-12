package pixo.font

import pixo.raster.*

struct TablesIndex {
    static let cblc = 0
    static let cff = 1
    static let os2 = 2
    static let camp = 3
    static let glyf = 4
    static let gpos = 5
    static let head = 6
    static let hhea = 7
    static let hmtx = 8
    static let kern = 9
    static let loca = 10
    static let maxp = 11
    static let name = 12
    static let post = 13
}

// 各个数据table位置
struct TableRecord {
    TableRecord(
        let offset: Int64,
        let length: Int64
    ) {}
}

public struct FontInfo {
    var name: String = ""
    var numGlyphs = 0
    var ascent = 0
    var descent = 0
    var lineGap = 0
    var caretSlope = (0, 0)
    var numHMetrics = 0
    var bounds = (0, 0, 0, 0)
    var unitsPerEm: Int26_6 = 0
    var indexToLocFormat = false // false means short, true means long.
    var isPostScript = false
    var isColor = false
}

public class TrueType {
    let tables: Array<TableRecord>
    let r: BinReader
    public var info = FontInfo()

    // 平台字形查找函数
    private var glyphIndexFn: ?glyphIndexFunc = None
    // 
    private var locaOffsets = Array<UInt32>()

    public init(data: Array<Byte>) {
        r = BinReader(data)
        let sfntVer = r.readUInt32()
        match (sfntVer) {
            case 0x00010000 | 0x74727565 => ()
            case 0x4f54544f => 
                // otto
                info.isPostScript = true
                throw Exception("pixo/font: unsupport otto")
            case 0x74746366 => ()
                // ttc
                throw Exception("pixo/font: unsupport ttc")
            case _ => ()
        }

        let numTables = Int64(r.readUInt16())
        // searchRange, entrySelector, rangeShift 是用于快速查找表的参数，我们直接跳过
        r.skip(2 + 2 + 2)

        tables = Array<TableRecord>(14, repeat: TableRecord(0, 0))
        // println("numTables=${numTables}")
        for (_ in 0..numTables) {
            let tag = r.readUInt32()
            let checksum = r.readUInt32()
            let offset = Int64(r.readUInt32())
            let length = Int64(r.readUInt32())
            // println("tag ${tag} offset ${offset}, length ${length}")
            let i = match (tag) {
                case 0x43424c43 => TablesIndex.cblc
                case 0x43464620 => TablesIndex.cff
                case 0x4f532f32 => TablesIndex.os2
                case 0x636d6170 => TablesIndex.camp
                case 0x676c7966 => TablesIndex.glyf
                case 0x47504f53 => TablesIndex.gpos
                case 0x68656164 => TablesIndex.head
                case 0x68686561 => TablesIndex.hhea
                case 0x686d7478 => TablesIndex.hmtx
                case 0x6b65726e => TablesIndex.kern
                case 0x6c6f6361 => TablesIndex.loca
                case 0x6d617870 => TablesIndex.maxp
                case 0x6e616d65 => TablesIndex.name
                case 0x706f7374 => TablesIndex.post
                case _ => -1
            }
            if (i != -1) {
                // println("table ${i}")
                tables[i] = TableRecord(offset, length)
            }
        }
        parseHead()
        parseName()
        parseMaxp()
        parseGlyphData()
        parseCamp()
        parseHhea()
    }

    func parseHead() {
        // https://www.microsoft.com/typography/otspec/head.htm
        if (let Some(t) <- tables.get(TablesIndex.head)) {
            // println("headsize = ${t.length}")
            let tr = r.subView(t.offset, t.length)
            // majorVersion,minorVersion,fontRevision,checkSumAdjustment,magicNumber,flags
            tr.skip(2 + 2 + 4 + 4 + 4 + 2)
            info.unitsPerEm = Int32(tr.readUInt16())
            // created,modified
            tr.skip(8 + 8)
            let x0 = tr.readUInt16()
            let y0 = tr.readUInt16()
            let x1 = tr.readUInt16()
            let y1 = tr.readUInt16()
            // macStyle,lowestRecPPEM,fontDirectionHint
            tr.skip(2 + 2 + 2)
            info.indexToLocFormat = tr.readUInt16() != 0
            info.bounds = (Int64(x0), Int64(y0), Int64(x1), Int64(y1))
        }
    }

    func parseName() {
        // https://www.microsoft.com/typography/otspec/name.htm
        if (let Some(t) <- tables.get(TablesIndex.name)) {
            let tr = r.subView(t.offset, t.length)
            // version
            tr.skip(2)
            let count = Int64(tr.readUInt16())
            let storageOffset = Int64(tr.readUInt16())
            for (i in 0..count) {
                // platformID,encodingID,languageID
                tr.skip(2 + 2 + 2)
                let nameID = Int64(tr.readUInt16())
                let length = Int64(tr.readUInt16())
                let offset = Int64(tr.readUInt16())
                if (nameID != 1) {
                    continue
                }
                let start = storageOffset + offset
                let namebuf = tr.getBytes(start, length)
                info.name = if (namebuf.size > 2 && namebuf[0] == 0 && namebuf[1] == 0) {
                    stringifyUTF16(namebuf)
                } else {
                    String.fromUtf8(namebuf)
                }
                break
            }
        }
    }

    func parseMaxp() {
        // https://www.microsoft.com/typography/otspec/maxp.htm
        let t = tables[TablesIndex.maxp]
        info.numGlyphs = Int64(r.getUInt16(t.offset + 4))
    }

    func parseCamp() {
        // https://www.microsoft.com/typography/otspec/cmap.htm
        let t = tables[TablesIndex.camp]
        let tr = r.subView(t.offset, t.length)
        // version
        tr.readUInt16()
        let numTables = Int64(tr.readUInt16())
        var bestWidth = 0
        var bestFormat = 0
        var bestOffset = 0
        for (i in 0..numTables) {
            let platformID = Int64(tr.readUInt16())
            let encodingID = Int64(tr.readUInt16())
            let subtableOffset = Int64(tr.readUInt32())
            let w = platformEncodingWidth(platformID, encodingID)
            if (w <= bestWidth) {
                continue
            }
            let format = Int64(tr.getUInt16(subtableOffset))
            if (!supportedCmapFormat(format, platformID, encodingID)) {
                continue
            }

            bestFormat = format
            bestOffset = subtableOffset
            bestWidth = w
        }
        if (bestWidth == 0) {
            // todo
            return
        }
        tr.seek(bestOffset)
        println("bestFormat=${bestFormat}")
        this.glyphIndexFn = match (bestFormat) {
            case 0 => cmapFormat0(tr)
            case 4 => cmapFormat4(tr)
            case 6 => cmapFormat6(tr)
            case 12 => cmapFormat12(tr)
            case _ => None
        }
    }

    func parseHhea() {
        // https://www.microsoft.com/typography/OTSPEC/hhea.htm
        if (let Some(t) <- tables.get(TablesIndex.hhea)) {
            let tr = r.subView(t.offset, t.length)
            // majorVersion,minorVersion
            tr.skip(2 + 2)
            info.ascent = Int64(tr.readUInt16())
            info.descent = Int64(tr.readUInt16())
            info.lineGap = Int64(tr.readUInt16())
            // advanceWidthMax,minLeftSideBearing,minRightSideBearing,xMaxExtent
            tr.skip(2 + 2 + 2 + 2)
            info.caretSlope = (Int64(tr.readUInt16()), // caretSlopeRise
                Int64(tr.readUInt16()) // caretSlopeRun
            )
            info.numHMetrics = Int64(tr.getUInt16(34))
            if (info.numHMetrics == 0 || info.numHMetrics > info.numGlyphs) {
                // todo
            }
        }
    }

    func parseGlyphData() {
        let offsetCount = info.numGlyphs + 1
        locaOffsets = Array<UInt32>(offsetCount, repeat: 0)
        if (info.isPostScript) {
            println("postscript")
        // postscript 暂不支持
        // todo
        } else if (let Some(t) <- tables.get(TablesIndex.loca)) {
            let tr = r.subView(t.offset, t.length)
            for (i in 0..offsetCount) {
                locaOffsets[i] = if (info.indexToLocFormat) {
                    tr.readUInt32()
                } else {
                    2 * UInt32(tr.readUInt16())
                }
            }
        } else if (let Some(t) <- tables.get(TablesIndex.cblc)) {
            info.isColor = true
            // 暂不支持颜色位图
            // todo
        }
    }

    func parseKern() {
        // todo
    }

    @OverflowWrapping
    func normalizeContour(phs: Paths, pts: Array<GlyphPoint>) {
        var preoff: ?GlyphPoint = None
        let firstOn = pts[0]
        phs.startTo(firstOn.point)
        for (i in 1..pts.size) {
            let p = pts[i]
            if (p.ov) {
                if (let Some(op) <- preoff) {
                    phs.quadTo(op.point, p.point)
                } else {
                    phs.lineTo(p.point)
                }
                preoff = None
            } else {
                // off
                if (let Some(op) <- preoff) {
                    let mid = (op.point + p.point) / (2 << 6)
                    phs.quadTo(op.point, mid)
                }
                preoff = p
            }
        }
        // 闭合
        if (let Some(op) <- preoff) {
            phs.quadTo(op.point, firstOn.point)
        } else {
            phs.lineTo(firstOn.point)
        }
    }

    @OverflowWrapping
    func loadSimpleGlyh(tr: BinReader, phs: Paths, ppem: Int26_6, numContours: Int64): Unit {
        println("enter loadSimpleGlyh")
        // https://learn.microsoft.com/zh-cn/typography/opentype/spec/glyf#simple-glyph-description
        // 每个轮廓的终点索引
        let endPts = Array(numContours, {_ => Int64(tr.readUInt16())})
        // 总点数 = 最后一个终点索引 + 1
        let numPoints = endPts[numContours - 1] + 1
        // 跳过 TrueType 指令（hinting data）
        let hintingSize = Int64(tr.readInt16())
        tr.skip(hintingSize)

        // 读取标志数组（可能包含重复标志）
        let flags = Array<UInt8>(numPoints, repeat: 0)
        let gpoints = Array<GlyphPoint>(numPoints, {_ => GlyphPoint()})

        var preX: Int16 = 0
        var preY: Int16 = 0
        var i = 0
        while (i < numPoints) {
            let base = i
            let flag = tr.readUInt8()
            let onCurve = (flag & flagOnCurve) != 0
            flags[i] = flag
            gpoints[i].ov = onCurve
            i++
            if ((flag & flagRepeat) != 0) {
                let repeat = Int64(tr.readUInt8())
                for (j in 0..repeat) {
                    flags[i] = flag
                    gpoints[i].ov = onCurve
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
                    tr.readInt16()
                }
            }
            preX += dx
            // gpoints[i].point.x = scale(Int32(preX) * ppem)
            gpoints[i].point.x = Int32(preX)
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
                    tr.readInt16()
                }
            }
            preY += dy
            // gpoints[i].point.y = -scale(Int32(preY) * ppem)
            gpoints[i].point.y =Int32(preY)
        }

        // let points = Array(numPoints, {
        //     i => GlyphPoint(
        //         Point26_6(
        //             scale(xCoordinates[i] * ppem),
        //             -scale(yCoordinates[i] * ppem),
        //         ),
        //         (flags[i] & flagOnCurve) != 0
        //     )
        // })

        var startId = 0
        for (endId in endPts) {
            normalizeContour(phs, gpoints[startId..endId + 1])
            startId = endId + 1
        }
    }

    @OverflowWrapping
    func loadCompoundGlyh(tr: BinReader, phs: Paths, ppem: Int26_6, depth: Int64): Unit {
        if (depth > 20) {
            return
        }
        println("enter loadCompoundGlyh")
        while (true) {
            let flag = tr.readUInt16()
            let glyphIndex = tr.readUInt16()
            if ((flag & flagArgsAreXYValues) == 0) {
                // 不支持点位
                throw Exception("pixo/font: unsupport compound glyph transform vector")
            }
            var m = Array<Int16>(6, repeat: 0)
            if ((flag & flagArg1And2AreWords) != 0) {
                m[4] = tr.readInt16()
                m[5] = tr.readInt16()
            } else {
                m[4] = Int16(tr.readInt8())
                m[5] = Int16(tr.readInt8())
            }
            
            let hasTransfrom = (flag & (flagWeHaveAScale | flagWeHaveAnXAndYScale | flagWeHaveATwoByTwo)) != 0
            if (hasTransfrom) {
                println("mmmmmm")
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
                    case _ => ()
                }
            }

            // 递归获取子字形
            // 记录下当前开始递归前path的位置
            let base = phs.size
            loadGlyph(glyphIndex, phs, ppem, depth: depth + 1)
            for (i in base..phs.size) {
                let pts = phs[i].points
                if (hasTransfrom) {
                    transformArgs(pts, m)
                }else{
                    translateArgs(pts, Int32(m[4]), Int32(m[5]))
                }
            }
            if ((flag & flagMoreComponents) == 0) {
                return
            }
        }
    }

    // 把指定索引的字形轮廓加载到buf里
    // depth 控制符合字形的递归深度
    func loadGlyph(index: UInt16, phs: Paths, ppem: Int26_6, depth!: Int64 = 0): Unit {
        let x = Int64(index)
        if (x >= info.numGlyphs) {
            return
        }
        let i = locaOffsets[x + 0]
        let j = locaOffsets[x + 1]
        if (i >= j) {
            return
        }
        let t = tables[TablesIndex.glyf]
        let d = r.getBytes(t.offset + Int64(i), Int64(j - i))
        if (d.size < 10) {
            return
        }
        let tr = BinReader(d)
        // 轮廓个数（正数表示简单字形，负数表示复合字形）
        let numContours = tr.readInt16()
        if (numContours == 0) {
            return
        }
        tr.seek(10)
        if (numContours < 0) {
            loadCompoundGlyh(tr, phs, ppem, depth)
        } else {
            loadSimpleGlyh(tr, phs, ppem, Int64(numContours))
        }
    }

    func glyphIndex(r: Rune): UInt16 {
        if (let Some(fn) <- glyphIndexFn) {
            fn(r)
        } else {
            UInt16(0)
        }
    }

    public func glyphPath(r: Rune, ppem: Int26_6): Paths {
        let phs = Paths()
        if (info.isColor || info.isPostScript) {
            return phs
        }
        let i = glyphIndex(r)
        println("index=${i}")
        loadGlyph(i, phs, ppem)
        for(v in phs){
            for(x in 0..v.points.size){
                let p = v.points[x]
                v.points[x] = Point26_6(
                    scale(p.x*ppem),
                    -scale(p.y*ppem)
                )
            }
        }
        phs
    }

    // 测试用
    public func glyphAscii(r: Rune, ppem: Int26_6) {
        let phs = glyphPath(r, ppem)
        let bbox = phs.bbox()
        let width = Int64(bbox.width() >> 6) + 1
        let height = Int64(bbox.height() >> 6) + 1
        let biasxy = Point26_6() - bbox.min
        let ra = Fill(width, height)
        ra.addPath(phs, dot: biasxy)
        ra.draw(ASCIIPaint(width, height))
    }

    // public func glyph(r: Rune, ppem: Int26_6, dot!: Point26_6 = Point26_6()) {
    //     // let ppem = Int32(0.5+(fontsize*64.0))
    //     let i = if (let Some(fn) <- glyphIndexFn) {
    //         fn(r)
    //     } else {
    //         UInt16(0)
    //     }

    //     let (glyphBounds, glyphPath) = glyphPath(r, ppem)
    //     let w = glyphBounds.width() >> 6
    //     let h = (glyphBounds.height() >> 6)

    //     var biasxy = dot - glyphBounds.min

    //     let advance = glyphAdvance(i, ppem) >> 6
    //     let height = scale(Int32(info.ascent-info.descent)*ppem)>>6
    //     biasxy += Point26_6(0,Int32(info.ascent)) + glyphBounds.min
    //     println(biasxy.y)
    //     println(info.descent)
    //     println(glyphBounds.min.y)

    //     println("width=${w},height=${h},advance=${advance},dd=${height} ascent=${info.ascent>>6},descent=${info.descent>>6}")

    //     let ra = Fill(Int64(advance), Int64(height + 1))
    //     for (seg in glyphPath) {
    //         match (seg.cmd) {
    //             case PathCmd.Start => ra.startTo(seg.points[0] + biasxy)
    //             case PathCmd.Line => ra.lineTo(seg.points[0] + biasxy)
    //             case PathCmd.Quad => ra.quadTo(seg.points[0] + biasxy, seg.points[1] + biasxy)
    //             case _ => ()
    //         }
    //     }
    //     ra.draw(ASCIIPaint(Int64(advance), Int64(height + 1)))
    // }

    @OverflowWrapping
    public func glyphAdvance(r: Rune, ppem: Int26_6): Int26_6 {
        let i = Int64(glyphIndex(r))
        let v = if (i < info.numHMetrics) {
            i
        } else {
            info.numHMetrics - 1
        }
        let t = tables[TablesIndex.hmtx]
        scale(Int32(this.r.getUInt16(t.offset + 4 * Int64(v))) * ppem)
    }

    @OverflowWrapping
    func scale(x: Int26_6): Int26_6 {
        let nx = if (x >= 0) {
            x + info.unitsPerEm / 2
        } else {
            x - info.unitsPerEm / 2
        }
        return nx / info.unitsPerEm
    }
}

@OverflowWrapping
func stringifyUTF16(b: Array<Byte>): String {
    let runes = Array<Rune>(b.size / 2, {
        i => Rune(u16(b[i * 2..]))
    })
    String(runes)
}

extend Paths {
    public func bbox(): Rectangle26_6 {
        var r = Rectangle26_6()
        for (ele in this) {
            for (i in 0..ele.points.size) {
                r.max.x = max(r.max.x, ele.points[i].x)
                r.max.y = max(r.max.y, ele.points[i].y)
                r.min.x = min(r.min.x, ele.points[i].x)
                r.min.y = min(r.min.y, ele.points[i].y)
            }
        }
        r
    }
}
