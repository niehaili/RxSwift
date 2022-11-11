//
//  Debug.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 5/2/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import Foundation

extension ObservableType {

    /**
     Prints received events for all observers on standard output.

     - seealso: [do operator on reactivex.io](http://reactivex.io/documentation/operators/do.html)

     - parameter identifier: Identifier that is printed together with event description to standard output.
     - parameter trimOutput: Should output be trimmed to max 40 characters.
     - returns: An observable sequence whose events are printed to standard output.
     */
    public func debug(_ identifier: String? = nil, trimOutput: Bool = false, file: String = #file, line: UInt = #line, function: String = #function)
        -> Observable<Element> {
            return Debug(source: self, identifier: identifier, trimOutput: trimOutput, file: file, line: line, function: function)
    }
}

private let dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

private func logEvent(_ identifier: String, dateFormat: DateFormatter, content: String) {
    print("\(dateFormat.string(from: Date())): \(identifier) -> \(content)")
}

final private class DebugSink<Source: ObservableType, Observer: ObserverType>: Sink<Observer>, ObserverType where Observer.Element == Source.Element {
    typealias Element = Observer.Element 
    typealias Parent = Debug<Source>
    
    private let parent: Parent
    private let timestampFormatter = DateFormatter()
    
    init(parent: Parent, observer: Observer, cancel: Cancelable) {
        self.parent = parent
        self.timestampFormatter.dateFormat = dateFormat
        super.init(observer: observer, cancel: cancel)
        
        logEvent(self.parent.identifier, dateFormat: self.timestampFormatter, content: "subscribed")
        MemoryLeakChecker.addObj(obj: self, identifier: self.parent.identifier)

    }
    
    func on(_ event: Event<Element>) {
        let maxEventTextLength = 40
        let eventText = "\(event)"

        let eventNormalized = (eventText.count > maxEventTextLength) && self.parent.trimOutput
            ? String(eventText.prefix(maxEventTextLength / 2)) + "..." + String(eventText.suffix(maxEventTextLength / 2))
            : eventText

        logEvent(self.parent.identifier, dateFormat: self.timestampFormatter, content: "Event \(eventNormalized)")

        self.forwardOn(event)
        if event.isStopEvent {
            self.dispose()
        }
    }
    
    override func dispose() {
        if !self.isDisposed {
            logEvent(self.parent.identifier, dateFormat: self.timestampFormatter, content: "isDisposed")
            MemoryLeakChecker.removeObj(obj: self)
        }
        super.dispose()
    }
}

final private class Debug<Source: ObservableType>: Producer<Source.Element> {
    fileprivate let identifier: String
    fileprivate let trimOutput: Bool
    private let source: Source

    init(source: Source, identifier: String?, trimOutput: Bool, file: String, line: UInt, function: String) {
        self.trimOutput = trimOutput
        if let identifier = identifier {
            self.identifier = identifier
        }
        else {
            let trimmedFile: String
            if let lastIndex = file.lastIndex(of: "/") {
                trimmedFile = String(file[file.index(after: lastIndex) ..< file.endIndex])
            }
            else {
                trimmedFile = file
            }
            self.identifier = "\(trimmedFile):\(line)"
        }
        self.source = source
    }
    
    override func run<Observer: ObserverType>(_ observer: Observer, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where Observer.Element == Source.Element {
        let sink = DebugSink(parent: self, observer: observer, cancel: cancel)
        let subscription = self.source.subscribe(sink)
        return (sink: sink, subscription: subscription)
    }
}

public class MemoryLeakChecker {
    public static var ignoreFileNames = [String]()
    private let lock = NSLock()
    private let unReleasedObjMap = NSMapTable<AnyObject, NSString>(keyOptions: .weakMemory)
    private static let instance = MemoryLeakChecker()

    public static func addObj(obj: AnyObject, identifier: String) {
        instance.lock.lock(); defer { instance.lock.unlock() }
        instance.unReleasedObjMap.setObject(identifier as NSString, forKey: obj)
    }
    
    public static func removeObj(obj: AnyObject) {
        instance.lock.lock(); defer { instance.lock.unlock() }
        instance.unReleasedObjMap.removeObject(forKey: obj)
   }
   
   public static func clearObjMap() {
       instance.lock.lock(); defer { instance.lock.unlock() }
       instance.unReleasedObjMap.removeAllObjects()
       print("🐬🐬🐬 清除未释放对象")
   }
    
    public static func printUnReleasedObjs() {
        print("===== 🐬🐬🐬 内存泄露输出开始=====")
        
        var values = [NSString]()
        let enumerator = instance.unReleasedObjMap.objectEnumerator()
        while let value = enumerator?.nextObject() as? NSString {
            values.append(value)
        }
        
        // 分组
        Dictionary(grouping: values, by: { $0 })
            .map { (key, value) in
            return "\(key):\(value.count)"
            }.sorted().filter { info in
                !ignoreFileNames.contains { info.hasPrefix("\($0).swift") }
            }.forEach { info in
            print(info)
        }
        print("===== 🐬🐬🐬 内存泄露输出结束=====")
    }
}
