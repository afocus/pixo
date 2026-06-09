package pixo.bitmap.encoding.jpeg


import std.io.InputStream
import std.binary.BigEndianOrder
import pixo.bitmap.Bitmap

const blocksize = 8 * 8
const maxComponentSize = 4 // 最大分量数

// 颜色分量信息
class DevComponent {
    var expandH: Int64 = 0
    var expandV: Int64 = 0
    var blockWidth: Int64 = 0
    var blockHeight: Int64 = 0
    DevComponent(
        let id: Int64, // // 分量标识符（1=Y, 2=Cb, 3=Cr）
        let h: Int64, // 水平采样因子
        let v: Int64, // 垂直采样因子
        let qid: Int64 // 使用的量化表 ID
    ) {}
}

// sos扫描的分量信息
struct ScanComp {
    ScanComp(
        let cIndex: Int64, // 分量索引
        let td: Int64, // DC huffman index
        let ta: Int64 // AC huffman index
    ) {}
}



// HuffmanTable 基于 LUT 的霍夫曼解码表
class DevHuffman {
    let luts = Array<UInt16>(1 << 8, repeat: 0) // 快速查找表，8 位索引
    let vals = Array<Byte>(256, repeat: 0) // 符号值
    let minCodes = Array<Int32>(16, repeat: 0) // 每种码长的最小码字
    let maxCodes = Array<Int32>(16, repeat: 0) // 每种码长的最大码字
    let valIndexs = Array<Int32>(16, repeat: 0) // 每种码长在 vals 中的起始索引

    // codes  每种码长的码字数量
    func build(codes: Array<Int32>) {
        // 构建 LUT：将长度 ≤8 的码字映射到 256 个 8 位前缀
        var code: UInt32 = 0
        var symbolIndex: Int64 = 0
        luts.fill(0)
        for (i in 0..8) {
            code <<= 1
            for (_ in 0..codes[i]) {
                let base = UInt8(code << (7 - i))
                // 高8位=符号，低8位=码长+1
                let lutValue = UInt16(vals[symbolIndex]) << 8 | UInt16(2 + i)
                for (k in 0..1 << (7 - i)) {
                    luts[Int64(base | UInt8(k))] = lutValue
                }
                code++
                symbolIndex++
            }
        }

        // 构建慢路径辅助表：minCodes, maxCodes, valsIndices
        var c: Int32 = 0
        var index: Int32 = 0
        for ((i, v) in codes.enumerate()) {
            if (v == 0) {
                minCodes[i] = -1
                maxCodes[i] = -1
                valIndexs[i] = -1
            } else {
                minCodes[i] = c
                maxCodes[i] = c + v - 1
                valIndexs[i] = index
                c += v
                index += v
            }
            c <<= 1
        }
    }

    func decode(br: BitReader): Byte {
        var useFast = true
        if (!br.tryFillBits(8)) {
            // 填充失败 如有还有未消费的bit处理下
            if (br.n > 0) {
                useFast = false
            }
        }
        if (useFast) {
            let bit = br.peekBits(8) & 0xff
            let lu = luts[Int64(bit)]
            if (lu != 0) {
                let n = (lu & 0xff) - 1
                br.consumeBits(Int64(n))
                return UInt8(lu >> 8)
            }
            if (br.n > 8) {
                // 未命中：消耗已查看的 8 比特，从第 9 比特开始继续
                br.consumeBits(8)
                if (let Some(v) <- slowPathDecode(Int32(bit), 8, br)) {
                    return v
                }
            }
        }
        slowPathDecode(0, 0, br).getOrThrow {=> Exception("jpeg: bad Huffman code")}
    }

    func slowPathDecode(initcode: Int32, index: Int64, br: BitReader): ?Byte {
        var code = initcode
        for (i in index..16) {
            let b = Int32(br.readBits(1) & 1)
            code = (code << 1) | b
            if (code <= maxCodes[i]) {
                let idx = Int64(valIndexs[i] + code - minCodes[i])
                return vals[idx]
            }
        }
        None
    }
}


public class Decode {
    let r: BitReader
    var width: Int64 = 0
    var height: Int64 = 0

    var dri = 0
    var progressive = false
    var mcuWidth: Int64 = 0
    var mcuHeight: Int64 = 0
    var maxH: Int64 = 0
    var maxV: Int64 = 0

    // 量化表
    let qaTables = Array<Array<Int32>>(maxComponentSize) {
        _ => Array<Int32>(blocksize, repeat: 0)
    }
    // Huffman tables 0:dc 1:ac
    let hfTables = Array<Array<DevHuffman>>(2) {
        _ => Array<DevHuffman>(maxComponentSize, {_ => DevHuffman()})
    }
    // 颜色分量
    let comps = Array<DevComponent>(maxComponentSize) {
        _ => unsafe { zeroValue<DevComponent>() }
    }
    let coeffs = Array<Array<Array<Int32>>>(maxComponentSize) {
        _ => Array<Array<Int32>>()
    }
    var compsSize = 0

    let dc = Array<Int32>(maxComponentSize, repeat: 0) // 直流系数差分预测值 索引comps
    var eobRun: UInt16 = 0

    // 单个mcu平面像素 用于mcu渲染图像
    // 不用等待全部扫描完
    var mcuPixMax = 0
    var mcuPixBuf = Array<Int32>() // Array<Int32>(mcuPixMax,repeat:0)
    var img: ?Bitmap = None

    public init(r: InputStream) {
        this.r = BitReader(r, 2 * blocksize)
    }

    func readMarker(): Byte {
        var flag = false
        while (true) {
            let b = r.readByte()
            if (b == 0xff) {
                flag = true
                continue
            }
            if (flag) {
                if (b == 0x00) {
                    flag = false
                    continue
                }
                return b
            }
        }
        throw Exception("jpeg: read eof")
    }

    public func decode(): Bitmap {
        if (readMarker() != 0xd8) {
            throw Exception("jpeg: miss marker 0xd8")
        }
        while (true) {
            let marker = readMarker()
            if (0xd0 <= marker && marker <= 0xd7) {
                continue
            }

            if (marker == 0xd9) {
                break
            }

            let n = Int64(r.readU16() - 2)
            match (marker) {
                case 0xc0 | 0xc1 | 0xc2 => parseSOF(n, marker)
                case 0xc4 => parseDHT(n)
                case 0xda => parseSOS(n)
                case 0xdb => parseDQT(n)
                case 0xdd => parseDRI(n)
                case 0xee => parseAPP14(n) // todo fix
                case _ =>
                    // 有数据但是无需处理
                    if (marker >= 0xe0 && marker <= 0xef || marker == 0xfe) {
                        r.ignore(n)
                    } else {
                        throw Exception("jpeg: unknown marker=${marker}")
                    }
            }
        }

        if (progressive) {
            for (my in 0..mcuHeight) {
                for (mx in 0..mcuWidth) {
                    renderMcuImage(mx, my)
                }
            }
        }
        img.getOrThrow()
    }



    func parseAPP14(n: Int64) {
        if (n < 12) {
            r.ignore(n)
            return
        }

        let buf = r.readNBytes(n)
        if (unsafe { String.withRawData(buf[..5]) } == "Adobe") {
            // cfg.adobeTransform = buf[11]
            // cfg.adobe = true
            throw Exception("jpeg: unsupport adobe")
        }
    }

    func parseDRI(n: Int64) {
        dri = Int64(r.readU16())
    }

    func parseSOF(n: Int64, marker: Byte) {
        progressive = marker == 0xc2
        let buf = r.readNBytes(n)
        // 精度 (1字节)：每个样本的位数，通常为 8
        let x = buf[0]
        if (x != 8) {
            throw Exception("jpeg: only support 8-bit precision")
        }

        height = Int64(UInt16.readBigEndian(buf[1..3]))
        width = Int64(UInt16.readBigEndian(buf[3..5]))
        compsSize = Int64(buf[5]) // 颜色分量数

        for (i in 0..compsSize) {
            let id = buf[6 + i * 3 + 0]
            let hv = buf[6 + i * 3 + 1]
            let qt = buf[6 + i * 3 + 2]
            var h = Int64(hv >> 4)
            var v = Int64(hv & 0x0f)
            // 灰度图像必须使用 1x1 采样（标准要求非交错扫描）
            if (compsSize == 1) {
                h = 1
                v = 1
            }
            maxH = max(maxH, h)
            maxV = max(maxV, v)
            comps[i] = DevComponent(Int64(id),h,v,Int64(qt))
        }

        // 预计算 MCU 网格尺寸（基于全局最大采样因子）
        mcuWidth = (width + 8 * Int64(maxH) - 1) / (8 * Int64(maxH))
        mcuHeight = (height + 8 * Int64(maxV) - 1) / (8 * Int64(maxV))

         // MCU平面最大可能为maxH*8 * maxV*8像素，
        mcuPixMax = maxH*maxV*64

        for (i in 0..compsSize) {
            let c = comps[i]
            c.expandH = maxH / c.h
            c.expandV = maxV / c.v
            c.blockWidth = mcuWidth * c.h
            c.blockHeight = mcuHeight * c.v
        }
    }

    func parseDQT(n: Int64) {
        var pos = 0
        // 用于存储一个或多个量化表
        while (pos < n) {
            pos++
            // 表信息字节 (1字节)：高4位为精度（0=8位/1=16位）；低4位为表ID。
            let x = r.readByte()
            let tid = Int64(x & 0x0f)
            match (x >> 4) {
                case 0 =>
                    let buf = r.readNBytes(blocksize)
                    for (i in 0..blocksize) {
                        qaTables[tid][i] = Int32(buf[i])
                    }
                    pos += blocksize
                case 1 =>
                    let buf = r.readNBytes(blocksize * 2)
                    for (i in 0..blocksize) {
                        qaTables[tid][i] = Int32(UInt16.readBigEndian(buf[i * 2 + 0..i * 2 + 2]))
                    }
                    pos += blocksize * 2
                case _ => throw Exception("jpeg: bad Pq value")
            }
        }
        if (pos != n) {
            throw Exception("jpeg: DQT has wrong length")
        }
    }

    func parseDHT(n: Int64) {
        var i = n
        while (i > 0) {
            let buf = r.readNBytes(17)
            if (buf.size < 17) {
                throw Exception("jpeg: DHT has wrong length")
            }
            let x = buf[0]
            // JFIF通常包含4张DHT表，分别是：亮度DC表（ID=0）、亮度AC表（ID=0）、色度DC表（ID=1）、色度AC表（ID=1）
            // 表类型（0=DC表/1=AC表）
            let h = hfTables[Int64(x >> 4)][Int64(x & 0x0f)]
            // 读取 16 字节的长度计数
            var totalValue = 0
            let codes = Array<Int32>(16, repeat: 0)
            for (i in 0..16) {
                let v = Int32(buf[i + 1])
                codes[i] = v
                totalValue += Int64(v)
            }
            // 读取符号值列表
            r.read(h.vals[..totalValue])
            h.build(codes)

            i -= totalValue + 17
        }
    }

    @OverflowWrapping
    func parseSOS(n: Int64) {
        let buf = r.readNBytes(n)
        // 参与本次扫描的分量数
        let ncomp = Int64(buf[0])
        let scans = Array<ScanComp>(ncomp) {
            _ => unsafe { zeroValue<ScanComp>() }
        }
        for (i in 0..ncomp) {
            // 分量 ID 对应 SOF 段中定义的分量 ID（例如 1=Y, 2=Cb, 3=Cr）
            let cs = Int64(buf[2 * i + 1])
            // 哈夫曼表选择
            let x = buf[2 * i + 2]
            var cIndex = -1
            for (j in 0..compsSize) {
                if (comps[j].id == cs) {
                    cIndex = j
                    break
                }
            }
            if (cIndex == -1) {
                for (c in comps) {
                    println("id=${c.id}")
                }
                throw Exception("sos compoent not found id = ${cs}")
            }
            scans[i] = ScanComp(cIndex, Int64(x >> 4), Int64(x & 0x0f))
        }

        let ss = Int64(buf[1 + 2 * ncomp])
        let se = Int64(buf[2 + 2 * ncomp])
        let ah = Int64(buf[3 + 2 * ncomp] >> 4)
        let al = Int64(buf[3 + 2 * ncomp] & 0x0f)

        for (sc in scans) {
            let c = comps[sc.cIndex]
            // 渐进式需要收集全部block
            // 基线模式则只收集一行block
            let n = if (progressive) {
                c.blockWidth * c.blockHeight
            } else {
                c.h*c.v
            }
            if (coeffs[sc.cIndex].size == 0) {
                coeffs[sc.cIndex] = Array<Array<Int32>>(n) {
                    _ => Array<Int32>(blocksize, repeat: 0)
                }
            }
        }

        if (img.isNone()) {
            mcuPixBuf = Array<Int32>(mcuPixMax * compsSize, repeat: 0)
            img = if (compsSize == 1) {
                Bitmap.Gray(width, height)
            } else {
                Bitmap.RGBA(width, height)
            }
        }

        scanMcus(scans, ss, se, ah, al)
    }

    
    func scanMcus(scans: Array<ScanComp>, ss: Int64, se: Int64, ah: Int64, al: Int64) {
        var blockCnt = 0
        var mcu = 0
        var expectedRST: UInt8 = 0xd0 // rst0Marker
        r.reset()
        dc.fill(0)

        for (my in 0..mcuHeight) {
            // row start..
            for (mx in 0..mcuWidth) {
                for (sc in scans) {
                    let c = comps[sc.cIndex]
                    for (i in 0..c.h * c.v) {
                        let (bx, by) = if (scans.size == 1) {
                            (blockCnt % c.blockWidth, blockCnt / c.blockWidth)
                        } else {
                            (mx * c.h + i % c.h, my * c.v + i / c.v)
                        }
                        if (scans.size == 1) {
                            blockCnt++
                            if (bx * 8 >= width || by * 8 >= height) {
                                continue
                            }
                        }
                        let idx = if (progressive){ by * c.blockWidth + bx }else{ i }
                        let b = coeffs[sc.cIndex][idx]
                        processblock(b, sc, ss, se, ah, al)
                    }
                }
                mcu++
                if (!progressive) {
                    // 基线模式 按mcu渲染像素
                    renderMcuImage(mx, my)
                    // coeffs被复用所以需要重置
                    for (cc in coeffs) {
                        for (b in cc) {
                            b.fill(0)
                        }
                    }
                }

                if ((dri > 0) && (mcu % dri == 0) && mcu < mcuWidth * mcuHeight) {
                    while (true) {
                        if (readMarker() == expectedRST) {
                            break
                        }
                    }
                    expectedRST++
                    if (expectedRST == 0xd7 + 1) {
                        expectedRST = 0xd0
                    }
                    r.reset()
                    dc.fill(0)
                    eobRun = 0
                }
            }
            // row end
        }
    }

    func processblock(b: Array<Int32>, sc: ScanComp, ss: Int64, se: Int64, ah: Int64, al: Int64) {
        var zig = ss
        if (ah == 0) {
            if (zig == 0) {
                // dc
                let v = hfTables[0][sc.td].decode(r)
                let dcDelta = r.receiveExtend(v & 0x0f)
                dc[sc.cIndex] += dcDelta
                b[0] = dc[sc.cIndex] << al

                zig++
            }

            // ac
            if (zig <= se && eobRun > 0) {
                eobRun--
            } else {
                while (zig <= se) {
                    let v = hfTables[1][sc.ta].decode(r)
                    let v0 = Int64(v >> 4)
                    let v1 = v & 0x0f
                    if (v1 != 0) {
                        zig += v0
                        if (zig > se) {
                            break
                        }
                        b[unzig[zig]] = r.receiveExtend(v1) << al
                    } else {
                        if (v0 != 0x0f) {
                            eobRun = 1 << v0
                            if (v0 != 0) {
                                eobRun |= UInt16(r.readBits(v0))
                            }
                            eobRun--
                            break
                        }
                        zig += 0x0f
                    }
                    zig++
                }
            }
        } else {

            // 渐进式
            let delta = Int32(1 << al)
            // dc
            if (zig == 0) {
                if (r.readBits(1) == 1) {
                    b[0] |= delta
                }
                return
            }

            // ac
            if (eobRun == 0) {
                while (zig <= se) {
                    var z = Int32(0)
                    let v = hfTables[1][sc.ta].decode(r)
                    let v0 = Int64(v >> 4)
                    let v1 = Int64(v & 0x0F)
                    if (v1 == 0) {
                        if (v0 != 0x0f) {
                            eobRun = 1 << v0
                            if (v0 != 0) {
                                eobRun |= UInt16(r.readBits(v0))
                            }
                            break
                        }
                    } else if (v1 == 1) {
                        z = delta
                        if (r.readBits(1) == 0) {
                            z = -z
                        }
                    } else {
                        throw Exception("jpeg: unexpected Huffman code")
                    }
                    zig = refineNonZeroes(b, zig, se, v0, delta)
                    if (zig > se) {
                        throw Exception("jpeg: too many coefficients")
                    }
                    if (z != 0) {
                        b[unzig[zig]] = z
                    }
                    zig++
                }
            }
            if (eobRun > 0) {
                eobRun--
                refineNonZeroes(b, zig, se, -1, delta)
            }
        }
    }

    func refineNonZeroes(b: Array<Int32>, ss: Int64, se: Int64, nz: Int64, delta: Int32): Int64 {
        var zig = ss
        var nzz = nz
        while (zig <= se) {
            let u = unzig[zig]
            if (b[u] == 0) {
                if (nzz == 0) {
                    break
                }
                nzz--
            } else {
                if (r.readBits(1) == 1) {
                    if (b[u] >= 0) {
                        b[u] += delta
                    } else {
                        b[u] -= delta
                    }
                }
            }
            zig++
        }
        return zig
    }

    // 按单个mcu渲染图片
    func renderMcuImage(mx: Int64, my: Int64) {
        let x0 = mx * maxH * 8
        let y0 = my * maxV * 8
        if (y0 >= height || x0 >= width) {
            return
        }
        let mcuw = min(maxH * 8, width - x0)
        let mcuh = min(maxV * 8, height - y0)
        // 分配mcu临时平面大小
        let pixsize = mcuw * mcuh
        for (i in 0..compsSize) {
            fillMcuPlane(mcuPixBuf[i * mcuPixMax..i * mcuPixMax + pixsize], i, mx, my, mcuw, mcuh)
        }
        let m = img.getOrThrow()
        for (py in 0..mcuh) {
            let rowStart = (y0 + py) * width + x0
            let offset = py * mcuw
            for (px in 0..mcuw) {
                if(compsSize == 1){
                    m.pixels[rowStart + px] = clamp(mcuPixBuf[offset + px])
                    continue
                }
                let (r, g, b) = if (compsSize == 4) {
                    cmyk2rgb(
                        mcuPixBuf[0 * mcuPixMax + offset + px],
                        mcuPixBuf[1 * mcuPixMax + offset + px],
                        mcuPixBuf[2 * mcuPixMax + offset + px],
                        mcuPixBuf[3 * mcuPixMax + offset + px],
                    )
                } else {
                    ycbcr2rgb(
                        mcuPixBuf[0 * mcuPixMax + offset + px],
                        mcuPixBuf[1 * mcuPixMax + offset + px] - 128,
                        mcuPixBuf[2 * mcuPixMax + offset + px] - 128,
                    )
                }
                m.pixels[4 * (rowStart + px) + 0] = r
                m.pixels[4 * (rowStart + px) + 1] = g
                m.pixels[4 * (rowStart + px) + 2] = b
                m.pixels[4 * (rowStart + px) + 3] = 255
            }
        }
    }



    func fillMcuPlane(buf: Array<Int32>, cindex: Int64, mx: Int64, my: Int64, w: Int64, h: Int64) {
        let c = comps[cindex]
        for (by in 0..c.v) {
            let blockrow = my * c.v + by
            for (bx in 0..c.h) {
                let idx = if (progressive) {
                    let blockrow = my * c.v + by
                    let blockcol = mx * c.h + bx
                    blockrow*c.blockWidth + blockcol
                } else {
                    by * c.h + bx
                }
                if (idx >= coeffs[cindex].size) {
                    continue
                }
                
                let b = coeffs[cindex][idx]
                let qt = qaTables[c.qid]
                for (i in 0..blocksize) {
                    b[unzig[i]] *= qt[i]
                }
                idct(b)

                let basex = bx * 8 * c.expandH
                let basey = by * 8 * c.expandV
                for (py in 0..8) {
                    let y0 = basey + py * c.expandV
                    if (y0 >= h) {
                        break
                    }
                    for (px in 0..8) {
                        let v = b[py * 8 + px] + 128
                        let x0 = basex + px * c.expandH
                        if (x0 >= w) {
                            break
                        }
                        // 填充矩形区域（利用扩展因子复制像素）
                        for (dy in 0..c.expandV) {
                            let y = y0 + dy
                            if (y >= h) {
                                break
                            }
                            let rowOffset = y * w
                            for (dx in 0..c.expandH) {
                                let x = x0 + dx
                                if (x >= w) {
                                    break
                                }
                                buf[rowOffset + x] = v
                            }
                        }
                    }
                }
            }
        }
    }
}
