package pixo.font

import std.deriving.Derive
import pixo.raster.Int26_6


@Derive[ToString]
public enum FontStyle{
    | Regular
    | Italic
    | Bold
    | BoldItalic
}



public struct FontInfo {
    public var family: String = ""
    public var subFamily: String = ""
    public var style: FontStyle = FontStyle.Regular
    public var numGlyphs = 0
    public var ascent = 0
    public var descent = 0
    public var lineGap = 0
    public var caretSlope = (0, 0)
    public var numHMetrics = 0
    public var bounds = (0, 0, 0, 0)
    public var unitsPerEm: Int26_6 = 0
    public var indexToLocFormat = false // false means short, true means long.
    public var isPostScript = false
    public var isColor = false
}




public class FontCollection{
    let fontOffsets:Array<Int64>
    let buf:Array<Byte>

    public init(data:Array<Byte>){
        buf = data
        let sfntVer = u32(data[..4])
        if(sfntVer == 0x74746366){
            let r = BinReader(data)
            r.skip(8) 
            let fontCount = Int64(r.readUInt32())
            fontOffsets = Array<Int64>(fontCount,repeat:0)
            for(i in 0..fontCount){
               fontOffsets[i] = Int64(r.readUInt32())
            }
        }else{
            // 非ttc文件
            // 按单字体处理
            fontOffsets = [0] 
        }
    }

    public prop size: Int64{
        get() {
            fontOffsets.size
        }
    }

    public func getFont(i:Int64):?SfntFont{
        if(let Some(v)<-fontOffsets.get(i)){
            SfntFont(buf,v)
        }else{
            None
        }
    }

}