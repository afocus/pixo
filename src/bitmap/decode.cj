package pixo.bitmap

import std.io.InputStream
import pixo.color.ColorType

public struct BitmapInfo {
    public BitmapInfo(
        let width: Int64,
        let height: Int64,
        let name: String,
        let colorType: ColorType
    ) {}
}


public interface Decodeable{
    func Decode(r:InputStream):Bitmap
    func DecodeInfo(r:InputStream):?BitmapInfo
}


public func DecodeInfo(r: InputStream): ?BitmapInfo {
    None
}

public func Decode(r: InputStream): ?Bitmap {
    None
}




public func registerDecode(name:String,iface:Decodeable){
    
}