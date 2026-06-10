package pixo.raster

import std.collection.ArrayList

// x,y 开始位置 n 重复次数 a 重叠透明度
type SpanFn = (x: Int64, y: Int64, n: Int64, a: Int16) -> Unit

struct Cell {
    Cell(var x: Int64, var y: Int64, var cover!: Int64 = 0, var area!: Int64 = 0) {}
}

struct Line {
    Line(let a: Point26_6, let b: Point26_6) {}
}

// CL-AA 抗锯齿算法
// 移植自 https://github.com/srwiley/scany
class Scan {
    let scanLinks = ArrayList<Cell>()
    let existcell = ArrayList<Array<Cell>>()

    var extends = Rectangle26_6()
    var firstP = Point26_6()
    var lastP = Point26_6()
    var width: Int64 = 0
    var height: Int64 = 0
    var inPath: Bool = false

    init(w: Int64, h: Int64) {
        clear(w, h)
    }

    func clear(w: Int64, h: Int64) {
        width = if (w < 0) {
            0
        } else {
            w
        }
        height = if (h < 0) {
            0
        } else {
            h
        }
        reset()
    }

    func reset(){
        scanLinks.clear()
        for (_ in 0..height) {
            scanLinks.add(Cell(-1, -1))
        }
        extends = Rectangle26_6(
            Point26_6(Int32.Max, Int32.Max),
            Point26_6(-Int32.Max, -Int32.Max)
        )
    }

    @OverflowWrapping
    func saveCell(x: Int64, y: Int64, cover: Int64, area: Int64) {
        if (cover == 0 || y < 0 || y >= height) {
            return
        }

        let (xx, areax) = if (x < 0) {
            (0, cover << 6)
        } else if (x >= width) {
            (width - 1, cover << 6)
        } else {
            (x, area)
        }

        var ic = y
        var icPrev = 0
        var cc = scanLinks[ic]

        while (cc.x < xx && cc.y != -1) {
            icPrev = ic
            ic = cc.y
            cc = scanLinks[ic]
        }

        match {
            case cc.x == xx =>
                var c = scanLinks[ic]
                c.area += areax
                c.cover += cover
                scanLinks[ic] = c
            case cc.y == -1 && cc.x < xx =>
                var c = scanLinks[ic]
                c.y = scanLinks.size
                scanLinks[ic] = c
                scanLinks.add(Cell(xx, -1, area: areax, cover: cover))
            case _ =>
                var c = scanLinks[icPrev]
                c.y = scanLinks.size
                scanLinks[icPrev] = c
                scanLinks.add(Cell(xx, ic, area: areax, cover: cover))
        }
    }

    @OverflowWrapping
    func sendVerticalLine(line: Line) {
        let x1 = Int64(line.a.x) >> 6
        var y1 = Int64(line.a.y) >> 6
        var y2 = Int64(line.b.y) >> 6
        let x1f2 = (Int64(line.a.x) - (x1 << 6)) * 2
        if (y1 == y2) {
            let cover = Int64(line.b.y - line.a.y)
            saveCell(x1, y1, cover, cover * x1f2)
            return
        }
        var y1f = Int64(line.a.y) - (y1 << 6)
        var y2f = Int64(line.b.y) - (y2 << 6)
        var flip = 1
        if (y2 < y1) {
            let tempy2 = y2
            let tempy2f = y2f
            y2 = y1
            y1 = tempy2
            y2f = y1f
            y1f = tempy2f
            flip = -1
        }
        var cover = (64 - y1f) * flip
        saveCell(x1, y1, cover, cover * x1f2)
        for (y in y1 + 1..y2) {
            cover = flip << 6
            saveCell(x1, y, cover, cover * x1f2)
        }
        cover = y2f * flip
        saveCell(x1, y2, cover, cover * x1f2)
    }

    @OverflowWrapping
    func sendEastLine(line: Line, dx: Int64, dy: Int64, flip: Int64) {
        let ax = Int64(line.a.x)
        let ay = Int64(line.a.y)
        let bx = Int64(line.b.x)
        let by = Int64(line.b.y)

        var cx = ax >> 6
        var cy = ay >> 6
        var fy1 = ay & (64 - 1)
        var fx1 = ax & (64 - 1)
        var yn = 64 + (cy << 6)
        var xn = 64 + (cx << 6)

        while (yn <= by && xn <= bx) {
            let xw = ax + (yn - ay) * dx / dy
            let yw = ay + (xn - ax) * dy / dx
            match {
                case xw == xn && yn == yw =>
                    let cover = (64 - fy1) * flip
                    saveCell(cx, cy, cover, cover * (64 + fx1))
                    yn += 64
                    xn += 64
                    cx++
                    cy++
                    fy1 = 0
                    fx1 = 0
                case yw > yn || xw < xn =>
                    let fx2 = xw - xn + 64
                    let cover = (64 - fy1) * flip
                    saveCell(cx, cy, cover, cover * (fx2 + fx1))
                    yn += 64
                    cy++
                    fx1 = fx2
                    fy1 = 0
                case _ =>
                    let fy2 = -yn + 64 + yw
                    let cover = (fy2 - fy1) * flip
                    saveCell(cx, cy, cover, cover * (64 + fx1))
                    xn += 64
                    cx++
                    fx1 = 0
                    fy1 = fy2
            }
        }
        if (yn <= by) {
            while (yn <= by) {
                let xw = ax + (yn - ay) * dx / dy
                let fx2 = xw - xn + 64
                let cover = (64 - fy1) * flip
                saveCell(cx, cy, cover, cover * (fx2 + fx1))
                yn += 64
                cy++
                fx1 = fx2
                fy1 = 0
            }
        } else {
            while (xn <= bx) {
                let yw = ay + (xn - ax) * dy / dx
                let fy2 = -yn + 64 + yw
                let cover = (fy2 - fy1) * flip
                saveCell(cx, cy, cover, cover * (64 + fx1))
                xn += 64
                cx++
                fx1 = 0
                fy1 = fy2
            }
        }
        let fx2 = bx & (64 - 1)
        let fy2 = by & (64 - 1)
        let cover = (fy2 - fy1) * flip
        saveCell(cx, cy, cover, cover * (fx2 + fx1))
    }

    @OverflowWrapping
    func sendWestLine(line: Line, dx: Int64, dy: Int64, flip: Int64) {
        let ax = Int64(line.a.x)
        let ay = Int64(line.a.y)
        let bx = Int64(line.b.x)
        let by = Int64(line.b.y)

        var cx = ax >> 6
        var cy = ay >> 6

        var fy1 = ay & (64 - 1)
        var fx1 = ax & (64 - 1)

        var yn = 64 + (cy << 6)
        var xn = cx << 6

        while (yn <= by && xn >= bx) {
            let xw = ax + (yn - ay) * dx / dy
            let yw = ay + (xn - ax) * dy / dx
            match {
                case xw == xn && yn == yw =>
                    let cover = (64 - fy1) * flip
                    saveCell(cx, cy, cover, cover * (fx1))
                    yn += 64
                    xn -= 64
                    cx--
                    cy++
                    fy1 = 0
                    fx1 = 64
                case yw > yn || xw > xn =>
                    let fx2 = xw - xn
                    let cover = (64 - fy1) * flip
                    saveCell(cx, cy, cover, cover * (fx2 + fx1))
                    yn += 64
                    cy++
                    fx1 = fx2
                    fy1 = 0
                case _ =>
                    let fy2 = -yn + 64 + yw
                    let cover = (fy2 - fy1) * flip
                    saveCell(cx, cy, cover, cover * (fx1))
                    xn -= 64
                    cx--
                    fx1 = 64
                    fy1 = fy2
            }
        }
        if (yn <= by) {
            while (yn <= by) {
                let xw = ax + (yn - ay) * dx / dy
                let fx2 = xw - xn
                let cover = (64 - fy1) * flip
                saveCell(cx, cy, cover, cover * (fx2 + fx1))
                yn += 64
                cy++
                fx1 = fx2
                fy1 = 0
            }
        } else {
            while (xn >= bx) {
                let yw = ay + (xn - ax) * dy / dx
                let fy2 = -yn + 64 + yw
                let cover = (fy2 - fy1) * flip
                saveCell(cx, cy, cover, cover * (fx1))
                xn -= 64
                cx--
                fx1 = 64
                fy1 = fy2
            }
        }
        let fx2 = bx & (64 - 1)
        let fy2 = by & (64 - 1)
        let cover = (fy2 - fy1) * flip
        saveCell(cx, cy, cover, cover * (fx2 + fx1))
    }

    @OverflowWrapping
    func lineToSegments(line: Line) {
        let dy = Int64(line.b.y - line.a.y)
        if (dy == 0) {
            return
        }
        let dx = Int64(line.b.x - line.a.x)
        match {
            case dx == 0 => sendVerticalLine(line)
            case dx > 0 && dy > 0 => sendEastLine(line, dx, dy, 1)
            case dx < 0 && dy < 0 => sendEastLine(Line(line.b, line.a), dx, dy, -1)
            case dx < 0 && dy > 0 => sendWestLine(line, dx, dy, 1)
            case _ => sendWestLine(Line(line.b, line.a), dx, dy, -1)
        }
    }

    func start(a: Point26_6): Unit {
        firstP = a
        lastP = a
        inPath = true
    }

    func line(b: Point26_6): Unit {
        if (b == lastP) {
            return
        }
        lineToSegments(Line(lastP, b))
        lastP = b
    }

    @OverflowWrapping
    func rasterize(cb: SpanFn): Unit {
        if (inPath) {
            if (firstP != lastP) {
                line(firstP) // close path
            }
            inPath = false
        }
        for (i in 0..height) {
            var ic = scanLinks[i].y
            var flip = 1
            var cover = 0
            while (ic != -1) {
                let cc = scanLinks[ic]
                cover += cc.cover
                var lastx = cc.x
                let val = (cover << 6) - cc.area / 2
                if (val == 0) {
                    ic = cc.y
                    continue
                }
                if (val <= 0) {
                    flip = -1
                }
                cb(lastx, i, 1, Int16(val * flip))
                ic = cc.y
                while (ic != -1) {
                    let cc = scanLinks[ic]
                    if (cc.x - lastx - 1 > 0) {
                        cb(lastx + 1, i, (cc.x - lastx - 1), Int16((cover << 6) * flip))
                    }
                    cover += cc.cover
                    lastx = cc.x
                    cb(lastx, i, 1, Int16(((cover << 6) - cc.area / 2) * flip))
                    ic = cc.y
                }
            }
        }
    }
}