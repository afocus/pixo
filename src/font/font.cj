package pixo.font

import std.deriving.Derive


@Derive[ToString]
public enum FontStyle{
    | Regular
    | Italic
    | Bold
    | BoldItalic
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

    public func getFont(i:Int64):?TrueType{
        if(let Some(v)<-fontOffsets.get(i)){
            TrueType(buf,v)
        }else{
            None
        }
    }


}