package pixo.raster

import std.collection.ArrayList

// 路径绘制接口
public interface Pathable {
    func startTo(a: Point26_6): Unit
    func lineTo(b: Point26_6): Unit
    func quadTo(b: Point26_6, c: Point26_6): Unit
    func cubicTo(b: Point26_6, c: Point26_6, d: Point26_6): Unit
}

public type Path = ArrayList<Int26_6>

extend Path <: Pathable {
    public func startTo(a: Point26_6) {
        this.add(all: [0, a.x, a.y, 0])
    }
    public func lineTo(b: Point26_6) {
        this.add(all: [1, b.x, b.y, 1])
    }
    public func quadTo(b: Point26_6, c: Point26_6) {
        this.add(all: [2, b.x, b.y, c.x, c.y, 2])
    }
    public func cubicTo(b: Point26_6, c: Point26_6, d: Point26_6) {
        this.add(all: [3, b.x, b.y, c.x, c.y, d.x, d.y, 3])
    }
}