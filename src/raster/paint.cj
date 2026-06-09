package pixo.raster

public interface Paintable {
    // 光栅化会多次调用panit处理span
    func panit(x: Int64, y: Int64, n: Int64, alpha: UInt8): Unit
    // 光栅化结束后调用
    func done(): Unit
}

// 绘制成 ASCII 艺术效果，主要用于测试
public class ASCIIPaint <: Paintable {
    let pixs: Array<UInt8>
    let stride: Int64
    public init(w: Int64, h: Int64) {
        pixs = Array<UInt8>(w * h, repeat: 0)
        stride = w
    }
    public func panit(x: Int64, y: Int64, n: Int64, alpha: UInt8): Unit {
        for (i in 0..n) {
            pixs[y * stride + x + i] = alpha
        }
    }

    public func done(): Unit {
        let chars = ".:+OX#&@".toRuneArray()
        for (y in 0..pixs.size) {
            if (y % stride == 0) {
                println()
            }
            let c = chars[Int64(pixs[y] >> 5)]
            print(c)
        }
    }
}
