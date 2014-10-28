//===--- ArrayBridge.swift - Array<T> <=> NSArray bridging ----------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2015 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SwiftShims

/// Class used whose sole instance is used as storage for empty
/// arrays.  The instance is defined in the runtime and statically
/// initialized.  See stdlib/runtime/GlobalObjects.cpp for details.
internal final class _EmptyArrayStorage
  : _ContiguousArrayStorageBase {

  init(_doNotCallMe: ()) {
    _sanityCheckFailure("creating instance of _EmptyArrayStorage")
  }
  
  var countAndCapacity: _ArrayBody

  override func _withVerbatimBridgedUnsafeBuffer<R>(
    body: (UnsafeBufferPointer<AnyObject>)->R
  ) -> R? {
    return body(UnsafeBufferPointer(start: .null(), count: 0))
  }

  override func _getNonVerbatimBridgedCount(dummy: Void) -> Int {
    return 0
  }

  override func _getNonVerbatimBridgedHeapBuffer(
    dummy: Void
  ) -> _HeapBuffer<Int, AnyObject> {
    return _HeapBuffer<Int, AnyObject>(
      _HeapBufferStorage<Int, AnyObject>.self, 0, 0)
  }

  override func canStoreElementsOfDynamicType(_: Any.Type) -> Bool {
    return false
  }

  /// A type that every element in the array is.
  override var staticElementType: Any.Type {
    return Void.self
  }
}

/// The empty array prototype.  We use the same object for all empty
/// [Native]Array<T>s.
internal var _emptyArrayStorage : _EmptyArrayStorage {
  return Builtin.bridgeFromRawPointer(
    Builtin.addressof(&_swiftEmptyArrayStorage))
}

// FIXME: This whole class is a workaround for
// <rdar://problem/18560464> Can't override generic method in generic
// subclass.  If it weren't for that bug, we'd override
// _withVerbatimBridgedUnsafeBuffer directly in
// _ContiguousArrayStorage<T>.
class _ContiguousArrayStorage1 : _ContiguousArrayStorageBase {
  /// If the `T` is bridged verbatim, invoke `body` on an
  /// `UnsafeBufferPointer` to the elements and return the result.
  /// Otherwise, return `nil`.
  final override func _withVerbatimBridgedUnsafeBuffer<R>(
    body: (UnsafeBufferPointer<AnyObject>)->R
  ) -> R? {
    var result: R? = nil
    self._withVerbatimBridgedUnsafeBufferImpl {
      result = body($0)
    }
    return result
  }

  /// If `T` is bridged verbatim, invoke `body` on an
  /// `UnsafeBufferPointer` to the elements.
  internal func _withVerbatimBridgedUnsafeBufferImpl(
    body: (UnsafeBufferPointer<AnyObject>)->Void
  ) {
    _sanityCheckFailure(
      "Must override _withVerbatimBridgedUnsafeBufferImpl in derived classes")
  }
}

// The class that implements the storage for a ContiguousArray<T>
final class _ContiguousArrayStorage<T> : _ContiguousArrayStorage1 {
  typealias Buffer = _ContiguousArrayBuffer<T>

  deinit {
    let b = Buffer(self)
    b.baseAddress.destroy(b.count)
    b._base._value.destroy()
  }

  final func __getInstanceSizeAndAlignMask() -> (Int,Int) {
    return Buffer(self)._base._allocatedSizeAndAlignMask()
  }

  /// If `T` is bridged verbatim, invoke `body` on an
  /// `UnsafeBufferPointer` to the elements.
  internal final override func _withVerbatimBridgedUnsafeBufferImpl(
    body: (UnsafeBufferPointer<AnyObject>)->Void
  ) {
    if _isBridgedVerbatimToObjectiveC(T.self) {
      let nativeBuffer = Buffer(self)
      body(
        UnsafeBufferPointer(
          start: UnsafePointer(nativeBuffer.baseAddress),
          count: nativeBuffer.count))
      _fixLifetime(self)
    }
  }

  /// Returns the number of elements in the array.
  ///
  /// Precondition: `T` is bridged non-verbatim.
  override internal func _getNonVerbatimBridgedCount(dummy: Void) -> Int {
    _sanityCheck(
      !_isBridgedVerbatimToObjectiveC(T.self),
      "Verbatim bridging should be handled separately")
    return Buffer(self).count
  }

  /// Bridge array elements and return a new buffer that owns them.
  ///
  /// Precondition: `T` is bridged non-verbatim.
  override internal func _getNonVerbatimBridgedHeapBuffer(dummy: Void) ->
    _HeapBuffer<Int, AnyObject> {
    _sanityCheck(
      !_isBridgedVerbatimToObjectiveC(T.self),
      "Verbatim bridging should be handled separately")
    let nativeBuffer = Buffer(self)
    let count = nativeBuffer.count
    let result = _HeapBuffer<Int, AnyObject>(
      _HeapBufferStorage<Int, AnyObject>.self, count, count)
    let resultPtr = result.baseAddress
    for i in 0..<count {
      (resultPtr + i).initialize(
        _bridgeToObjectiveCUnconditional(nativeBuffer[i]))
    }
    return result
  }

  /// Return true if the `proposedElementType` is `T` or a subclass of
  /// `T`.  We can't store anything else without violating type
  /// safety; for example, the destructor has static knowledge that
  /// all of the elements can be destroyed as `T`
  override func canStoreElementsOfDynamicType(
    proposedElementType: Any.Type
  ) -> Bool {
    return proposedElementType is T.Type
  }

  /// A type that every element in the array is.
  override var staticElementType: Any.Type {
    return T.self
  }
}

public struct _ContiguousArrayBuffer<T> : _ArrayBufferType {

  /// Make a buffer with uninitialized elements.  After using this
  /// method, you must either initialize the count elements at the
  /// result's .baseAddress or set the result's .count to zero.
  public init(count: Int, minimumCapacity: Int)
  {
    let realMinimumCapacity = max(count, minimumCapacity)
    if realMinimumCapacity == 0 {
      self = _ContiguousArrayBuffer<T>()
    }
    else {
      __bufferPointer = ManagedBufferPointer(
        bufferClass: _ContiguousArrayStorage<T>.self,
        minimumCapacity: realMinimumCapacity
      ) {_,_ in _ArrayBody() }
      
      let verbatim = _isBridgedVerbatimToObjectiveC(T.self)
      
      __bufferPointer.value = _ArrayBody(
        count: count, capacity: _base._capacity(),
        elementTypeIsBridgedVerbatim: verbatim)
    }
  }

  init(_ storage: _ContiguousArrayStorageBase?) {
    __bufferPointer = ManagedBufferPointer(
      unsafeBufferObject: storage ?? _emptyArrayStorage)
  }

  /// If the elements are stored contiguously, a pointer to the first
  /// element. Otherwise, nil.
  public var baseAddress: UnsafeMutablePointer<T> {
    return __bufferPointer.withUnsafeMutablePointerToElements { $0 }
  }

  /// Call `body(p)`, where `p` is an `UnsafeBufferPointer` over the
  /// underlying contiguous storage.
  public func withUnsafeBufferPointer<R>(
    body: (UnsafeBufferPointer<Element>)->R
  ) -> R {
    let ret = body(UnsafeBufferPointer(start: self.baseAddress, count: count))
    _fixLifetime(self)
    return ret
  }

  /// Call `body(p)`, where `p` is an `UnsafeMutableBufferPointer`
  /// over the underlying contiguous storage.
  public mutating func withUnsafeMutableBufferPointer<R>(
    body: (UnsafeMutableBufferPointer<T>)->R
  ) -> R {
    let ret = body(
      UnsafeMutableBufferPointer(start: baseAddress, count: count))
    _fixLifetime(self)
    return ret
  }

  //===--- _ArrayBufferType conformance -----------------------------------===//
  /// The type of elements stored in the buffer
  public typealias Element = T

  /// create an empty buffer
  public init() {
    __bufferPointer = ManagedBufferPointer(
      unsafeBufferObject: _emptyArrayStorage)
  }

  /// Adopt the storage of x
  public init(_ buffer: _ContiguousArrayBuffer) {
    self = buffer
  }

  public mutating func requestUniqueMutableBackingBuffer(minimumCapacity: Int)
    -> _ContiguousArrayBuffer<Element>?
  {
    if _fastPath(isUniquelyReferenced() && capacity >= minimumCapacity) {
      return self
    }
    return nil
  }

  public mutating func isMutableAndUniquelyReferenced() -> Bool {
    return isUniquelyReferenced()
  }

  /// If this buffer is backed by a `_ContiguousArrayBuffer`
  /// containing the same number of elements as `self`, return it.
  /// Otherwise, return `nil`.
  public func requestNativeBuffer() -> _ContiguousArrayBuffer<Element>? {
    return self
  }

  /// Replace the given subRange with the first newCount elements of
  /// the given collection.
  ///
  /// Requires: this buffer is backed by a uniquely-referenced
  /// _ContiguousArrayBuffer
  public mutating func replace<
    C: CollectionType where C.Generator.Element == Element
  >(
    #subRange: Range<Int>, with newCount: Int, elementsOf newValues: C
  ) {
    _arrayNonSliceInPlaceReplace(&self, subRange, newCount, newValues)
  }

  /// Get/set the value of the ith element
  public subscript(i: Int) -> T {
    get {
      _sanityCheck(_isValidSubscript(i), "Array index out of range")
      // If the index is in bounds, we can assume we have storage.
      return baseAddress[i]
    }
    nonmutating set {
      _sanityCheck(i >= 0 && i < count, "Array index out of range")
      // If the index is in bounds, we can assume we have storage.

      // FIXME: Manually swap because it makes the ARC optimizer happy.  See
      // <rdar://problem/16831852> check retain/release order
      // baseAddress[i] = newValue
      var nv = newValue
      let tmp = nv
      nv = baseAddress[i]
      baseAddress[i] = tmp
    }
  }

  /// How many elements the buffer stores
  public var count: Int {
    get {
      return __bufferPointer.value.count
    }
    nonmutating set {
      _sanityCheck(newValue >= 0)

      _sanityCheck(
        newValue <= capacity,
        "Can't grow an array buffer past its capacity")

      _sanityCheck(_base.hasStorage || newValue == 0)

      if _base.hasStorage {
        _base.value.count = newValue
      }
    }
  }

  /// Return whether the given `index` is valid for subscripting, i.e. `0
  /// ≤ index < count`
  func _isValidSubscript(index : Int) -> Bool {
    /// Instead of returning 0 for no storage, we explicitly check
    /// for the existance of storage.
    /// Note that this is better than folding hasStorage in to
    /// the return from this function, as this implementation generates
    /// no shortcircuiting blocks.
    _precondition(_base.hasStorage, "Cannot index empty buffer")
    return (index >= 0) & (index < _base.value.count)
  }

  /// How many elements the buffer can store without reallocation
  public var capacity: Int {
    return _base.hasStorage ? _base.value.capacity : 0
  }

  /// Copy the given subRange of this buffer into uninitialized memory
  /// starting at target.  Return a pointer past-the-end of the
  /// just-initialized memory.
  public func _uninitializedCopy(
    subRange: Range<Int>, target: UnsafeMutablePointer<T>
  ) -> UnsafeMutablePointer<T> {
    _sanityCheck(subRange.startIndex >= 0)
    _sanityCheck(subRange.endIndex >= subRange.startIndex)
    _sanityCheck(subRange.endIndex <= count)

    var dst = target
    var src = baseAddress + subRange.startIndex
    for i in subRange {
      dst++.initialize(src++.memory)
    }
    _fixLifetime(owner)
    return dst
  }

  /// Return a _SliceBuffer containing the given subRange of values
  /// from this buffer.
  public subscript(subRange: Range<Int>) -> _SliceBuffer<T>
  {
    return _SliceBuffer(
      owner: __bufferPointer.buffer,
      start: baseAddress + subRange.startIndex,
      count: subRange.endIndex - subRange.startIndex,
      hasNativeBuffer: true)
  }

  /// Return true iff this buffer's storage is uniquely-referenced.
  /// NOTE: this does not mean the buffer is mutable.  Other factors
  /// may need to be considered, such as whether the buffer could be
  /// some immutable Cocoa container.
  public mutating func isUniquelyReferenced() -> Bool {
    return __bufferPointer.holdsUniqueReference()
  }

  /// Returns true iff this buffer is mutable. NOTE: a true result
  /// does not mean the buffer is uniquely-referenced.
  public func isMutable() -> Bool {
    return true
  }

  /// Convert to an NSArray.
  /// Precondition: T is bridged to Objective-C
  /// O(1).
  public func _asCocoaArray() -> _NSArrayCoreType {
    _sanityCheck(
        _isBridgedToObjectiveC(T.self),
        "Array element type is not bridged to ObjectiveC")
    if count == 0 {
      return _SwiftDeferredNSArray(
        _nativeStorage: _emptyArrayStorage)
    }
    return _SwiftDeferredNSArray(_nativeStorage: _storage)
  }

  /// An object that keeps the elements stored in this buffer alive
  public var owner: AnyObject {
    return _storage
  }

  /// A value that identifies the storage used by the buffer.  Two
  /// buffers address the same elements when they have the same
  /// identity and count.
  public var identity: UnsafePointer<Void> {
    return withUnsafeBufferPointer { UnsafePointer($0.baseAddress) }
  }
  
  /// Return true iff we have storage for elements of the given
  /// `proposedElementType`.  If not, we'll be treated as immutable.
  func canStoreElementsOfDynamicType(proposedElementType: Any.Type) -> Bool {
    return _storage.canStoreElementsOfDynamicType(proposedElementType)
  }

  /// Return true if the buffer stores only elements of type `U`.
  /// Requires: `U` is a class or `@objc` existential. O(N)
  func storesOnlyElementsOfType<U>(
    _: U.Type
  ) -> Bool {
    _sanityCheck(_isClassOrObjCExistential(U.self))
    
    // Start with the base class so that optimizations based on
    // 'final' don't bypass dynamic type check.
    let s: _ContiguousArrayStorageBase? = _storage
    
    if _fastPath(s != nil){
      if _fastPath(s!.staticElementType is U.Type) {
        // Done in O(1)
        return true
      }
    }

    // Check the elements
    for x in self {
      if !(x is U) {
        return false
      }
    }
    return true
  }

  //===--- private --------------------------------------------------------===//
  var _storage: _ContiguousArrayStorageBase {
    return Builtin.castFromNativeObject(__bufferPointer._nativeBuffer)
  }

  typealias _Base = _HeapBuffer<_ArrayBody, T>
  var _base: _Base {
    return _Base(nativeStorage: __bufferPointer._nativeBuffer)
  }

  var __bufferPointer: ManagedBufferPointer<_ArrayBody, T>
}

/// Append the elements of rhs to lhs
public func += <
  T, C: CollectionType where C._Element == T
> (
  inout lhs: _ContiguousArrayBuffer<T>, rhs: C
) {
  let oldCount = lhs.count
  let newCount = oldCount + numericCast(count(rhs))

  if _fastPath(newCount <= lhs.capacity) {
    lhs.count = newCount
    (lhs.baseAddress + oldCount).initializeFrom(rhs)
  }
  else {
    var newLHS = _ContiguousArrayBuffer<T>(
      count: newCount,
      minimumCapacity: _growArrayCapacity(lhs.capacity))

    if lhs._base.hasStorage {
      newLHS.baseAddress.moveInitializeFrom(lhs.baseAddress, count: oldCount)
      lhs._base.value.count = 0
    }
    swap(&lhs, &newLHS)
    (lhs._base.baseAddress + oldCount).initializeFrom(rhs)
  }
}

/// Append rhs to lhs
public func += <T> (inout lhs: _ContiguousArrayBuffer<T>, rhs: T) {
  lhs += CollectionOfOne(rhs)
}

func === <T>(
  lhs: _ContiguousArrayBuffer<T>, rhs: _ContiguousArrayBuffer<T>
) -> Bool {
  return lhs._base == rhs._base
}

func !== <T>(
  lhs: _ContiguousArrayBuffer<T>, rhs: _ContiguousArrayBuffer<T>
) -> Bool {
  return lhs._base != rhs._base
}

extension _ContiguousArrayBuffer : CollectionType {
  /// The position of the first element in a non-empty collection.
  ///
  /// Identical to `endIndex` in an empty collection.
  public var startIndex: Int {
    return 0
  }
  /// The collection's "past the end" position.
  ///
  /// `endIndex` is not a valid argument to `subscript`, and is always
  /// reachable from `startIndex` by zero or more applications of
  /// `successor()`.
  public var endIndex: Int {
    return count
  }
  
  /// Return a *generator* over the elements of this *sequence*.
  ///
  /// Complexity: O(1)
  public func generate() -> IndexingGenerator<_ContiguousArrayBuffer> {
    return IndexingGenerator(self)
  }
}

public func ~> <
  S: _Sequence_Type
>(
  source: S, _: (_CopyToNativeArrayBuffer,())
) -> _ContiguousArrayBuffer<S.Generator.Element>
{
  let initialCapacity = source~>_underestimateCount()
  var result = _ContiguousArrayBuffer<S.Generator.Element>(
    count: 0, minimumCapacity: initialCapacity)

  // Using GeneratorSequence here essentially promotes the sequence to
  // a SequenceType from _Sequence_Type so we can iterate the elements
  for x in GeneratorSequence(source.generate()) {
    result += x
  }
  return result
}

public func ~> <
  C: protocol<_CollectionType, _Sequence_Type>
  where C._Element == C.Generator.Element
>(
  source: C, _:(_CopyToNativeArrayBuffer, ())
) -> _ContiguousArrayBuffer<C.Generator.Element>
{
  return _copyCollectionToNativeArrayBuffer(source)
}

func _copyCollectionToNativeArrayBuffer<
  C: protocol<_CollectionType, _Sequence_Type>
  where C._Element == C.Generator.Element
>(source: C) -> _ContiguousArrayBuffer<C.Generator.Element>
{
  let count: Int = numericCast(Swift.count(source))
  if count == 0 {
    return _ContiguousArrayBuffer()
  }

  var result = _ContiguousArrayBuffer<C.Generator.Element>(
    count: numericCast(count),
    minimumCapacity: 0
  )

  var p = result.baseAddress
  var i = source.startIndex
  for _ in 0..<count {
    (p++).initialize(source[i++])
  }
  _expectEnd(i, source)
  return result
}
