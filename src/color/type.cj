package pixo.color

public enum ColorType <: Equatable<ColorType> {
    | RGBA
    | Gray

    public func convert(c: Color): Color {
        if (this == c.mode()) {
            return c
        }
        let (r, g, b, a) = c.toRGBA()
        match (this) {
            case RGBA => Color.RGBA(r, g, b, a)
            case Gray => Color.Gray(calcGray(r, g, b))
        }
    }

    public func spp(): Int64 {
        match (this) {
            case RGBA => 4
            case Gray => 1
        }
    }

    public operator func ==(other: ColorType): Bool {
        match ((this, other)) {
            case (RGBA, RGBA) => true
            case (Gray, Gray) => true
            case _ => false
        }
    }

    public operator func !=(other: ColorType): Bool {
        !(this == other)
    }

    private func calcGray(r: UInt8, g: UInt8, b: UInt8): UInt8 {
        UInt8((UInt32(r) * 299 + UInt32(g) * 587 + UInt32(b) * 114) / 1000)
    }
}
