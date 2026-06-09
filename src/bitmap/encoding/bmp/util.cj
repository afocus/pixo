package pixo.bitmap.encoding.bmp

import std.binary.LittleEndianOrder
import std.io.InputStream
import std.io.OutputStream

let bmpHeaderBytes: Array<Byte> = "BM".toArray()

struct BmpInfoHeader {
    BmpInfoHeader(
        let size: Int64, // 本结构大小 (40)
        let width: Int64, // 图像宽度 (像素)
        let height: Int64, // 图像高度 (像素，正数表示自底向上，负数表示自顶向下)
        let planes: UInt16, // 颜色平面数，必须为 1
        let bpp: UInt16, // 像素位数 (1,4,8,16,24,32)
        let compression: UInt32, // 压缩方式 (0=BI_RGB 无压缩)
        let imageSize: UInt32, // 位图数据大小 (可设为0)
        let xpelsPerMeter: UInt32,
        let ypelsPerMeter: UInt32,
        let colorUsed: Int64, // 实际使用的颜色表中的颜色数 (0=使用全部)
        let colorImportant: Int64 // 重要颜色数 (0=全部重要)
    ) {}
}

class BinReader {
    private let r: InputStream
    private let tempbuf = Array<Byte>(4, repeat: 0)
    private var pos: Int64 = 0

    init(r: InputStream) {
        this.r = r
    }

    func readU16(): UInt16 {
        r.read(tempbuf[..2])
        let v = UInt16.readLittleEndian(tempbuf)
        pos += 2
        v
    }

    func readU32(): UInt32 {
        r.read(tempbuf)
        let v = UInt32.readLittleEndian(tempbuf)
        pos += 4
        v
    }

    func readI32(): Int32 {
        r.read(tempbuf)
        let v = Int32.readLittleEndian(tempbuf)
        pos += 4
        v
    }

    func readBytes(n: Int64): Array<Byte> {
        let b = Array<Byte>(n, repeat: 0)
        pos += n
        r.read(b)
        b
    }

    func postion(): Int64 {
        pos
    }
}


class BinWriter {
    private let w: OutputStream
    private let tempbuf = Array<Byte>(4, repeat: 0)
    private var pos: Int64 = 0

    init(w:OutputStream){
        this.w = w
    }

    func write(v:UInt16) {
        v.writeLittleEndian(tempbuf[..2])
        w.write(tempbuf[..2])
        pos+=2
    }

    func write(v:UInt32) {
        v.writeLittleEndian(tempbuf)
        w.write(tempbuf)
        pos+=4
    }

    func write(b:Array<Byte>){
        w.write(b)
        pos+=b.size
    }

    func postion(): Int64 {
        pos
    }
}
