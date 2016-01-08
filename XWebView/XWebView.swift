/*
 Copyright 2015 XWebView

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
*/

import Foundation
import ObjectiveC
import WebKit

@available(iOS 8.0, *)
extension WKWebView {
    public func loadPlugin(object: AnyObject, namespace: String) -> XWVScriptObject? {
        let channel = XWVChannel(name: nil, webView: self)
        return channel.bindPlugin(object, toNamespace: namespace)
    }

    func prepareForPlugin() {
        let key = unsafeAddressOf(XWVChannel)
        if objc_getAssociatedObject(self, key) != nil { return }

        let bundle = NSBundle(forClass: XWVChannel.self)
        guard let path = bundle.pathForResource("xwebview", ofType: "js"),
            let source = try? NSString(contentsOfFile: path, encoding: NSUTF8StringEncoding) else {
            preconditionFailure("FATAL: Internal error")
        }
        let time = WKUserScriptInjectionTime.AtDocumentStart
        let script = WKUserScript(source: source as String, injectionTime: time, forMainFrameOnly: true)
        let xwvplugin = XWVUserScript(webView: self, script: script, namespace: "XWVPlugin")
        objc_setAssociatedObject(self, key, xwvplugin, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

@available(iOS 8.0, *)
extension WKWebView {
    // Synchronized evaluateJavaScript
    public func evaluateJavaScript(script: String, error: NSErrorPointer = nil) -> AnyObject? {
        var result: AnyObject?
        var done = false
        let timeout = 3.0
        if NSThread.isMainThread() {
            evaluateJavaScript(script) {
                (obj: AnyObject?, err: NSError?)->Void in
                result = obj
                if error != nil {
                    error.memory = err
                }
                done = true
            }
            while !done {
                let reason = CFRunLoopRunInMode(kCFRunLoopDefaultMode, timeout, true)
                if reason != CFRunLoopRunResult.HandledSource {
                    break
                }
            }
        } else {
            let condition: NSCondition = NSCondition()
            dispatch_async(dispatch_get_main_queue()) {
                [weak self] in
                self?.evaluateJavaScript(script) {
                    (obj: AnyObject?, err: NSError?)->Void in
                    condition.lock()
                    result = obj
                    if error != nil {
                        error.memory = err
                    }
                    done = true
                    condition.signal()
                    condition.unlock()
                }
            }
            condition.lock()
            while !done {
                if !condition.waitUntilDate(NSDate(timeIntervalSinceNow: timeout)) {
                    break
                }
            }
            condition.unlock()
        }
        if !done {
            print("<XWV> ERROR: Timeout to evaluate script.")
        }
        return result
    }
}
