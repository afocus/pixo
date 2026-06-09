package pixo.geom

import std.math.{sin, cos}

// Matrix(a, b, c, d, e, f)
// 映射：
// x' = a*x + c*y + e
// y' = b*x + d*y + f
// 齐次坐标 3×3 矩阵：
// [ a, c, e ]
// [ b, d, f ]
// [ 0, 0, 1 ]
public struct Matrix <: ToString {
    Matrix(
        public let a: Float64,
        public let b: Float64,
        public let c: Float64,
        public let d: Float64,
        public let e: Float64,
        public let f: Float64
    ) {}

    public static func identity(): Matrix {
        Matrix(
            1.0,
            0.0,
            0.0,
            1.0,
            0.0,
            0.0,
        )
    }

    public static func translate(x: Float64, y: Float64): Matrix {
        Matrix(
            1.0,
            0.0,
            0.0,
            1.0,
            x,
            y,
        )
    }

    public static func scale(x: Float64, y: Float64): Matrix {
        Matrix(
            x,
            0.0,
            0.0,
            y,
            0.0,
            0.0,
        )
    }

    // 旋转矩阵（逆时针弧度为正）
    public static func rotate(angle: Float64): Matrix {
        let c = cos(angle)
        let s = sin(angle)
        Matrix(
            c,
            s,
            -c,
            c,
            0.0,
            0.0,
        )
    }

    public static func shear(x: Float64, y: Float64): Matrix {
        Matrix(
            1.0,
            y,
            x,
            1.0,
            0.0,
            0.0,
        )
    }

    // 矩阵乘法：this = this * other（先作用 other，再作用 this）
    public func multiply(other: Matrix): Matrix {
        Matrix(
            a * other.a + c * other.b,
            b * other.a + d * other.b,
            a * other.c + c * other.d,
            b * other.c + d * other.d,
            a * other.e + c * other.f + e,
            b * other.e + d * other.f + f,
        )
    }

    // 逆矩阵
    public func invert(): Matrix {
        let det = a * d - b * c
        let invDst = 1.0 / det
        Matrix(
            d * invDst,
            -b * invDst,
            -c * invDst,
            a * invDst,
            (c * f - d * e) * invDst,
            (b * e - a * f) * invDst,
        )
    }

    // 正向映射一个点
    public func transformPoint(x: Float64, y: Float64): (Float64, Float64) {
        (a * x + c * y + e, b * x + d * y + f)
    }

    // 映射矩形
    public func transformRect(rc: Rect): Rect {
        let ps = [
            (rc.x0, rc.y0),
            (rc.x1, rc.y0),
            (rc.x0, rc.y1),
            (rc.x1, rc.y1)
        ]
        var dst = Rect(0, 0, 0, 0)
        for (i in 0..4) {
            let (x, y) = transformPoint(Float64(ps[i][0]), Float64(ps[i][1]))
            let dx = Int64(x)
            let dy = Int64(y)
            if (dx < dst.x0) {
                dst.x0 = dx
            }
            if (dy < dst.y0) {
                dst.y0 = dy
            }
            if (dx > dst.x1) {
                dst.x1 = dx
            }
            if (dy > dst.y1) {
                dst.y1 = dy
            }
        }
        dst
    }

    public func translateTo(x: Float64, y: Float64): Matrix {
        Matrix.translate(x, y).multiply(this)
    }

    public func scaleTo(x: Float64, y: Float64): Matrix {
        Matrix.scale(x, y).multiply(this)
    }

    public func rotateTo(angle: Float64): Matrix {
        Matrix.rotate(angle).multiply(this)
    }

    public func shearTo(x: Float64, y: Float64): Matrix {
        Matrix.shear(x, y).multiply(this)
    }

    public func toString(): String {
        "matrix(${a},${b},${c},${d},${e},${f})"
    }
}
