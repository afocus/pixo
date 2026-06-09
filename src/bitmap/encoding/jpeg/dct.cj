package pixo.bitmap.encoding.jpeg


const cos1: UInt64 = 1130768441178740757 // fix cos 1*pi/16
const sin1: UInt64 = 224923827593068887 // fix sin 1*pi/16
const cos3: UInt64 = 958619196450722178 // fix cos 3*pi/16
const sin3: UInt64 = 640528868967736374 // fix sin 3*pi/16
const sqrt2: UInt64 = 1630477228166597777 // fix sqrt 2
const sqrt2_cos6: UInt64 = 623956622067911264 // fix (sqrt 2)*cos 6*pi/16
const sqrt2_sin6: UInt64 = 1506364539328854985 // fix (sqrt 2)*sin 6*pi/16
const sqrt2inv: UInt64 = 815238614083298888 // fix 1/sqrt 2
const sqrt2inv_cos6: UInt64 = 311978311033955632 // fix (1/sqrt 2)*cos 6*pi/16
const sqrt2inv_sin6: UInt64 = 753182269664427492 // fix (1/sqrt 2)*sin 6*pi/16

@OverflowWrapping
func dctBox(x0: Int32, x1: Int32, kcos: Int32, ksin: Int32): (Int32, Int32) {
    let ksum = kcos * (x0 + x1)
    (ksum + (ksin - kcos) * x1, ksum - (kcos + ksin) * x0)
}

func c(x: UInt64, bits: Int64): Int32 {
    Int32((x + (1 << (59 - bits))) >> (60 - bits))
}

func fdct(b: Array<Int32>) {
    fdctCols(b)
    fdctRows(b)
}

func idct(b: Array<Int32>) {
    idctRows(b)
    idctCols(b)
}

func fdctRows(b: Array<Int32>) {
    for (i in 0..8) {
        let x = b[8 * i..8 * i + 8]
        var x0 = x[0]
        var x1 = x[1]
        var x2 = x[2]
        var x3 = x[3]
        var x4 = x[4]
        var x5 = x[5]
        var x6 = x[6]
        var x7 = x[7]

        (x0, x7) = (x0 + x7, x0 - x7)
        (x1, x6) = (x1 + x6, x1 - x6)
        (x2, x5) = (x2 + x5, x2 - x5)
        (x3, x4) = (x3 + x4, x3 - x4)

        (x4, x7) = dctBox(x4 >> 14, x7 >> 14, c(cos3, 14), c(sin3, 14))
        (x5, x6) = dctBox(x5 >> 14, x6 >> 14, c(cos1, 14), c(sin1, 14))

        (x0, x3) = (x0 + x3, x0 - x3)
        (x1, x2) = (x1 + x2, x1 - x2)

        (x2, x3) = dctBox(x2 >> 14, x3 >> 14, c(sqrt2_cos6, 14), c(sqrt2_sin6, 14))

        (x0, x1) = (x0 + x1, x0 - x1)

        (x4, x6) = (x4 + x6, x4 - x6)
        (x7, x5) = (x7 + x5, x7 - x5)

        x5 = (x5 >> 14) * c(sqrt2, 14)
        x6 = (x6 >> 14) * c(sqrt2, 14)

        (x7, x4) = (x7 + x4, x7 - x4)

        x0 = (x0 + 1 << 17) >> 18
        x1 = (x1 + 1 << 17) >> 18
        x2 = (x2 + 1 << 17) >> 18
        x3 = (x3 + 1 << 17) >> 18
        x4 = (x4 + 1 << 17) >> 18
        x5 = (x5 + 1 << 17) >> 18
        x6 = (x6 + 1 << 17) >> 18
        x7 = (x7 + 1 << 17) >> 18

        x[0] = x0
        x[1] = x7
        x[2] = x2
        x[3] = x5
        x[4] = x1
        x[5] = x6
        x[6] = x3
        x[7] = x4
    }
}

func fdctCols(b: Array<Int32>) {
    for (i in 0..8) {
        var x0 = b[0 * 8 + i]
        var x1 = b[1 * 8 + i]
        var x2 = b[2 * 8 + i]
        var x3 = b[3 * 8 + i]
        var x4 = b[4 * 8 + i]
        var x5 = b[5 * 8 + i]
        var x6 = b[6 * 8 + i]
        var x7 = b[7 * 8 + i]

        (x0, x7) = (x0 + x7, x0 - x7)
        (x1, x6) = (x1 + x6, x1 - x6)
        (x2, x5) = (x2 + x5, x2 - x5)
        (x3, x4) = (x3 + x4, x3 - x4)

        (x4, x7) = dctBox(x4, x7, c(cos3, 18), c(sin3, 18))
        (x5, x6) = dctBox(x5, x6, c(cos1, 18), c(sin1, 18))

        (x0, x3) = (x0 + x3, x0 - x3)
        (x1, x2) = (x1 + x2, x1 - x2)

        (x2, x3) = dctBox(x2, x3, c(sqrt2_cos6, 18), c(sqrt2_sin6, 18))

        (x0, x1) = (x0 + x1, x0 - x1)

        b[0 * 8 + i] = (x0 - 128 * 8) << 18
        b[4 * 8 + i] = x1 << 18
        b[2 * 8 + i] = x2
        b[6 * 8 + i] = x3

        (x4, x6) = (x4 + x6, x4 - x6)
        (x7, x5) = (x7 + x5, x7 - x5)

        x5 = (x5 >> 12) * c(sqrt2, 12)
        x6 = (x6 >> 12) * c(sqrt2, 12)

        (x7, x4) = (x7 + x4, x7 - x4)

        b[1 * 8 + i] = x7
        b[3 * 8 + i] = x5
        b[5 * 8 + i] = x6
        b[7 * 8 + i] = x4
    }
}

@OverflowWrapping
func idctRows(b: Array<Int32>) {
    for (i in 0..8) {
        let x = b[8 * i..8 * i + 8]
        var x0 = x[0]
        var x7 = x[1]
        var x2 = x[2]
        var x5 = x[3]
        var x1 = x[4]
        var x6 = x[5]
        var x3 = x[6]
        var x4 = x[7]

        x0 <<= 17
        x1 <<= 17

        (x0, x1) = (x0 + x1, x0 - x1)

        (x2, x3) = dctBox(x2, x3, c(sqrt2inv_cos6, 18), -c(sqrt2inv_sin6, 18))

        (x1, x2) = (x1 + x2, x1 - x2)
        (x0, x3) = (x0 + x3, x0 - x3)

        x4 <<= 7
        x7 <<= 7

        (x7, x4) = (x7 + x4, x7 - x4)

        x6 = x6 * c(sqrt2inv, 8)
        x5 = x5 * c(sqrt2inv, 8)

        (x7, x5) = (x7 + x5, x7 - x5)
        (x4, x6) = (x4 + x6, x4 - x6)

        (x4, x7) = dctBox(x4 >> 2, x7 >> 2, c(cos3, 12), -c(sin3, 12))
        (x5, x6) = dctBox(x5 >> 2, x6 >> 2, c(cos1, 12), -c(sin1, 12))

        (x0, x7) = (x0 + x7, x0 - x7)
        (x1, x6) = (x1 + x6, x1 - x6)
        (x2, x5) = (x2 + x5, x2 - x5)
        (x3, x4) = (x3 + x4, x3 - x4)

        x[0] = x0
        x[1] = x1
        x[2] = x2
        x[3] = x3
        x[4] = x4
        x[5] = x5
        x[6] = x6
        x[7] = x7
    }
}

@OverflowWrapping
func idctCols(b: Array<Int32>) {
    for (i in 0..8) {
        var x0 = b[0 * 8 + i]
        var x7 = b[1 * 8 + i]
        var x2 = b[2 * 8 + i]
        var x5 = b[3 * 8 + i]
        var x1 = b[4 * 8 + i]
        var x6 = b[5 * 8 + i]
        var x3 = b[6 * 8 + i]
        var x4 = b[7 * 8 + i]

        x0 += 1 << 19

        (x0, x1) = ((x0 + x1) >> 2, (x0 - x1) >> 2)

        (x2, x3) = dctBox(x2 >> 13, x3 >> 13, c(sqrt2inv_cos6, 12), -c(sqrt2inv_sin6, 12))

        (x1, x2) = (x1 + x2, x1 - x2)
        (x0, x3) = (x0 + x3, x0 - x3)

        (x7, x4) = (x7 + x4, x7 - x4)

        x5 = (x5 >> 13) * c(sqrt2inv, 14)
        x6 = (x6 >> 13) * c(sqrt2inv, 14)

        (x7, x5) = (x7 + x5, x7 - x5)
        (x4, x6) = (x4 + x6, x4 - x6)

        (x4, x7) = dctBox(x4 >> 14, x7 >> 14, c(cos3, 12), -c(sin3, 12))
        (x5, x6) = dctBox(x5 >> 14, x6 >> 14, c(cos1, 12), -c(sin1, 12))

        (x0, x7) = (x0 + x7, x0 - x7)
        (x1, x6) = (x1 + x6, x1 - x6)
        (x2, x5) = (x2 + x5, x2 - x5)
        (x3, x4) = (x3 + x4, x3 - x4)

        x0 >>= 18
        x1 >>= 18
        x2 >>= 18
        x3 >>= 18
        x4 >>= 18
        x5 >>= 18
        x6 >>= 18
        x7 >>= 18

        b[0 * 8 + i] = x0
        b[1 * 8 + i] = x1
        b[2 * 8 + i] = x2
        b[3 * 8 + i] = x3
        b[4 * 8 + i] = x4
        b[5 * 8 + i] = x5
        b[6 * 8 + i] = x6
        b[7 * 8 + i] = x7
    }
}
