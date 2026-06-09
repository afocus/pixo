package pixo.bitmap.encoding.png

import std.io.OutputStream
import std.io.ByteBuffer
import std.binary.BigEndianOrder
import stdx.compress.zlib.CompressOutputStream
import pixo.bitmap.Bitmap
import pixo.color.ColorType

public class Encode {
    private let chunkTempbuf = Array<Byte>(4, repeat: 0)
    let image: Bitmap
    let ct: PNGColorType
    let crc = Crc32IEEE()

    public init(img: Bitmap) {
        image = img
        // 如果不带透明通道优化成RGB
        ct = match (img.colorType) {
            case ColorType.Gray => Gray
            case _ =>
                if (img.isOpaque()) {
                    RGB
                } else {
                    RGBA
                }
        }
    }

    public func encode(w: OutputStream) {
        w.write(pngHeaderBytes)
        writeIHDR(w)
        writeIDATs(w)
        writeChunk(w, "IEND", Array<Byte>())
        w.flush()
    }

    func writeIHDR(w: OutputStream) {
        let headbuf = Array<Byte>(13, repeat: 0)
        UInt32(image.width).writeBigEndian(headbuf[0..4])
        UInt32(image.height).writeBigEndian(headbuf[4..8])
        headbuf[8] = 8 // bitdepth
        headbuf[9] = ct.toValue() // colortype
        headbuf[10] = 0
        headbuf[11] = 0
        headbuf[12] = 0
        writeChunk(w, "IHDR", headbuf)
    }

    @OverflowWrapping
    func writeIDATs(w: OutputStream) {
        // stdx不写入zlib头，这里需要补充上
        let buf = ByteBuffer([0x78, 0x9c])
        let enc = CompressOutputStream(buf)

        let srcSpp = image.colorType.spp()
        let srcLineSize = srcSpp * image.width
        let targetSpp = samplesPerPixel(ct) // 深度统一8
        let targetLineSize = targetSpp * image.width

        // 计算最佳滤波类型的中间数据
        var bestFilterType = 0
        let bestFilterdata = Array<Byte>(targetLineSize, repeat: 0)
        let tempFilterLine = Array<Byte>(targetLineSize, repeat: 0)

        // 上一行数据 用于参与滤波计算
        let pdata = Array<Byte>(targetLineSize, repeat: 0)

        for (y in 0..image.height) {
            // 当前行需要处理优化成rgb的情况
            let cdata = match (ct) {
                case RGB =>
                    let target = Array<Byte>(targetLineSize, repeat: 0)
                    let src = image.pixels[y * srcLineSize..(y + 1) * srcLineSize]
                    for (i in 0..image.width) {
                        target[i * targetSpp + 0] = src[i * srcSpp + 0]
                        target[i * targetSpp + 1] = src[i * srcSpp + 1]
                        target[i * targetSpp + 2] = src[i * srcSpp + 2]
                    }
                    target
                case _ => image.pixels[y * targetLineSize..(y + 1) * targetLineSize]
            }
            // 选择代价最小的滤波器
            var bestCost = Int64.Max
            for (ft in 0..5) {
                for (i in 0..cdata.size) {
                    tempFilterLine[i] = cdata[i] - filterPaeth(UInt8(ft), cdata, pdata, i, targetSpp)
                }
                let c = filterCost(tempFilterLine)
                if (c < bestCost) {
                    bestCost = c
                    bestFilterType = ft
                    tempFilterLine.copyTo(bestFilterdata)
                }
            }
            enc.write(UInt8(bestFilterType))
            enc.write(bestFilterdata)
            // 32KB 一个block
            if (buf.length > (32 >> 10)) {
                // enc.flush()
                writeChunk(w, "IDAT", buf.bytes())
                buf.clear()
            }
            cdata.copyTo(pdata)
        }
        enc.flush()
        enc.close()
        writeChunk(w, "IDAT", buf.bytes())
        buf.clear()
    }

    func filterCost(data: Array<Byte>): Int64 {
        var sum = 0
        for (v in data) {
            if (v > 127) {
                sum += 256 - Int64(v)
            } else {
                sum += Int64(v)
            }
        }
        return sum
    }

    func writeChunk(w: OutputStream, name: String, data: Array<Byte>) {
        let namebytes = unsafe { name.rawData() }
        UInt32(data.size).writeBigEndian(chunkTempbuf)
        w.write(chunkTempbuf)
        w.write(namebytes)
        if (data.size > 0) {
            w.write(data)
        }
        crc.write(namebytes)
        crc.write(data)
        crc.sum().writeBigEndian(chunkTempbuf[0..4])
        crc.reset()
        w.write(chunkTempbuf)
    }
}
