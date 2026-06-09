package pixo.bitmap.encoding.jpeg

import std.io.{InputStream,OutputStream}
import std.binary.BigEndianOrder
import std.collection.ArrayStack

func clamp(x:Int32):UInt8 {
	if(x<0){
		return 0
	}
	if(x > 255){
		return 255
	}
	return UInt8(x)
}

func rgb2ycbcr(r:UInt8,g:UInt8,b:UInt8):(Int32,Int32,Int32){
    let y = (19595*Int32(r) + 38470*Int32(g) + 7471*Int32(b) + 32768) >> 16
	let cb = (-11056*Int32(r) - 21712*Int32(g) + 32768*Int32(b) + 32768) >> 16
    let cr = (32768*Int32(r) - 27440*Int32(g) - 5328*Int32(b) + 32768) >> 16
    (y,cb,cr)
}

func ycbcr2rgb(y:Int32,cb:Int32,cr:Int32):(UInt8,UInt8,UInt8){
    let r = y + ((1402 * cr) >> 10)
    let g = y - ((344 * cb) >> 10) - ((714 * cr) >> 10)
    let b = y + ((1772 * cb) >> 10)
    (
        clamp(r),
        clamp(g),
        clamp(b),
    )
}


func cmyk2rgb(c:Int32,m:Int32,y:Int32,k:Int32):(UInt8,UInt8,UInt8){
    let r= 255 * (255 - c) * (255 - k) / 65025
    let g= 255 * (255 - m) * (255 - k) / 65025
    let b= 255 * (255 - y) * (255 - k) / 65025
    (
        UInt8(r),
        UInt8(g),
        UInt8(b),
    )
}

let unzig = [
    0, 1, 8, 16, 9, 2, 3, 10,
    17, 24, 32, 25, 18, 11, 4, 5,
    12, 19, 26, 33, 40, 48, 41, 34,
    27, 20, 13, 6, 7, 14, 21, 28,
    35, 42, 49, 56, 57, 50, 43, 36,
    29, 22, 15, 23, 30, 37, 44, 51,
    58, 59, 52, 45, 38, 31, 39, 46,
    53, 60, 61, 54, 47, 55, 62, 63,
]

class BitReader {
    let r: InputStream
    var a: UInt32 = 0 // 比特缓冲（高位在前）
    var n: Int64 = 0 //  缓冲中剩余比特数
    let unReadByteStack = ArrayStack<Byte>(2) //用于存放因标记而推回的字节（最多 2 个）
    let buf: Array<Byte>

    init(r: InputStream, bufsize: Int64) {
        this.r = r
        this.buf = Array<Byte>(bufsize, repeat: 0)
    }

    func reset() {
        a = 0
        n = 0
        unReadByteStack.clear()
    }

    func read(arr: Array<Byte>): Int64 {
        r.read(arr)
    }

    func readByte(): Byte {
        if (let Some(b) <- unReadByteStack.remove()) {
            return b
        }
        let n = r.read(buf[..1])
        if (n == 1) {
            return buf[0]
        }
        throw Exception("jpeg: read byte eof")
    }

    func unReadByte(b: Byte) {
        unReadByteStack.add(b)
    }

    // 优先使用内部buf 除非buf长度不够
    func readNBytes(n: Int64): Array<Byte> {
        if (n > buf.size) {
            let bigBuf = Array<Byte>(n, repeat: 0)
            let l = r.read(bigBuf)
            bigBuf[..l]
        } else {
            let l = r.read(buf[..n])
            buf[..l]
        }
    }

    func readU16(): UInt16 {
        r.read(buf[..2])
        UInt16.readBigEndian(buf[..2])
    }

    func ignore(n: Int64) {
        var i = n
        while (i >= buf.size) {
            r.read(buf)
            i -= buf.size
        }
        if (i > 0) {
            r.read(buf[..i])
        }
    }

    // fillBits 确保缓冲中至少有 t 个比特
    func fillBits(t: Int64) {
        while (n < t) {
            let b = readByteStuffed().getOrThrow()
            a = (a << 8) | UInt32(b)
            n += 8
        }
    }

    func tryFillBits(t: Int64): Bool {
        while (n < t) {
            if (let Some(b) <- readByteStuffed()) {
                a = (a << 8) | UInt32(b)
                n += 8
            } else {
                return false
            }
        }
        true
    }

    func peekBits(t: Int64): UInt32 {
        fillBits(t)
        var v = UInt32(a >> (n - t))
        if (t > 16) {
            v &= (1 << t) - 1
        }
        v
    }

    func consumeBits(t: Int64) {
        n -= t
        a &= (1 << n) - 1
    }

    // readBits 读取 t 个比特
    func readBits(t: Int64): UInt32 {
        if (t <= 0) {
            return 0
        }
        let v = peekBits(t)
        consumeBits(t)
        v
    }

    @OverflowWrapping
    func receiveExtend(t: UInt8): Int32 {
        if (t == 0) {
            return 0
        }
        let v = readBits(Int64(t))
        if ((v >> (t - 1)) == 1) {
            Int32(v)
        } else {
            Int32(v - (1 << t) + 1)
        }
    }

    // readByteStuffed 读取一个数据字节，处理 0xFF 转义
    func readByteStuffed(): ?Byte {
        let b = readByte()
        if (b != 0XFF) {
            return b
        }
        let nextb = readByte()
        if (nextb == 0x00) {
            return b
        }
        // 遇到其他marker
        unReadByte(nextb)
        unReadByte(0xFF)
        None
    }
}


class BitWriter{
    let w:OutputStream
    let buf = Array<Byte>(16,repeat:0)
    var a:Byte = 0
    var n:Int64 = 0
    init(w:OutputStream){
        this.w = w
    }

    func writeByte(b:Byte){
        buf[0] = b
        let n = if(b==0xff){
            buf[1]=0x00
            2
        }else{
            1
        }
        w.write(buf[..n])
    }

    func writeBits(code:UInt32,nbits:Int64){
        var i = nbits
        while(i>0){
            if(n==0){
                writeByte(a)
                a = 0
                n = 0
            }
            i--
            let bit = (code>>i) & 1
            a |= UInt8(bit) << (7-n)
            n++
        }
    }

    func flush(){
        if(n>0){
            writeByte(a)
        }
    }

    func writeU16(v:UInt16){
        v.writeBigEndian(buf)
        w.write(buf[..2])
    }


}