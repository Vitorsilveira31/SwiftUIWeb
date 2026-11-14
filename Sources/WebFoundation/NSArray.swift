// Foundation's `NSArray` and `NSMutableArray` for browser and Embedded builds: the parts predicates and
// filtering use. Elements are `Any`; an element that is `nil` is stored as `NSNull`, as in Foundation.

open class NSArray: NSObject, ExpressibleByArrayLiteral {
  package var _items: [Any]

  public override init() {
    _items = []
    super.init()
  }

  public convenience init(object anObject: Any) {
    self.init(array: [anObject])
  }

  public convenience init(array: [Any]) {
    self.init()
    _items = array
  }

  public convenience init(objects elements: Any...) {
    self.init(array: elements)
  }

  public required convenience init(arrayLiteral elements: Any...) {
    self.init(array: elements)
  }

  open var count: Int { _items.count }

  open func object(at index: Int) -> Any { _items[index] }

  open subscript(idx: Int) -> Any { _items[idx] }

  open var firstObject: Any? { _items.first }

  open var lastObject: Any? { _items.last }

  /// The elements that satisfy `predicate`, in order.
  open func filtered(using predicate: NSPredicate) -> [Any] {
    _items.filter { predicate.evaluate(with: $0) }
  }
}

open class NSMutableArray: NSArray {
  public override init() {
    super.init()
  }

  public init(capacity numItems: Int) {
    super.init()
    _items.reserveCapacity(numItems)
  }

  open func add(_ anObject: Any) { _items.append(anObject) }

  open func insert(_ anObject: Any, at index: Int) { _items.insert(anObject, at: index) }

  open func removeObject(at index: Int) { _items.remove(at: index) }

  open func removeLastObject() { _items.removeLast() }

  open func removeAllObjects() { _items.removeAll() }

  open func replaceObject(at index: Int, with anObject: Any) { _items[index] = anObject }

  open override subscript(idx: Int) -> Any {
    get { _items[idx] }
    set { _items[idx] = newValue }
  }

  /// Removes the elements that do not satisfy `predicate`.
  open func filter(using predicate: NSPredicate) {
    _items = _items.filter { predicate.evaluate(with: $0) }
  }
}
