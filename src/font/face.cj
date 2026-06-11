package pixo.font

import pixo.raster.Int26_6
import pixo.raster.Point26_6
import pixo.raster.Fill

class Face{
    let font:TrueType
    let scale:Int26_6
    let rast = Fill(0,0)
    init(f:TrueType,size:Int64,dpi!:Int64 = 72){
        font = f
        scale = Int32(0.5 + Float32(size *dpi * 64 / 72))
    }


    // func drawString(s:String){
    //     var dot = Point26_6()
    //     for(r in s.toRuneArray()){
    //         font.glyphPath(r,scale,dot:dot)
    //     }
    // }

}