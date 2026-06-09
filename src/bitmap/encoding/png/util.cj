package pixo.bitmap.encoding.png

import std.math.abs

let pngHeaderBytes: Array<Byte> = [137, 80, 78, 71, 13, 10, 26, 10]

enum PNGColorType {
    | Gray
    | RGB
    | Indexed
    | GrayAlpha
    | RGBA

    static func fromValue(t: UInt8): PNGColorType {
        match (t) {
            case 0 => Gray
            case 2 => RGB
            case 3 => Indexed
            case 4 => GrayAlpha
            case 6 => RGBA
            case _ => throw Exception("png:error colortype")
        }
    }
    func toValue(): UInt8 {
        match (this) {
            case Gray => 0
            case RGB => 2
            case Indexed => 3
            case GrayAlpha => 4
            case RGBA => 6
        }
    }
}

public struct PNGConfig <: ToString {
    PNGConfig(
        let width: Int64,
        let height: Int64,
        let bitDepth: UInt8,
        let colorType: PNGColorType,
        let compressionMethod: UInt8,
        let filterMethod: UInt8,
        let interlaceMethod: UInt8
    ) {}

    public func toString(): String {
        let b = StringBuilder()
        b.append("width = ${width}\n")
        b.append("height = ${height}\n")
        b.append("bitDepth = ${bitDepth}\n")
        b.append("colorType = ${colorType.toValue()}\n")
        b.append("compressionMethod = ${compressionMethod}\n")
        b.append("filterMethod = ${filterMethod}\n")
        b.append("interlaceMethod = ${interlaceMethod}\n")
        b.toString()
    }
}

let adam7Passes = [
    // startRow, startCol, rowStep, colStep
    [0, 0, 8, 8],
    [0, 4, 8, 8],
    [4, 0, 8, 4],
    [0, 2, 4, 4],
    [2, 0, 4, 2],
    [0, 1, 2, 2],
    [1, 0, 2, 1]
]

// paethPredictor 实现 Paeth 预测函数
func paethPredictor(a: UInt8, b: UInt8, c: UInt8): UInt8 {
    let p = Int64(a) + Int64(b) - Int64(c)

    let pa = abs(p - Int64(a))
    let pb = abs(p - Int64(b))
    let pc = abs(p - Int64(c))

    if (pa <= pb && pa <= pc) {
        a
    } else if (pb <= pc) {
        b
    } else {
        c
    }
}

@OverflowWrapping
func filterPaeth(ft: UInt8, cdata: Array<Byte>, pdata: Array<Byte>, i: Int64, bpp: Int64): UInt8 {
    let a: UInt8 = if (i - bpp >= 0) {
        cdata[i - bpp]
    } else {
        0
    }
    let b: UInt8 = pdata[i]
    let c: UInt8 = if (i - bpp >= 0) {
        pdata[i - bpp]
    } else {
        0
    }
    match (ft) {
        case 0 => 0
        case 1 => a
        case 2 => b
        case 3 => UInt8((UInt16(a) + UInt16(b)) / 2)
        case 4 => paethPredictor(a, b, c)
        case _ => throw Exception("png: filterType ${ft} unsupport")
    }
}

// samplesPerPixel 返回颜色类型对应的采样通道数（不含填充位）
func samplesPerPixel(ct: PNGColorType): Int64 {
    match (ct) {
        case Gray => 1
        case RGB => 3
        case Indexed => 1
        case GrayAlpha => 2
        case RGBA => 4
    }
}

// calcFilterBpp 计算滤波器用的每像素字节数
// PNG 规范规定：
//   - 对于位深度 < 8，bpp 等于颜色类型的基准 bpp（灰度/索引为1，灰度+Alpha为2）
//   - 对于位深度 = 8 或 16，bpp = 基准bpp * (位深度/8)
func calcFilterBpp(ct: PNGColorType, bitDepth: UInt8): Int64 {
    let base = samplesPerPixel(ct)
    if (bitDepth < 8) {
        // 小于8位时，bpp 仍为 base（通常为1或2），像素打包不影响滤波器
        base
    } else {
        // 8 位或 16 位，直接乘以 (bitDepth/8)
        base * Int64(bitDepth / 8)
    }
}

class Crc32IEEE {
    static let table = Array<UInt32>(256, repeat: 0)

    @OverflowWrapping
    static init() {
        let poly = UInt32(0xEDB88320)
        for (i in 0..256) {
            var crc = UInt32(i)
            for (_ in 0..8) {
                crc = if ((crc & 1) == 1) {
                    (crc >> 1) ^ poly
                } else {
                    crc >> 1
                }
            }
            table[i] = crc
        }
    }
    var crc: UInt32 = UInt32(0xFFFFFFFF)

    @OverflowWrapping
    func write(data: Array<Byte>) {
        for (b in data) {
            crc = (crc >> 8) ^ table[Int64(UInt8(crc) ^ b)]
        }
    }

    func sum(): UInt32 {
        crc ^ 0xFFFFFFFF
    }

    func reset() {
        crc = UInt32(0xFFFFFFFF)
    }
}