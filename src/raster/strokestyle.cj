package pixo.raster

import std.math.{atan2, sin, cos, abs}

// 连接样式
public enum JoinStyle {
    | Bevel
    | Round
    | Miter(Float64) // miter-limit

    // p: 路径顶点
    // anorm: 上一段路径的法向量
    // bnorm: 当前段路径的法向量
    func call(lhs: Pathable, rhs: Pathable, p: Point26_6, anorm: Point26_6, bnorm: Point26_6): Unit {
        match (this) {
            case Bevel =>
                lhs.lineTo(p + bnorm)
                rhs.lineTo(p - bnorm)
            case Round =>
                let dot = anorm.roate90cw().dot(bnorm)
                if (dot >= 0) {
                    addArc(p, anorm, bnorm) {s => lhs.lineTo(s)}
                    rhs.lineTo(p - bnorm)
                } else {
                    lhs.lineTo(p + bnorm)
                    addArc(p, anorm.neg(), bnorm.neg()) {s => rhs.lineTo(s)}
                }
            case Miter(limit) =>
                let dot = anorm.roate90cw().dot(bnorm)
                if (dot >= 0) {
                    addMiter(p, anorm, bnorm, limit) {s => lhs.lineTo(s)}
                    rhs.lineTo(p - bnorm)
                } else {
                    lhs.lineTo(p + bnorm)
                    addMiter(p, anorm.neg(), bnorm.neg(), limit) {s => rhs.lineTo(s)}
                }
        }
    }
}

// 端点样式
public enum CapStyle {
    | Butt
    | Square
    | Round

    // a: 上一段路径的顶点
    // b: 当前段路径的顶点
    func call(hs: Pathable, a: Point26_6, b: Point26_6) {
        match (this) {
            case Butt => hs.lineTo(a + b)
            case Square =>
                let side = a + b.roate90ccw()
                hs.lineTo(side - b)
                hs.lineTo(side + b)
                hs.lineTo(a + b)
            case Round =>
                let e = b.roate90ccw()
                let side = a + e
                let start = a - b
                let end = a + b
                let d = b * 35
                let x = e * 35
                hs.cubicTo(start + e, side - d, side)
                hs.cubicTo(side + d, end + x, end)
        }
    }
}

public class DashStyle {
    public DashStyle(
        let list: Array<Int64>,
        let offset!: Int64 = 0
    ) {}
}




func addMiter(p: Point26_6, anorm: Point26_6, bnorm: Point26_6, limit: Float64, lineCb: (Point26_6) -> Unit) {
    let r2 = anorm.dot(anorm)
    if (r2 == 0) {
        lineCb(p + bnorm)
        return
    }
    let dot = anorm.dot(bnorm)
    let denorm = r2 + dot
    // 计算阈值 threshold = r^2 / (2 * limit^2)
    // 根据svg标准 小于1.0倍数 则限制为1.0
    let mlimit = max(limit, 1.0)
    let limitFactor = 2.0 * mlimit * mlimit
    if (Int64(Float64(denorm) * limitFactor) < r2) {
        lineCb(p + bnorm)
        return
    }
    // 计算尖角顶点
    let sumvec = anorm + bnorm
    let scale = Int32((r2 << 6) / denorm)
    let v = sumvec * scale
    lineCb(p + v)
    lineCb(p + bnorm)
}

func addArc(p: Point26_6, anorm: Point26_6, bnorm: Point26_6, lineCb: (Point26_6) -> Unit) {
    let r2 = anorm.dot(anorm)
    if (r2 < 1024) {
        // 半径平方阈值，小于该值直接画直线。
        lineCb(p + bnorm)
        return
    }
    // 计算旋转角度 totalAngle
    let totalAngle = atan2(Float64(anorm.cross(bnorm)), Float64(anorm.dot(bnorm)))
    let r = Float64(anorm.length()) / 64.0
    var segs = Int64(abs(totalAngle) * r / 2.0) + 1 // 每2.0像素弧长一个分段
    if (segs < 2) {
        segs = 2
    } else if (segs > 180) {
        segs = 180
    }

    // 预计算旋转矩阵参数
    let stepAngle = totalAngle / Float64(segs)
    let sinFix = Int32(sin(stepAngle) * 64.0)
    let cosFix = Int32(cos(stepAngle) * 64.0)

    var curr = anorm
    for (_ in 0..segs) {
        // 应用旋转矩阵:
        curr = Point26_6(
            (curr * cosFix).x - (curr * sinFix).y,
            (curr * sinFix).x + (curr * cosFix).y,
        )
        lineCb(p + curr)
    }
    // 6. 连接终点，消除累积误差
    lineCb(p + bnorm)
}