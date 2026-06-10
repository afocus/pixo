package pixo.raster

import std.collection.ArrayList

// 路径绘制接口
public interface Pathable {
    func startTo(a: Point26_6): Unit
    func lineTo(b: Point26_6): Unit
    func quadTo(b: Point26_6, c: Point26_6): Unit
    func cubicTo(b: Point26_6, c: Point26_6, d: Point26_6): Unit
}




public enum PathCmd {
    | Start
    | Line
    | Quad
    | Cubic
}
public struct PathElement{
    PathElement(
        public let cmd:PathCmd,
        public let points:Array<Point26_6>
    ){}
}

public type Paths = ArrayList<PathElement>

extend Paths <: Pathable {
    public func startTo(a: Point26_6) {
        add(PathElement(PathCmd.Start,a))
    }
    public func lineTo(b: Point26_6) {
        add(PathElement(PathCmd.Line,b))
    }
    public func quadTo(b: Point26_6, c: Point26_6) {
        add(PathElement(PathCmd.Quad,b, c))
    }
    public func cubicTo(b: Point26_6, c: Point26_6, d: Point26_6) {
        add(PathElement(PathCmd.Cubic,b, c))
    }
    public func firstPoint():Point26_6{
        this[0].points[0]
    }

}


