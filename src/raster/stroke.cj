package pixo.raster

import std.math.sqrt

public class Stroke {
    let lhs: Fill
    // 反方向存储的路径
    let rhs = Path()
    var startP = Point26_6() // 起始点
    var startNorm = Point26_6() // 起始法向量 用于闭合连接
    var a = Point26_6() // 当前点
    var anorm = Point26_6() // 当前路径的法向量

    // 实线设置
    var u: Int26_6 = 0 // 半径 线宽的一半
    var join = JoinStyle.Miter(4.0)
    var cap = CapStyle.Butt

    // 虚线数组
    var dash: DashStyle = DashStyle()
    var dashArr: Array<Int26_6> = []
    // 当前在虚线数组中的哪个位置
    var dashArrIndex: Int64 = 0
    // 当前相当于dashArr[0]的偏移
    var dashDelta: Int26_6 = 0

    public init(r: Fill) {
        lhs = r
    }

    public func setWidth(w: Int26_6) {
        u = w / 2
    }

    public func setJoin(s: JoinStyle) {
        join = s
    }

    public func setCap(c: CapStyle) {
        cap = c
    }

    public func setDash(d: DashStyle) {
        dash = d
    }

    public func startTo(a: Point26_6): Unit {
        this.a = a
        this.startP = a
        dashArr = dash.list.map({v => Int32(v << 6)})
        dashDelta = Int32(dash.offset) << 6
        dashArrIndex = 0
    }

    func dashLinePart(b: Point26_6, bnorm: Point26_6, closedPart: Bool) {
        // 偶数实线 奇数空白
        if (dashArrIndex % 2 == 0) {
            if (rhs.size == 0) {
                lhs.startTo(a + bnorm)
                rhs.startTo(a - bnorm)
                startP = a
                // 闭合join使用
                startNorm = bnorm
            } else {
                join.call(lhs, rhs, a, anorm, bnorm)
            }
            lhs.lineTo(b + bnorm)
            rhs.lineTo(b - bnorm)
        }
        a = b
        anorm = bnorm
        if (closedPart) {
            // 本段线段结束
            stop()
        }
    }

    func dashLineTo(b: Point26_6): Unit {
        let ba = b - a
        var seglen = ba.length()
        let bnorm = ba.normalize(u).roate90ccw()
        var nlt: Int26_6 = 0
        let ca = a // 复制a 后续会用到 不然while里会不停的重置a
        while (dashDelta + seglen > dashArr[dashArrIndex]) {
            // 当前段的起始位置
            let n1 = dashArr[dashArrIndex] - dashDelta
            nlt += n1
            dashLinePart(ca + ba.normalize(nlt), bnorm, true)
            seglen -= n1
            dashDelta = 0
            dashArrIndex++
            if (dashArrIndex == dashArr.size) {
                dashArrIndex = 0
            }
        }
        dashDelta += seglen
        dashLinePart(b, bnorm, false)
    }

    public func lineTo(b: Point26_6): Unit {
        if (a == b) {
            return
        }
        if (dashArr.size > 0) {
            dashLineTo(b)
            return
        }
        let bnorm = (b - a).normalize(u).roate90ccw()
        if (rhs.size == 0) {
            lhs.startTo(a + bnorm)
            rhs.startTo(a - bnorm)
            // 闭合join使用
            startNorm = bnorm
        } else {
            join.call(lhs, rhs, a, anorm, bnorm)
        }
        lhs.lineTo(b + bnorm)
        rhs.lineTo(b - bnorm)
        a = b
        anorm = bnorm
    }

    public func quadTo(b: Point26_6, c: Point26_6): Unit {
        quadToFn(a, b, c, lineTo)
    }

    public func cubicTo(b: Point26_6, c: Point26_6, d: Point26_6): Unit {
        cubicToFn(a, b, c, d, lineTo)
    }

    func stop() {
        if (rhs.size == 0) {
            return
        }
        if (startP == a) {
            // closed
            addRightPath()
            // 连接起始点
            join.call(lhs, rhs, a, anorm, startNorm)
        } else {
            // open
            let rightStartP = Point26_6(rhs[1], rhs[2])
            cap.call(lhs, a, anorm.neg())
            addRightPath()
            cap.call(lhs, startP, startP - rightStartP)
        }
        // 清空以便下次使用
        rhs.clear()
    }

    public func draw(iface: Paintable) {
        stop()
        lhs.draw(iface)
    }

    func addRightPath() {
        var i = rhs.size - 1
        while (true) {
            match (rhs[i]) {
                case 0 => return
                case 1 =>
                    i -= 4
                    lhs.lineTo(Point26_6(rhs[i - 2], rhs[i - 1]))
                case 2 =>
                    i -= 6
                    lhs.quadTo(
                        Point26_6(rhs[i + 2], rhs[i + 3]),
                        Point26_6(rhs[i - 2], rhs[i - 1])
                    )
                case 3 =>
                    i -= 8
                    lhs.cubicTo(
                        Point26_6(rhs[i + 4], rhs[i + 5]),
                        Point26_6(rhs[i + 2], rhs[i + 3]),
                        Point26_6(rhs[i - 2], rhs[i - 1]),
                    )
                case _ => return
            }
        }
    }
}

// 添加一些stroke使用的辅助方法
extend Point26_6 {
    // 点积
    func dot(p: Point26_6): Int64 {
        Int64(x * p.x) + Int64(y * p.y)
    }

    // 叉积
    func cross(p: Point26_6): Int64 {
        Int64(x * p.y) - Int64(y * p.x)
    }

    // 反转180度
    func neg(): Point26_6 {
        Point26_6(-x, -y)
    }

    // 顺时针90度(y轴向下)
    func roate90cw(): Point26_6 {
        Point26_6(-y, x)
    }

    // 逆时针90度(y轴向下)
    func roate90ccw(): Point26_6 {
        Point26_6(y, -x)
    }

    func length(): Int26_6 {
        let xf = Float64(x)
        let yf = Float64(y)
        Int32(sqrt(xf * xf + yf * yf))
    }

    // 给定长度进行归一化
    func normalize(n: Int26_6): Point26_6 {
        let d = length()
        if (d == 0) {
            Point26_6()
        } else {
            Point26_6(
                x * n / d,
                y * n / d
            )
        }
    }
}
