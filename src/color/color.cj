package pixo.color

public enum Color <: ToString {
    | RGBA(UInt8, UInt8, UInt8, UInt8)
    | Gray(UInt8)

    public func mode(): ColorType {
        match (this) {
            case Gray(_) => ColorType.Gray
            case _ => ColorType.RGBA
        }
    }

    func toRGBA(): (UInt8, UInt8, UInt8, UInt8) {
        match (this) {
            case RGBA(r, g, b, a) => (r, g, b, a)
            case Gray(y) => (y, y, y, 0xff)
        }
    }

    public func toString(): String {
        match (this) {
            case RGBA(r, g, b, a) => "rgba(${r},${g},${b},${a})"
            case Gray(y) => "gray(${y})"
        }
    }

    public static func black(): Color {
        Gray(0x00)
    }

    public static func white(): Color {
        Gray(0xff)
    }
}
