package pixo.draw



import std.math.{abs, sin, floor}
import std.runtime.getProcessorCount
import pixo.geom.{Matrix,Rect}
import pixo.bitmap.Bitmap
import pixo.color.*


// 抗锯齿采样滤波
public enum InterpMode {
    | Nearest
    | BiLiner
    | BiCubic
    | MitchellNetravali
    | Lanczos

    func radius(): Int64 {
        match (this) {
            case Nearest => 0
            case BiLiner => 1
            case BiCubic => 2
            case MitchellNetravali => 2
            case Lanczos => 3
        }
    }

    func kernel(v: Float64): Float64 {
        match (this) {
            case Nearest =>
                if (v >= -0.5 && v < 0.5) {
                    1.0
                } else {
                    0.0
                }
            case BiLiner =>
                let x = abs(v)
                if (x < 1.0) {
                    1.0 - x
                } else {
                    0.0
                }
            case BiCubic =>
                let x = abs(v)
                if (x <= 1.0) {
                    x * x * (1.5 * x - 2.5) + 1.0
                } else if (x <= 2.0) {
                    x * (x * (2.5 - 0.5 * x) - 4.0) + 2.0
                } else {
                    0.0
                }
            case MitchellNetravali =>
                let x = abs(v)
                if (x <= 2.0) {
                    bcspline(x, 1.0 / 3.0, 1.0 / 3.0)
                } else {
                    0.0
                }
            case Lanczos =>
                let x = abs(v)
                if (x <= 3.0) {
                    sinc(x) * sinc(x / 3.0)
                } else {
                    0.0
                }
        }
    }
}

public func transform(dst: Bitmap, src: Bitmap, m: Matrix, mode!: InterpMode = InterpMode.BiLiner, op!: Op = Op.Over) {
    // let srcbox = src.rect()
    // var dstbox = dst.rect().intersect(m.transformRect(srcbox))
    // let inv = m.invert()

    // let dr = inv.transformRect(dstbox)
    // dstbox = dstbox.sub(dr.x0,dr.y0)




    let srcbox = src.rect()
    var dstbox = dst.rect().intersect(m.transformRect(srcbox))
    let inv = m.invert()

    let dr = inv.transformRect(dstbox)
    dstbox = dstbox.sub(dr.x0,dr.y0)
    dstbox = dstbox.intersect(dst.rect())


    let useOp = if(
        src.colorType == dst.colorType && 
        src.colorType == ColorType.RGBA){
        op
    }else{
        Op.Src
    }
    
    // match(op){
    //     case Op.Over =>

    // }
    
    


    // println(srcbox)
    // println(dstbox)
    // println(dr)
    
    match(mode){
        case Nearest =>
            nearestTransform(dst,src,dstbox,srcbox,inv,op)
        case _ =>
            // sampleTransformRGBA(dst,src,dstbox,srcbox,inv,mode,op)
            sampleTransformLut(dst,src,dstbox,srcbox,inv,mode,op)
            // if(dst.colorMode == src.colorMode && dst.colorMode == ColorMode.CmRGBA){
            //     println("rgba")
            //     sampleTransformRGBA(dst,src,dstbox,srcbox,inv,mode,op)
            // }else{
            //     sampleTransformImage(dst,src,dstbox,srcbox,inv,mode)
            // }
    }
}




func sampleTransformImage(dst:Bitmap,src:Bitmap,dr:Rect,sr:Rect,m:Matrix,mode:InterpMode){
    let radius = mode.radius()
    let kernel = mode.kernel
    parallel(dr.y0,dr.y1){ start,end =>
        // 预计算水平/垂直权重
        let wx = Array<Float64>(radius * 2, repeat: 0.0)
        let wy = Array<Float64>(radius * 2, repeat: 0.0)
        let px = Array<Float64>(src.spp, repeat: 0.0)
        for(y in start..end){
            for(x in dr.x0..dr.x1){
                let (sx, sy) = m.transformPoint(Float64(x), Float64(y))
                let x0 = Int64(floor(sx))
                let y0 = Int64(floor(sy))
                if(!sr.contains(x0,y0)){
                    println(">>>")
                    continue
                }

                let dx = sx - Float64(x0)
                let dy = sy - Float64(y0)

                for (i in 0..radius * 2) {
                    let offset = Float64(i - radius + 1)
                    wx[i] = kernel(offset - dx)
                    wy[i] = kernel(offset - dy)
                }
                px.fill(0.0)
                for (j in 0..radius * 2) {
                    let ty = y0 - radius + 1 + j
                    for (i in 0..radius * 2) {
                        let w = wx[i] * wy[j]
                        if (w == 0.0) {
                            continue
                        }
                        let tx = x0 - radius + 1 + i
                        if(!sr.contains(tx,ty)){
                            continue
                        }
                        let offset = ty * src.stride + tx * src.spp
                        for (k in 0..src.spp) {
                            px[k] += w * Float64(src.pixels[offset + k])
                        }
                    }
                }

                

                let c = match(src.colorType){
                    case ColorType.Gray => Color.Gray(
                        clampf(px[0]),
                    )
                    case ColorType.RGBA => Color.RGBA(
                        clampf(px[0]),
                        clampf(px[1]),
                        clampf(px[2]),
                        clampf(px[3]),
                    )
                }
                dst.setColor(x,y,c)
            }
        }
    }
}


func nearestTransform(dst:Bitmap,src:Bitmap,dr:Rect,sr:Rect,m:Matrix,op:Op){
    let rgba = dst.colorType == src.colorType && dst.colorType == ColorType.RGBA
    parallel(dr.y0,dr.y1){ start,end =>
        for(y in start..end){
            let yf = Float64(y)+0.5
            for(x in dr.x0..dr.x1){
                let xf = Float64(x)+0.5
                let dx = Int64(m.a*xf+m.c*yf+m.e)
                let dy = Int64(m.b*xf+m.d*yf+m.f)
                if(!sr.contains(dx,dy)){
                    continue
                }
                if(!rgba){
                    dst.setColor(x,y,src.getColor(dy,dy))
                    continue
                }
                let srco = dy * src.stride + dx * 4
                let dsto = y * dst.stride + x * 4
                match(op){
                    case Src =>
                        dst.pixels[dsto+0] = src.pixels[srco+0]
                        dst.pixels[dsto+1] = src.pixels[srco+1]
                        dst.pixels[dsto+2] = src.pixels[srco+2]
                        dst.pixels[dsto+3] = src.pixels[srco+3]
                    case Over =>
                        blendOver(
                            dst.pixels[dsto..dsto+4],
                            src.pixels[srco..srco+4]
                        )
                }
            }
        }
    }
}

const shift = 16
let scale = Float64(1 << shift)


struct KernelLut{
    let tables:Array<Float64>
    let scale:Float64
    init(n:Int64,r:Int64,fn:(Float64)->Float64){
        tables = Array<Float64>(n){ i =>
            let dist = (Float64(i) + 0.5) / Float64(n) * Float64(r)
            fn(dist)
        }
        scale = Float64(n)/Float64(r)
    }
    func value(t:Float64):Float64{
        let i = Int64(t*scale)
        if(i>=tables.size){
            0.0
        }else{
            tables[i]
        }
    }
}


func sampleTransformLut(dst:Bitmap,src:Bitmap,dr:Rect,sr:Rect,m:Matrix,mode:InterpMode,op:Op){
    let radius = mode.radius()
    let kernel = mode.kernel
    let luts = KernelLut(256,radius,kernel)

    parallel(dr.y0,dr.y1){ start,end =>

        // 预计算水平/垂直权重
        let wx = Array<Float64>(radius * 2, repeat: 0.0)
        let wy = Array<Float64>(radius * 2, repeat: 0.0)
        let px = Array<Float64>(4, repeat: 0.0)

        for(y in start..end){
            
            let yoffset = y * dst.stride
            for(x in dr.x0..dr.x1){
                let (sx, sy) = m.transformPoint(Float64(x), Float64(y))
                let x0 = Int64(sx)
                let y0 = Int64(sy)
                if(!sr.contains(x0,y0)){
                    continue
                }

                let dx = sx - Float64(x0)
                let dy = sy - Float64(y0)

                for (i in 0..radius * 2) {
                    let offset = Float64(i - radius + 1)
                    wx[i] = luts.value(offset - dx)
                    wy[i] = luts.value(offset - dy)
                }
                px.fill(0.0)
                for (j in 0..radius * 2) {
                    let ty = y0 - radius + 1 + j
                    for (i in 0..radius * 2) {
                        let w = wx[i] * wy[j]
                        if (w == 0.0) {
                            continue
                        }
                        let tx = x0 - radius + 1 + i
                        if(!sr.contains(tx,ty)){
                            continue
                        }
                        let offset = ty * src.stride + tx * 4
                        for (k in 0..4) {
                            px[k] += w * Float64(src.pixels[offset + k])
                        }
                    }
                }
                let dstOffset = yoffset + x * 4
                match(op){
                    case Src =>
                        dst.pixels[dstOffset+0] = clampf(px[0])
                        dst.pixels[dstOffset+1] = clampf(px[1])
                        dst.pixels[dstOffset+2] = clampf(px[2])
                        dst.pixels[dstOffset+3] = clampf(px[3])
                    case Over =>
                        blendOver(
                            dst.pixels[dstOffset..dstOffset+4],
                            clampf(px[0]),
                            clampf(px[1]),
                            clampf(px[2]),
                            clampf(px[3]),
                        )
                }

            }
        }

    }


	
}


func sampleTransformRGBA(dst:Bitmap,src:Bitmap,dr:Rect,sr:Rect,m:Matrix,mode:InterpMode,op:Op){
    let radius = mode.radius()
    let kernel = mode.kernel


    parallel(dr.y0,dr.y1){ start,end =>
        // 预计算水平/垂直权重
        let wx = Array<Float64>(radius * 2, repeat: 0.0)
        let wy = Array<Float64>(radius * 2, repeat: 0.0)
        let px = Array<Float64>(4, repeat: 0.0)
        for(y in start..end){
            let yoffset = y * dst.stride
            for(x in dr.x0..dr.x1){
                let (sx, sy) = m.transformPoint(Float64(x), Float64(y))
                let x0 = Int64(floor(sx))
                let y0 = Int64(floor(sy))
                if(!sr.contains(x0,y0)){
                    continue
                }

                let dx = sx - Float64(x0)
                let dy = sy - Float64(y0)

                for (i in 0..radius * 2) {
                    let offset = Float64(i - radius + 1)
                    wx[i] = kernel(offset - dx)
                    wy[i] = kernel(offset - dy)
                }
                px.fill(0.0)
                for (j in 0..radius * 2) {
                    let ty = y0 - radius + 1 + j
                    for (i in 0..radius * 2) {
                        let w = wx[i] * wy[j]
                        if (w == 0.0) {
                            continue
                        }
                        let tx = x0 - radius + 1 + i
                        if(!sr.contains(tx,ty)){
                            continue
                        }
                        let offset = ty * src.stride + tx * 4
                        for (k in 0..4) {
                            px[k] += w * Float64(src.pixels[offset + k])
                        }
                    }
                }
                let dstOffset = yoffset + x * 4
                match(op){
                    case Src =>
                        dst.pixels[dstOffset+0] = clampf(px[0])
                        dst.pixels[dstOffset+1] = clampf(px[1])
                        dst.pixels[dstOffset+2] = clampf(px[2])
                        dst.pixels[dstOffset+3] = clampf(px[3])
                    case Over =>
                        blendOver(
                            dst.pixels[dstOffset..dstOffset+4],
                            clampf(px[0]),
                            clampf(px[1]),
                            clampf(px[2]),
                            clampf(px[3]),
                        )
                }
            }
        }
    }
}


// func transformRGBA(dst: Image, src: Image, , op!: Op = Src) {
//     let srcBox = src.rect()
//     let dstbox = dst.rect().intersect(m.transformRect(srcBox))
//     let inv = m.invert()
//     let radius = mode.radius()
//     let kernel = mode.kernel

//     parallel(dstbox.y0, dstbox.y1) {
//         start, end => for (y in start..end) {
//             // 预计算水平/垂直权重
//             let wx = Array<Float64>(radius * 2, repeat: 0.0)
//             let wy = Array<Float64>(radius * 2, repeat: 0.0)
//             let yoffset = y * dst.stride
//             for (x in dstbox.x0..dstbox.x1) {
//                 let (sx, sy) = inv.transformPoint(Float64(x), Float64(y))
//                 let x0 = Int64(floor(sx))
//                 let y0 = Int64(floor(sy))
                
//                 if(!srcBox.contains(x0,y0)){
//                     continue
//                 }

//                 let dx = sx - Float64(x0)
//                 let dy = sy - Float64(y0)
                
                

//                 let (r,g,b,a) = if (radius == 0) {
//                     // Nearest fastpath
//                     let tx = x0 + Int64(kernel(dx))
//                     let ty = y0 + Int64(kernel(dy))
//                     let offset = ty * src.stride + tx * src.spp

//                     (
//                         src.pixs[offset+0],
//                         src.pixs[offset+1],
//                         src.pixs[offset+2],
//                         src.pixs[offset+3],
//                     )
//                 } else {
                   

//                     for (i in 0..radius * 2) {
//                         let offset = Float64(i - radius + 1)
//                         wx[i] = kernel(offset - dx)
//                         wy[i] = kernel(offset - dy)
//                     }

//                     let px = Array<Float64>(src.spp, repeat: 0.0)
//                     for (j in 0..radius * 2) {
//                         let ty = y0 - radius + 1 + j
//                         for (i in 0..radius * 2) {
//                             let w = wx[i] * wy[j]
//                             if (w == 0.0) {
//                                 continue
//                             }
//                             let tx = x0 - radius + 1 + i
//                             if(!srcBox.contains(tx,ty)){
//                                 continue
//                             }
//                             let offset = ty * src.stride + tx * src.spp
//                             for (k in 0..src.spp) {
//                                 px[k] += w * Float64(src.pixs[offset + k])
//                             }
//                         }
//                     }
//                     (
//                         clampf(px[0]),
//                         clampf(px[1]),
//                         clampf(px[2]),
//                         clampf(px[3]),
//                     )
//                 }
//                 let dstOffset = yoffset + x * dst.spp
//                 match(op){
//                     case Src =>
//                         dst[dstOffset+0] = r
//                         dst[dstOffset+1] = g
//                         dst[dstOffset+2] = b
//                         dst[dstOffset+3] = a
//                     case Over =>
//                         blendOver(dst[dstOffset..dstOffset+4],r,g,b,a)
//                 }
//             }
//         }
//     }
// }



func parallel(start: Int64, end: Int64, cb: (Int64, Int64) -> Unit) {
    let h = end - start
    if(h<=0){
        return
    }
    let pcnt = getProcessorCount()
    if (h < 10*pcnt || pcnt == 1) {
        cb(start, end)
        return
    }
    // 每个worker处理多少行
    let rowsPerWorker = h / pcnt
    let go = Array(pcnt,{_=>unsafe{zeroValue<Future<Unit>>()}})

    for(i in 0..pcnt){
        let ss = i*rowsPerWorker
        let se = if(i+1 == pcnt){
            h
        }else{
            ss+rowsPerWorker
        }
        go[i] = spawn {
            cb(start+ss,start+se)
        }
    }

    for (g in go) {
        g.get()
    }
}

func bcspline(x: Float64, b: Float64, c: Float64): Float64 {
    if (x < 1.0) {
        ((12.0 - 9.0 * b - 6.0 * c) * x * x * x + (-18.0 + 12.0 * b + 6.0 * c) * x * x + (6.0 - 2.0 * b)) / 6.0
    } else if (x < 2.0) {
        ((-b - 6.0 * c) * x * x * x + (6.0 * b + 30.0 * c) * x * x + (-12.0 * b - 48.0 * c) * x + (8.0 * b + 24.0 * c)) /
            6.0
    } else {
        0.0
    }
}

const PI = 3.14159265358979323846264338327

func sinc(x: Float64): Float64 {
    if (x == 0.0) {
        1.0
    } else {
        sin(PI * x) / (PI * x)
    }
}

// func clamp(v: Int32): UInt8 {
//     if (v < 0) {
//         0
//     } else if (v > 255) {
//         255
//     } else {
//         UInt8(v)
//     }
// }

func clampf(v: Float64): UInt8 {
    if (v < 0.0) {
        0
    } else if (v > 255.0) {
        255
    } else {
        UInt8(v)
    }
}
