package pixo.raster

import std.math.sqrt

public class Fill <: Pathable{
    let s:Scan
    public init(w:Int64,h:Int64){
        s = Scan(w,h)
    }

    public func startTo(a:Point26_6){
        s.start(a)
    }

    public func lineTo(b:Point26_6){
        s.line(b)
    }

    public func quadTo(b:Point26_6,c:Point26_6){
        quadToFn(s.lastPoint,b,c,lineTo)
    }

    public func cubicTo(b:Point26_6,c:Point26_6,d:Point26_6){
        cubicToFn(s.lastPoint,b,c,d,lineTo)
    }

    public func draw(iface:Paintable){
        s.rasterize{ x:Int64,y:Int64,n:Int64,a:Int16 =>
            let ma = UInt8(min(UInt32(a)<<4,65535)>>8)
            iface.panit(x,y,n,ma)
        }
        iface.done()
        s.reset()
    }
}



func devSquared(x0: Float32, y0: Float32, x1: Float32, y1: Float32, x2: Float32, y2: Float32): Float32 {
    let devx = x0 - 2.0 * x1 + x2
    let devy = y0 - 2.0 * y1 + y2
    return devx * devx + devy * devy
}


// 辅助函数 二次贝塞尔曲线转直线段
// a 起点 b 控制点 c 终点
func quadToFn(a: Point26_6, b: Point26_6, c: Point26_6, lineCb: (Point26_6) -> Unit) {
    if(a == b || b == c){
        lineCb(c)
        return
    }
    let ax = Float32(a.x)
    let ay = Float32(a.y)
    let bx = Float32(b.x)
    let by = Float32(b.y)
    let cx = Float32(c.x)
    let cy = Float32(c.y)

    let devsq = devSquared(ax, ay, bx, by, cx, cy)
    if (devsq >= 0.333) {
        const tol: Float32 = 3.0
        let n = 1 + Int64(sqrt(sqrt(tol * devsq)))
        let nInv = 1.0 / Float32(n)
        var t: Float32 = 0.0
        for (_ in 0..n - 1) {
            t += nInv
            let mt = 1.0 - t
            let t1 = mt * mt
            let t2 = mt * t * 2.0
            let t3 = t * t
            lineCb(Point26_6(Int32(ax * t1 + bx * t2 + cx * t3), Int32(ay * t1 + by * t2 + cy * t3)))
        }
    }
    lineCb(c)
}


// 辅助函数 三次贝塞尔曲线转直线段
// a 起点 b,c 控制点 d 终点
func cubicToFn(a: Point26_6, b: Point26_6, c: Point26_6, d: Point26_6, lineCb: (Point26_6) -> Unit) {
     if((a == b && c == d) || (a == b && b == c) || (c == b && d == c)){
        lineCb(d)
        return
    }

    let ax = Float32(a.x)
    let ay = Float32(a.y)
    let bx = Float32(b.x)
    let by = Float32(b.y)
    let cx = Float32(c.x)
    let cy = Float32(c.y)
    let dx = Float32(d.x)
    let dy = Float32(d.y)

    let devsq = max(
        devSquared(ax, ay, bx, by, dx, dy),
        devSquared(ax, ay, cx, cy, dx, dy),
    )
    if (devsq >= 0.333) {
        const tol: Float32 = 3.0
        let n = 1 + Int64(sqrt(sqrt(tol * devsq)))
        let nInv = 1.0 / Float32(n)
        var t: Float32 = 0.0
        for (_ in 0..n - 1) {
            t += nInv
            let mt = 1.0 - t
            let t1 = mt * mt * mt
            let t2 = mt * mt * t * 3.0
            let t3 = mt * t * t * 3.0
            let t4 = t * t * t
            lineCb(
                Point26_6(
                    Int32(ax * t1 + bx * t2 + cx * t3 + dx * t4),
                    Int32(ay * t1 + by * t2 + cy * t3 + dy * t4),
                )
            )
        }
    }
    lineCb(d)
}
