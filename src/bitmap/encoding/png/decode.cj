package pixo.bitmap.encoding.png

import std.binary.BigEndianOrder
import std.io.InputStream
import std.io.ByteBuffer
import stdx.compress.zlib.DecompressInputStream
import pixo.bitmap.Bitmap
import pixo.color.Color

// 将一个png解析成image对象
public class Decode {
    let input: InputStream
    let chunkTempbuf = Array<Byte>(4, repeat: 0)
    let crc = Crc32IEEE()
    var ihdr: ?PNGConfig = None
    var palette = Array<Byte>()

    public init(r: InputStream) {
        input = r
    }

    public func config(): PNGConfig {
        if (let Some(c) <- ihdr) {
            return c
        }
        let h = Array<Byte>(8, repeat: 0)
        input.read(h)
        if (h != pngHeaderBytes) {
            throw Exception("png:bad file")
        }
        let c = readIHDR()
        ihdr = c
        c
    }

    public func decode(): Bitmap {
        let cfg = config()
        let idatBuf = ByteBuffer()
        let img = match (cfg.colorType) {
            case Gray => Bitmap.Gray(cfg.width, cfg.height)
            case _ => Bitmap.RGBA(cfg.width, cfg.height)
        }
        var firstIdat = true
        var run = true
        while (run) {
            let (name, data) = readChunk()
            match (name) {
                case "PLTE" =>
                    if (data.size % 3 != 0) {
                        throw Exception("png:PLTE size error")
                    }
                    palette = data
                case "IDAT" =>
                    // fix zlib miss head
                    if (firstIdat) {
                        firstIdat = false
                        idatBuf.write(data[2..])
                    } else {
                        idatBuf.write(data)
                    }
                case "IEND" =>
                    run = false
                case _ =>
                    // 暂不支持其他类型数据块
                    ()
            }
        }
        idatBuf.flush()
        let enc = DecompressInputStream(idatBuf)
        readIDATs(img, enc)
        enc.close()
        img
    }

    func readIHDR(): PNGConfig {
        let (name, data) = readChunk()
        if (name != "IHDR") {
            throw Exception("png:bad file")
        }
        PNGConfig(
            Int64(UInt32.readBigEndian(data[0..4])),
            Int64(UInt32.readBigEndian(data[4..8])),
            data[8],
            PNGColorType.fromValue(data[9]),
            data[10],
            data[11],
            data[12],
        )
    }

    @OverflowWrapping
    func readPass(enc: DecompressInputStream, w: Int64, h: Int64, cb: (Int64, Int64, Color) -> Unit) {
        let cfg = config()
        let spp = samplesPerPixel(cfg.colorType)
        let bpp = calcFilterBpp(cfg.colorType, cfg.bitDepth)

        let linew = (w * Int64(cfg.bitDepth) * spp + 7) / 8

        let filterType: Array<Byte> = [0]
        let filterLineData = Array<Byte>(linew, repeat: 0) // 临时存放滤波结果
        let pdata = Array<Byte>(linew, repeat: 0) // 解析后上一行
        let cdata = Array<Byte>(linew, repeat: 0) // 解析后当前行
        let depth = Int64(cfg.bitDepth)
        for (y in 0..h) {
            enc.read(filterType)
            let bn = enc.read(filterLineData)
            if (bn != filterLineData.size) {
                throw Exception("png:IDAT read zlib error size=${bn} h=${h} y=${y}")
            }
            for (i in 0..linew) {
                cdata[i] = filterLineData[i] + filterPaeth(filterType[0], cdata, pdata, i, bpp)
            }
            cdata.copyTo(pdata)
            for (x in 0..w) {
                let c = match (cfg.colorType) {
                    case Gray => Color.Gray(readSample(cdata, x, depth, 0, spp))
                    case GrayAlpha =>
                        let g = readSample(cdata, x, depth, 0, spp)
                        let a = readSample(cdata, x, depth, 1, spp)
                        Color.RGBA(g, g, g, a)
                    case Indexed =>
                        let i = readSample(cdata, x, depth, 0, spp)
                        let offset = Int64(i) * 3
                        if (offset >= palette.size) {
                            Color.RGBA(0, 0, 0, 0xff)
                        } else {
                            Color.RGBA(
                                palette[offset + 0],
                                palette[offset + 1],
                                palette[offset + 2],
                                0xff,
                            )
                        }
                    case RGB => Color.RGBA(
                        readSample(cdata, x, depth, 0, spp),
                        readSample(cdata, x, depth, 1, spp),
                        readSample(cdata, x, depth, 2, spp),
                        0xff,
                    )
                    case RGBA => Color.RGBA(
                        readSample(cdata, x, depth, 0, spp),
                        readSample(cdata, x, depth, 1, spp),
                        readSample(cdata, x, depth, 2, spp),
                        readSample(cdata, x, depth, 3, spp),
                    )
                }
                cb(x, y, c)
            }
        }
    }

    func readIDATs(img: Bitmap, enc: DecompressInputStream) {
        let cfg = config()
        if (cfg.interlaceMethod == 0) {
            readPass(enc, cfg.width, cfg.height) {
                x, y, c => img.setColor(x, y, c)
            }
        } else {
            for (pass in adam7Passes) {
                if (pass[1] >= cfg.width || pass[0] >= cfg.height) {
                    continue
                }
                let w = (cfg.width - pass[1] + pass[3] - 1) / pass[3]
                let h = (cfg.height - pass[0] + pass[2] - 1) / pass[2]
                readPass(enc, w, h) {
                    x, y, c => img.setColor(pass[1] + x * pass[3], pass[0] + y * pass[2], c)
                }
            }
        }
    }

    @OverflowWrapping
    func readSample(row: Array<Byte>, x: Int64, bitDepth: Int64, sampleIdx: Int64, spp: Int64): UInt8 {
        match {
            case bitDepth < 8 =>
                // check spp>1? 灰度和索引都是1
                // 计算整体位宽偏移
                let startBit = x * bitDepth
                // 计算在第几个byte
                let byteIndex = startBit / 8
                let bitShift = 8 - (startBit % 8) - bitDepth // 高位在左（MSB先）
                (row[byteIndex] >> bitShift) & ((1 << bitDepth) - 1)
            case bitDepth == 8 =>
                let offset = x * spp + sampleIdx
                row[offset]
            case _ =>
                let n = bitDepth / 8
                let offset = (x * spp + sampleIdx) * n
                UInt8(UInt16.readBigEndian(row[offset..offset + 2]) >> 8)
        }
    }

    func readChunk(): (String, Array<Byte>) {
        input.read(chunkTempbuf)
        let n = UInt32.readBigEndian(chunkTempbuf)
        input.read(chunkTempbuf)
        let name = unsafe { String.fromUtf8Unchecked(chunkTempbuf) }

        let data = Array<Byte>(Int64(n), repeat: 0)
        if (n > 0) {
            input.read(data)
        }

        crc.write(chunkTempbuf)
        crc.write(data)
        let c1 = crc.sum()
        crc.reset()

        input.read(chunkTempbuf)
        let c2 = UInt32.readBigEndian(chunkTempbuf)
        if (c1 != c2) {
            throw Exception("png:crc error type:${name}")
        }
        (name, data)
    }
}
