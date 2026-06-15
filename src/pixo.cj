package pixo

import std.fs.File
import std.fs.OpenMode
import std.io.readToEnd
import pixo.font.SfntFont

main(){
    let fd = File("C:/Windows/Fonts/CascadiaMono.ttf",OpenMode.Read)
    let font = SfntFont(readToEnd(fd))
    fd.close()
    let dpi = 72
    let fontsize = 20
    let scale = Int32(0.5 + Float32(fontsize *dpi * 64 / 72))
    font.glyphAscii(r"G", scale)
    println("--------------------")
    font.glyphAscii(r"p", scale)
    println("--------------------")
    font.glyphAscii(r"a", scale)
}