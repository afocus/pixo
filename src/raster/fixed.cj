package pixo.raster


// 定点26.6 替代浮点
public type Int26_6 = Int32


public struct Point26_6 <: Equatable<Point26_6> & ToString{
    public var x:Int26_6
    public var y:Int26_6

    public init(){
        this.x = 0
        this.y = 0
    }
    public init(x:Int26_6,y:Int26_6){
        this.x = x
        this.y = y
    }

    public operator func +(q:Point26_6):Point26_6{
        Point26_6(this.x+q.x,this.y+q.y)
    }

    public operator func -(q:Point26_6):Point26_6{
        Point26_6(this.x-q.x,this.y-q.y)
    }

    public operator func *(k:Int26_6):Point26_6{
        Point26_6(this.x*k/64,this.y*k/64)
    }

    public operator func /(k:Int26_6):Point26_6{
        Point26_6(this.x*64/k,this.y*64/k)
    }

    public func isEmpty():Bool{
        x == 0 && y == 0
    }

    public operator func ==(q:Point26_6):Bool{
        this.x == q.x && this.y == q.y
    }

    public operator func !=(q:Point26_6):Bool{
        !(this == q)
    }

    public func toString():String{
        "Point26_6(${x},${y})"
    }

}


public struct Rectangle26_6 <: ToString{
    public var min:Point26_6
    public var max:Point26_6

    public init(){
        this.min = Point26_6()
        this.max = Point26_6()
    }
    public init( min:Point26_6, max:Point26_6){
        this.min = min
        this.max = max
    }

    public func containe(p:Point26_6):Bool{
        p.x >= this.min.x && p.x < this.max.x && p.y>=this.min.y && p.y<this.max.y
    }

    public func toString():String{
        "Rectangle26_6(${min},${max})"
    }
}

