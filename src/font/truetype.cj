package pixo.font

import pixo.raster.{Int26_6, Point26_6}

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

struct FontCache {
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
    var glyphIndex: ?glyphIndexFunc = None
    var locaOffsets: Array<UInt32> = []
}

public class TrueType {
    let tables: Array<TableRecord>
    let r: BinReader
    var cache = FontCache()
    public init(data: Array<Byte>) {
        if (String.fromUtf8(data[0..4]) == "ttcf") {
            // 暂不支持ttc
        }
        // raw = data
        r = BinReader(data)
        let sfntVer = r.readUInt32()
        match (sfntVer) {
            case 0x00010000 | 0x74727565 => ()
            case 0x4f54544f => cache.isPostScript = true
            case 0x74746366 => ()
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
            cache.unitsPerEm = Int32(tr.readUInt16())
            // created,modified
            tr.skip(8 + 8)
            let x0 = tr.readUInt16()
            let y0 = tr.readUInt16()
            let x1 = tr.readUInt16()
            let y1 = tr.readUInt16()
            // macStyle,lowestRecPPEM,fontDirectionHint
            tr.skip(2 + 2 + 2)
            cache.indexToLocFormat = tr.readUInt16() != 0
            cache.bounds = (Int64(x0), Int64(y0), Int64(x1), Int64(y1))
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
                cache.name = if (namebuf.size > 2 && namebuf[0] == 0 && namebuf[1] == 0) {
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
        cache.numGlyphs = Int64(r.getUInt16(t.offset + 4))
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
        this.cache.glyphIndex = match (bestFormat) {
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
            cache.ascent = Int64(tr.readInt16())
            cache.descent = Int64(tr.readInt16())
            cache.lineGap = Int64(tr.readInt16())
            // advanceWidthMax,minLeftSideBearing,minRightSideBearing,xMaxExtent
            tr.skip(2 + 2 + 2 + 2)
            cache.caretSlope = (Int64(tr.readUInt16()), // caretSlopeRise
                Int64(tr.readUInt16()) // caretSlopeRun
            )
            cache.numHMetrics = Int64(tr.getUInt16(34))
            if (cache.numHMetrics == 0 || cache.numHMetrics > cache.numGlyphs) {
                // todo
            }
        }
    }

    func parseGlyphData() {
        let offsetCount = cache.numGlyphs + 1
        let locations = Array<UInt32>(offsetCount, repeat: 0)
        if (cache.isPostScript) {
        // postscript 暂不支持
        // todo
        } else if (let Some(t) <- tables.get(TablesIndex.loca)) {
            let tr = r.subView(t.offset, t.length)
            for (i in 0..offsetCount) {
                locations[i] = if (cache.indexToLocFormat) {
                    tr.readUInt32()
                } else {
                    2 * UInt32(tr.readUInt16())
                }
            }
        } else if (let Some(t) <- tables.get(TablesIndex.cblc)) {
            cache.isColor = true
            // 暂不支持颜色位图
            // todo
        }
        cache.locaOffsets = locations
    }

    func parseKern() {
        // todo
    }

    func glyphIndex(r: Rune): UInt16 {
        cache.glyphIndex?(r) ?? 0
    }

    func loadGlyph(index: UInt16, buf: GlyphBuffer, depth!: Int64 = 0): Unit {
        if (cache.isColor) {
            return
        }
        if (cache.isPostScript) {
            return
        }

        let x = Int64(index)
        if (x >= cache.numGlyphs) {
            return
        }
        let i = cache.locaOffsets[x + 0]
        let j = cache.locaOffsets[x + 1]
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
        tr.seek(0)
        if (numContours < 0) {
            loadCompoundGlyh(this, tr, buf, depth)
        } else {
            loadSimpleGlyh(tr, buf)
        }
    }

    // public func getGlyphPath(r:Rune,ppem:Int26_6):Array<PathElement>{

    //     []
    // }

    @OverflowWrapping
    public func glyph(r: Rune, ppem: Int26_6, dot!: Point26_6 = Point26_6()) {
        // let ppem = Int32(0.5+(fontsize*64.0))
        let i = glyphIndex(r)
        // todo objectPool ?
        let buf = GlyphBuffer(ppem, cache.unitsPerEm, dot)
        loadGlyph(i, buf)
        // for (seg in buf.paths) {
        //     for ((j, v) in seg.args.enumerate()) {
        //         seg.args[j] = Point26_6(
        //             scale(v.x * ppem),
        //             -scale(v.y * ppem)
        //         )
        //     }
        // }
        let bounds = buf.bounds()
        let width = (bounds.max.x - bounds.min.x) >> 6
        let height = (bounds.max.y - bounds.min.y) >> 6

        let biasxy = Point26_6(
            dot.x - bounds.min.x,
            dot.y - bounds.min.y
        )
        let advance = glyphAdvance(i, ppem) >> 6
        println("width=${width},height=${height},advance=${advance}")
        println("pos=${bounds.min.x}")

        // let ra = Raster(Int64(advance), Int64(height+1))
        // for(seg in buf.paths){
        //     match(seg.op){
        //         case b'M' =>
        //             ra.startTo(seg.args[0]+biasxy)
        //         case b'L' =>
        //             ra.lineTo(seg.args[0]+biasxy)
        //         case b'Q' =>
        //             ra.quadTo(seg.args[0]+biasxy,seg.args[1]+biasxy)
        //         case _=>()
        //     }
        // }
        // ra.draw()
    }

    @OverflowWrapping
    func glyphAdvance(x: UInt16, ppem: Int26_6): Int26_6 {
        let i = Int64(x)
        let v = if (i < cache.numHMetrics) {
            i
        } else {
            cache.numHMetrics - 1
        }
        let t = tables[TablesIndex.hmtx]
        scale(Int32(r.getUInt16(t.offset + 4 * Int64(v))) * ppem)
    }

    @OverflowWrapping
    func scale(x: Int26_6): Int26_6 {
        let nx = if (x >= 0) {
            x + cache.unitsPerEm / 2
        } else {
            x - cache.unitsPerEm / 2
        }
        return nx / cache.unitsPerEm
    }
}

func stringifyUTF16(b: Array<Byte>): String {
    let runes = Array<Rune>(b.size / 2, {
        i => Rune(u16(b[i * 2..]))
    })
    String(runes)
}
