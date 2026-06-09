package pixo.geom


public struct Rect<:ToString{
    public Rect(
        public var x0:Int64,
        public var y0:Int64,
        public var x1:Int64,
        public var y1:Int64
    ){}

    public func width():Int64{
        x1-x0
    }

    public func height():Int64{
        y1-y0
    }

    public func empty():Bool{
        x0>=x1 || y0>=y1
    }


    public func contains(x:Int64,y:Int64):Bool{
        x>=x0 && x<x1 && y>=y0 && y<y1
    }

    public func toString():String{
        "rect(${x0},${y0},${x1},${y1})"
    }

    public func intersect(other:Rect):Rect{
        var r = this
        if(r.x0<other.x0){
            r.x0 = other.x0
        }
        if(r.y0<other.y0){
            r.y0 = other.y0
        }
        if(r.x1>other.x1){
            r.x1 = other.x1
        }
        if(r.y1>other.y1){
            r.y1 = other.y1
        }
        if(r.empty()){
            Rect(0,0,0,0)
        }else{
            r
        }
    }


    public func sub(x:Int64,y:Int64):Rect{
        Rect(x0-x,y0-y,x1-x,y1-y)
    }

}