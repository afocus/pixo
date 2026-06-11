package pixo.font

import std.io.InputStream
import std.collection.ArrayList

public enum FontStyle{
    | Regular
    | Bold
}

// 字体合集
public class Collection{
    private let fonts = ArrayList<TrueType>()
    public func add(path:String){

    }

    public func add(stream:InputStream){

    }

    public func loadSystemFonts(){

    }


    public func get(name:String,st:FontStyle):TrueType{
        TrueType([])
    }

}