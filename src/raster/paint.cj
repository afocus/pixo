package pixo.raster

import pixo.bitmap.Bitmap
import pixo.color.{Color, ColorType}
import pixo.draw.blendOver
import pixo.geom.Rect

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

// 当前仅支持ColorType.RGBA
public class BitmapPaint <: Paintable {
    let surface: Bitmap
    let colorCb: (x: Int64, y: Int64) -> Color
    let box: Rect
    public init(rgbaBitmap: Bitmap, colorCallback: (x: Int64, y: Int64) -> Color) {
        if (rgbaBitmap.colorType != ColorType.RGBA) {
            throw Exception("raster: BitmapPaint only support ColorType.RGBA")
        }
        surface = rgbaBitmap
        colorCb = colorCallback
        box = rgbaBitmap.rect()
    }

    public func panit(x: Int64, y: Int64, n: Int64, alpha: UInt8): Unit {
        if (alpha == 0 || !box.contains(x + n, y)) {
            return
        }
        let aa = UInt16(alpha)
        for (i in 0..n) {
            let (r, g, b, a) = colorCb(x + i, y).toRGBA()
            // 计算混合颜色最终透明度
            let ia = (UInt16(a) * (0xff - aa)) >> 8
            let offset = surface.pixelsOffset(x + i, y)
            blendOver(surface.pixels[offset..offset + 4], r, g, b, UInt8(ia))
        }
    }

    public func done(): Unit {}
}
