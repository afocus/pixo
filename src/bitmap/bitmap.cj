package pixo.bitmap

import pixo.color.*
import pixo.geom.Rect


// 可编辑位图
// 直接操作pixels是危险的 尽量使用setColor/getColor
public class Bitmap {
    public let pixels: Array<UInt8>
    public let width: Int64
    public let height: Int64
    public let stride: Int64
    public let colorType: ColorType
    public let spp: Int64

    init(ct: ColorType, w: Int64, h: Int64, pixs: Array<UInt8>, rowSize: Int64) {
        spp = ct.spp()
        colorType = ct
        width = w
        height = h
        pixels = pixs
        stride = rowSize
    }

    public init(ct: ColorType, w: Int64, h: Int64) {
        spp = ct.spp()
        colorType = ct
        width = w
        height = h
        stride = spp * w
        pixels = Array<UInt8>(stride, repeat: 0)
    }

    public static func RGBA(w: Int64, h: Int64) {
        Bitmap(ColorType.RGBA, w, h)
    }

    public static func Gray(w: Int64, h: Int64) {
        Bitmap(ColorType.Gray, w, h)
    }

    // 获取指定坐标的像素在原始数据中的位置
    public func pixelsOffset(x: Int64, y: Int64): Int64 {
        y * stride + x * spp
    }

    // 设置指定位置像素的颜色
    public func setColor(x: Int64, y: Int64, c: Color) {
        let i = pixelsOffset(x, y)
        let c1 = colorType.convert(c)
        match (c1) {
            case Color.RGBA(r, g, b, a) =>
                pixels[i + 0] = r
                pixels[i + 1] = g
                pixels[i + 2] = b
                pixels[i + 3] = a
            case Color.Gray(y) => 
                pixels[i + 0] = y
        }
    }

    // 获取指定位置像素的颜色
    public func getColor(x: Int64, y: Int64): Color {
        let i = pixelsOffset(x, y)
        match (colorType) {
            case ColorType.Gray => 
                Color.Gray(pixels[i])
            case ColorType.RGBA => 
                Color.RGBA(
                    pixels[i + 0],
                    pixels[i + 1],
                    pixels[i + 2],
                    pixels[i + 3],
                )
        }
    }

    // 是否不透明
    public func isOpaque(): Bool {
        if (colorType == ColorType.Gray) {
            return true
        }
        for (y in 0..height) {
            for (x in 0..width) {
                let a = pixelsOffset(x, y) + 3
                if (pixels[a] != 0xff) {
                    return false
                }
            }
        }
        true
    }

    // 返回一个新的拷贝
    public func clone(): Bitmap {
        Bitmap(colorType, width, height, pixels.clone(), stride)
    }

    // 返回图像的一部分
    // 引用自原图像 修改原图像像素子图像也会被修改
    public func clip(x: Int64, y: Int64, w: Int64, h: Int64): Bitmap {
        let offset = pixelsOffset(x, y)
        Bitmap(colorType, w, h, pixels[offset..], stride)
    }


    public func rect(): Rect {
        Rect(0, 0, width, height)
    }
}
