package pixo.font

import std.binary.BigEndianOrder

func u32(buf: Array<Byte>): UInt32 {
    UInt32.readBigEndian(buf)
}

func u16(buf: Array<Byte>): UInt16 {
    UInt16.readBigEndian(buf)
}

func i16(buf: Array<Byte>): Int16 {
    Int16.readBigEndian(buf)
}

class BinReader {
    let buf: Array<Byte>
    private var pos: Int64 = 0
    init(data: Array<Byte>) {
        buf = data
    }

    func readUInt8() {
        pos++
        buf[pos - 1]
    }


    func readInt8(){
        let v = Int8.readBigEndian(buf)
        pos++
        v
    }

    func readUInt16() {
        let v = u16(buf[pos..])
        pos += 2
        v
    }

    func readInt16() {
        let v = i16(buf[pos..])
        pos += 2
        v
    }

    func readUInt32(): UInt32 {
        let v = u32(buf[pos..])
        pos += 4
        v
    }

    func readBytes(length: Int64): Array<Byte> {
        let b = buf[pos..pos + length]
        pos += length
        b
    }

    func seek(offset: Int64) {
        pos = offset
    }

    func skip(offset: Int64) {
        pos += offset
    }

    func tell(): Int64 {
        pos
    }

    func size(): Int64 {
        buf.size
    }




    func getUInt8(offset: Int64): UInt8 {
        buf[offset]
    }

    func getUInt16(offset: Int64): UInt16 {
        u16(buf[offset..])
    }

    func getUInt32(offset: Int64): UInt32 {
        u32(buf[offset..])
    }

    func getBytes(offset: Int64, length: Int64): Array<Byte> {
        if (offset < 0 || offset > offset + length) {
            println("offset:${offset}, length:${length}")
            // throw InvalidBoundsException
        }
        if ((offset + length) > buf.size) {
            println("x:${offset + length}, bufsize:${buf.size}")
            // throw InvalidBoundsException
        }
        buf[offset..offset + length]
    }

    func subView(offset: Int64, length: Int64): BinReader {
        BinReader(getBytes(offset, length))
    }
}
