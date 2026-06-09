package pixo.bitmap.encoding.bmp

import std.io.OutputStream
import pixo.bitmap.Bitmap
import pixo.color.*

public class Encode {
    let img: Bitmap
    public init(image: Bitmap) {
        img = image
    }
    public func encode(w: OutputStream) {
        let (info, linew) = writeHeader(w)
        let line = Array<Byte>(linew, repeat: 0)
        for (y in 0..img.height) {
            for (x in 0..img.width) {
                match (img.getColor(x, y)) {
                    case Color.Gray(y) => 
                        line[x] = y
                    case Color.RGBA(r, g, b, a) =>
                        if (info.bpp == 24) {
                            line[x * 3 + 0] = b
                            line[x * 3 + 1] = g
                            line[x * 3 + 2] = r
                        } else {
                            line[x * 4 + 0] = b
                            line[x * 4 + 1] = g
                            line[x * 4 + 2] = r
                            line[x * 4 + 3] = a
                        }
                }
            }
            w.write(line)
        }
    }

    func writeHeader(w: OutputStream): (BmpInfoHeader, Int64) {
        let bitCount: UInt16 = match (img.colorType) {
            case ColorType.Gray => 8
            case ColorType.RGBA =>
                if (img.isOpaque()) {
                    24
                } else {
                    32
                }
        }

        let paletteLen = if (bitCount == 8) {
            256 * 4 // 8位全色板
        } else {
            0
        }

        let hinfo = BmpInfoHeader(40, img.width, img.height, 1, bitCount, 0, 0, 0, 0, 0, 0)

        // 计算每行字节数（4 字节对齐）
        let lineW = (Int64(hinfo.bpp) * hinfo.width + 31) / 32 * 4
        let offset = UInt32(14 + hinfo.size) + UInt32(paletteLen)
        let fileSize = offset + UInt32(lineW * hinfo.height)

        let ww = BinWriter(w)
        // header
        ww.write(bmpHeaderBytes)
        ww.write(fileSize)
        ww.write(UInt32(0))

        ww.write(offset)

        // info
        ww.write(UInt32(hinfo.size))
        ww.write(UInt32(hinfo.width))
        ww.write(UInt32(hinfo.height))
        ww.write(UInt16(hinfo.planes))
        ww.write(UInt16(hinfo.bpp))
        ww.write(hinfo.compression)
        ww.write(UInt32(0))
        ww.write(UInt32(0))
        ww.write(UInt32(0))
        ww.write(UInt32(0))
        ww.write(UInt32(0))

        if (paletteLen > 0) {
            // 简单处理 方便gray图直接使用调色板索引
            let palette = Array<Byte>(256 * 4, repeat: 0)
            for (i in 0..256) {
                palette[i * 4 + 0] = UInt8(i)
                palette[i * 4 + 1] = UInt8(i)
                palette[i * 4 + 2] = UInt8(i)
                palette[i * 4 + 3] = 0xff
            }
            ww.write(palette)
        }

        (hinfo, lineW)
    }
}
