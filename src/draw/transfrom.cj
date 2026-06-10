package pixo.draw

import std.math.{abs, sin, floor}
import std.runtime.getProcessorCount
import pixo.geom.{Matrix, Rect}
import pixo.bitmap.Bitmap
import pixo.color.*

// 抗锯齿采样滤波
public enum InterpMode {
    | Nearest
    | BiLiner
    | BiCubic
    | MitchellNetravali
    | Lanczos

    func radius(): Int64 {
        match (this) {
            case Nearest => 0
            case BiLiner => 1
            case BiCubic => 2
            case MitchellNetravali => 2
            case Lanczos => 3
        }
    }

    func kernel(v: Float64): Float64 {
        match (this) {
            case Nearest =>
                if (v >= -0.5 && v < 0.5) {
                    1.0
                } else {
                    0.0
                }
            case BiLiner =>
                let x = abs(v)
                if (x < 1.0) {
                    1.0 - x
                } else {
                    0.0
                }
            case BiCubic =>
                let x = abs(v)
                if (x <= 1.0) {
                    x * x * (1.5 * x - 2.5) + 1.0
                } else if (x <= 2.0) {
                    x * (x * (2.5 - 0.5 * x) - 4.0) + 2.0
                } else {
                    0.0
                }
            case MitchellNetravali =>
                let x = abs(v)
                if (x <= 2.0) {
                    bcspline(x, 1.0 / 3.0, 1.0 / 3.0)
                } else {
                    0.0
                }
            case Lanczos =>
                let x = abs(v)
                if (x <= 3.0) {
                    sinc(x) * sinc(x / 3.0)
                } else {
                    0.0
                }
        }
    }
}

// 将src按指定矩阵变换写入dst
// Op.Over 仅当dst和src的colortype都是rgba时有效
public func transform(dst: Bitmap, src: Bitmap, m: Matrix, mode!: InterpMode = InterpMode.BiLiner, op!: Op = Op.Over) {
    let srcbox = src.rect()
    var dstbox = dst.rect().intersect(m.transformRect(srcbox))
    let inv = m.invert()
    let dr = inv.transformRect(dstbox)
    dstbox = dstbox.sub(dr.x0, dr.y0)
    dstbox = dstbox.intersect(dst.rect())
    match (mode) {
        case Nearest => nearestTransform(dst, src, dstbox, srcbox, inv, op)
        case _ => sampleTransform(dst, src, dstbox, srcbox, inv, mode, op)
    }
}

func nearestTransform(dst: Bitmap, src: Bitmap, dr: Rect, sr: Rect, m: Matrix, op: Op) {
    let rgba = dst.colorType == src.colorType && dst.colorType == ColorType.RGBA
    parallel(dr.y0, dr.y1) {
        start, end => for (y in start..end) {
            let yf = Float64(y) + 0.5
            for (x in dr.x0..dr.x1) {
                let xf = Float64(x) + 0.5
                let dx = Int64(m.a * xf + m.c * yf + m.e)
                let dy = Int64(m.b * xf + m.d * yf + m.f)
                if (!sr.contains(dx, dy)) {
                    continue
                }
                if (!rgba) {
                    dst.setColor(x, y, src.getColor(dy, dy))
                    continue
                }
                let srco = src.pixelsOffset(dx, dy)
                let dsto = dst.pixelsOffset(x, y)
                match (op) {
                    case Src => src.pixels[srco..srco + 4].copyTo(dst.pixels[dsto..dsto + 4])
                    case Over => blendOver(
                        dst.pixels[dsto..dsto + 4],
                        src.pixels[srco + 0],
                        src.pixels[srco + 1],
                        src.pixels[srco + 2],
                        src.pixels[srco + 3],
                    )
                }
            }
        }
    }
}

func sampleTransform(dst: Bitmap, src: Bitmap, dr: Rect, sr: Rect, m: Matrix, mode: InterpMode, op: Op) {
    let radius = mode.radius()
    let kernel = mode.kernel
    let rgba = dst.colorType == src.colorType && dst.colorType == ColorType.RGBA
    parallel(dr.y0, dr.y1) {
        start, end =>
            // 预计算水平/垂直权重
            let wx = Array<Float64>(radius * 2, repeat: 0.0)
            let wy = Array<Float64>(radius * 2, repeat: 0.0)
            // 当前采样的颜色
            let px = Array<Float64>(src.spp, repeat: 0.0)
            for (y in start..end) {
                for (x in dr.x0..dr.x1) {
                    let (sx, sy) = m.transformPoint(Float64(x), Float64(y))
                    let x0 = Int64(floor(sx))
                    let y0 = Int64(floor(sy))
                    if (!sr.contains(x0, y0)) {
                        continue
                    }

                    let dx = sx - Float64(x0)
                    let dy = sy - Float64(y0)

                    for (i in 0..radius * 2) {
                        let offset = Float64(i - radius + 1)
                        wx[i] = kernel(offset - dx)
                        wy[i] = kernel(offset - dy)
                    }
                    px.fill(0.0)
                    for (j in 0..radius * 2) {
                        let ty = y0 - radius + 1 + j
                        for (i in 0..radius * 2) {
                            let w = wx[i] * wy[j]
                            if (w == 0.0) {
                                continue
                            }
                            let tx = x0 - radius + 1 + i
                            if (!sr.contains(tx, ty)) {
                                continue
                            }
                            let offset = src.pixelsOffset(tx, ty)
                            for (k in 0..src.spp) {
                                px[k] += w * Float64(src.pixels[offset + k])
                            }
                        }
                    }
                    if (!rgba) {
                        let c = match (src.colorType) {
                            case ColorType.Gray => Color.Gray(clampf(px[0]))
                            case ColorType.RGBA => Color.RGBA(clampf(px[0]), clampf(px[1]), clampf(px[2]), clampf(px[3]))
                        }
                        dst.setColor(x, y, c)
                        continue
                    }
                    let dstOffset = dst.pixelsOffset(x, y)
                    match (op) {
                        case Src =>
                            dst.pixels[dstOffset + 0] = clampf(px[0])
                            dst.pixels[dstOffset + 1] = clampf(px[1])
                            dst.pixels[dstOffset + 2] = clampf(px[2])
                            dst.pixels[dstOffset + 3] = clampf(px[3])
                        case Over => blendOver(
                            dst.pixels[dstOffset..dstOffset + 4],
                            clampf(px[0]),
                            clampf(px[1]),
                            clampf(px[2]),
                            clampf(px[3]),
                        )
                    }
                }
            }
    }
}

// 按y轴批量处理
func parallel(start: Int64, end: Int64, cb: (Int64, Int64) -> Unit) {
    let h = end - start
    if (h <= 0) {
        return
    }
    let pcnt = getProcessorCount()
    if (h < 10 * pcnt || pcnt == 1) {
        cb(start, end)
        return
    }
    // 每个worker处理多少行
    let rowsPerWorker = h / pcnt
    let go = Array(pcnt, {_ => unsafe { zeroValue<Future<Unit>>() }})

    for (i in 0..pcnt) {
        let ss = i * rowsPerWorker
        let se = if (i + 1 == pcnt) {
            h
        } else {
            ss + rowsPerWorker
        }
        go[i] = spawn {
            cb(start + ss, start + se)
        }
    }

    for (g in go) {
        g.get()
    }
}

func bcspline(x: Float64, b: Float64, c: Float64): Float64 {
    if (x < 1.0) {
        ((12.0 - 9.0 * b - 6.0 * c) * x * x * x + (-18.0 + 12.0 * b + 6.0 * c) * x * x + (6.0 - 2.0 * b)) / 6.0
    } else if (x < 2.0) {
        ((-b - 6.0 * c) * x * x * x + (6.0 * b + 30.0 * c) * x * x + (-12.0 * b - 48.0 * c) * x + (8.0 * b + 24.0 * c)) /
            6.0
    } else {
        0.0
    }
}

const PI = 3.14159265358979323846264338327

func sinc(x: Float64): Float64 {
    if (x == 0.0) {
        1.0
    } else {
        sin(PI * x) / (PI * x)
    }
}

func clampf(v: Float64): UInt8 {
    if (v < 0.0) {
        0
    } else if (v > 255.0) {
        255
    } else {
        UInt8(v)
    }
}
