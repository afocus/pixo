package pixo.draw

public enum Op{
    | Over
    | Src
}


public func blendOver(dst:Array<UInt8>,src:Array<UInt8>){
    // if(src.size == 1){
    //     dst.fill(src[0])
    //     return
    // }
    if(src[3] == 0x00){
        return
    }
    if(src[3]==0xff || dst[3]==0x00){
        // src.copyTo(dst)
        dst[0]=src[0]
        dst[1]=src[1]
        dst[2]=src[2]
        dst[3]=src[3]
        return
    }

    let aa = UInt16(src[3])
    let ia = UInt16(0xff-src[3])

    dst[0] = div255(UInt16(src[0])*aa+UInt16(dst[0])*ia)
    dst[1] = div255(UInt16(src[1])*aa+UInt16(dst[1])*ia)
    dst[2] = div255(UInt16(src[2])*aa+UInt16(dst[2])*ia)
    dst[3] = src[3]+div255(UInt16(dst[3])*ia)
}

func blendSrc(dst:Array<UInt8>){

}

// x/255 
func div255(x:UInt16):UInt8{
    UInt8((x + 1 + (x >> 8)) >> 8)
}


// public func blendOver2(dst:Array<UInt8>,src:Array<UInt8>){
//     if(src[3]==0xff){
//         src.copyTo(dst)
//         return
//     }
//     let sr = Float64(src[0])/255.0
//     let sg = Float64(src[1])/255.0
//     let sb = Float64(src[2])/255.0
//     let sa = Float64(src[3])/255.0

//     let dr = Float64(dst[0])/255.0
//     let dg = Float64(dst[1])/255.0
//     let db = Float64(dst[2])/255.0
//     let da = Float64(dst[3])/255.0


//     let x = da*(1.0-sa)
//     let a = (sa+x)
//     if(a==0.0){
//         dst.fill(0)
//         return
//     }

//     dst[0] = clampf((sr*sa + dr*x) / a * 255.0)
//     dst[1] = clampf((sg*sa + dg*x) / a * 255.0)
//     dst[2] = clampf((sb*sa + db*x) / a * 255.0)
//     dst[3] = clampf(a*255.0)
    

// }