package pixo.bitmap.encoding.bmp

import std.io.InputStream
import pixo.bitmap.Bitmap
import pixo.color.Color

public class Decode {
    let r: InputStream
    var palette = Array<Color>()
    public init(r: InputStream) {
        this.r = r
    }

    @OverflowWrapping
    public func decode(): Bitmap {
        let info = parseHeader()
        let (h, flag) = if (info.height < 0) {
            (-info.height, true)
        } else {
            (info.height, false)
        }
        let img = Bitmap.RGBA(info.width, h)
        if (info.width == 0 || info.height == 0) {
            return img
        }

        // 计算每行像素数据所占的字节数 (必须为 4 的倍数)
        let lineW = (Int64(info.bpp) * info.width + 31) / 32 * 4
        let line = Array<Byte>(lineW, repeat: 0)
        let allowAlpha = info.size > 40 // for rgba
        let mask = UInt8((1 << info.bpp) - 1) // for palette
        
        for (y0 in 0..h) {
            let y = if (flag) {
                y0
            } else {
                h - y0 - 1
            }
            r.read(line)
            match (info.bpp) {
                case 1 | 2 | 4 | 8 =>
                    var byteIndex = 0
                    var bitIndex = 8
                    for (x in 0..info.width) {
                        bitIndex -= Int64(info.bpp)
                        let colorIndex = Int64((line[byteIndex]) >> bitIndex & mask)
                        if (bitIndex == 0) {
                            byteIndex++
                            bitIndex = 8
                        }
                        img.setColor(
                            x,
                            y,
                            palette[colorIndex],
                        )
                    }
                case 24 => for (x in 0..info.width) {
                    img.setColor(
                        x,
                        y,
                        Color.RGBA(
                            line[x * 3 + 2],
                            line[x * 3 + 1],
                            line[x * 3 + 0],
                            0xff,
                        )
                    )
                }
                case 32 => for (x in 0..info.width) {
                    img.setColor(
                        x,
                        y,
                        Color.RGBA(
                            line[x * 4 + 2],
                            line[x * 4 + 1],
                            line[x * 4 + 0],
                            if (!allowAlpha) {
                                0xff
                            } else {
                                line[x * 4 + 3]
                            },
                        )
                    )
                }
                case _ => ()
            }
        }
        img
    }

    @OverflowWrapping
    func parseHeader(): BmpInfoHeader {
        let rr = BinReader(r)
        if (rr.readU16() != 0x4D42) {
            throw Exception("bmp: bad file")
        }
        rr.readBytes(8)
        let offset = Int64(rr.readU32())
        let info = BmpInfoHeader(
            Int64(rr.readU32()),
            Int64(rr.readU32()),
            Int64(rr.readI32()),
            rr.readU16(),
            rr.readU16(),
            rr.readU32(),
            rr.readU32(),
            rr.readU32(),
            rr.readU32(),
            Int64(rr.readU32()),
            Int64(rr.readU32())
        )
        var c = info.compression
        if (c == 3 && info.size > 40) {
            if (rr.readU32() == 0xff0000 && rr.readU32() == 0xff00 && rr.readU32() == 0xff && rr.readU32() == 0xff000000) {
                c = 0
            }
        }
        if (c != 0 || info.planes != 1) {
            throw Exception("bmp: unsupport")
        }

        // 跳过多余的内容
        // 避免下面解析调色板错位
        var n = info.size + 14 - rr.postion()
        if (n > 0) {
            rr.readBytes(n)
        }

        if (info.bpp <= 8) {
            // 调色板
            let colorCount = if (info.colorUsed == 0) {
                Int64(1 << info.bpp) // 全色
            } else {
                info.colorUsed
            }
            let bs = rr.readBytes(colorCount * 4)
            palette = Array<Color>(colorCount, {
                // bgr -> rgb
                i => Color.RGBA(
                    bs[i * 4 + 2],
                    bs[i * 4 + 1],
                    bs[i * 4 + 0],
                    0xff,
                )
            })
        }
        if(offset!=rr.postion()){
            throw Exception("bmp: bad file")
        }
        info
    }
}
