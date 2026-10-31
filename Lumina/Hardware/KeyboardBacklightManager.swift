import AppKit
import ObjectiveC

@MainActor
final class KeyboardBacklightManager {
    static let shared = KeyboardBacklightManager()

    private var client: NSObject?
    private var keyboardID: UInt64 = 0
    private var isLoaded = false
    private var loadAttempted = false
    private(set) var isAvailable: Bool = false

    private let setBrightnessSel       = NSSelectorFromString("setBrightness:forKeyboard:")
    private let getBrightnessSel       = NSSelectorFromString("brightnessForKeyboard:")
    private let getKeyboardIDsSel      = NSSelectorFromString("copyKeyboardBacklightIDs")
    private let isAutoBrightnessSel    = NSSelectorFromString("isAutoBrightnessEnabledForKeyboard:")
    private let setAutoBrightnessSel   = NSSelectorFromString("enableAutoBrightness:forKeyboard:")

    private static let msgSend: UnsafeMutableRawPointer? = {
        guard let handle = dlopen(nil, RTLD_NOW) else { return nil }
        defer { dlclose(handle) }
        return dlsym(handle, "objc_msgSend")
    }()

    private init() {}

    @discardableResult
    func load() -> Bool {
        guard !loadAttempted else { return isLoaded }
        loadAttempted = true

        guard let bundle = Bundle(
            path: "/System/Library/PrivateFrameworks/CoreBrightness.framework"
        ), bundle.load() else {
            return false
        }

        guard let clientClass = NSClassFromString("KeyboardBrightnessClient")
                as? NSObject.Type else {
            return false
        }

        let instance = clientClass.init()

        guard Self.msgSend != nil,
              hasCompatibleMethod(on: instance, selector: getKeyboardIDsSel, returns: "@", arguments: []),
              hasCompatibleMethod(on: instance, selector: getBrightnessSel, returns: "f", arguments: ["Q"]),
              hasCompatibleMethod(on: instance, selector: setBrightnessSel, returns: "B", arguments: ["f", "Q"]),
              hasCompatibleMethod(on: instance, selector: isAutoBrightnessSel, returns: "B", arguments: ["Q"]),
              hasCompatibleMethod(on: instance, selector: setAutoBrightnessSel, returns: "B", arguments: ["B", "Q"]),
              let ids = instance.perform(getKeyboardIDsSel)?
                .takeRetainedValue() as? [NSNumber],
              let firstID = ids.first else {
            return false
        }

        client = instance
        keyboardID = firstID.uint64Value
        isLoaded = true
        isAvailable = true
        return true
    }

    // A selector can survive an OS update while its calling convention changes.
    // Refuse unfamiliar signatures before any unsafe function-pointer dispatch.
    private func hasCompatibleMethod(on instance: NSObject, selector: Selector,
                                     returns returnType: String, arguments: [String]) -> Bool {
        guard instance.responds(to: selector),
              let method = class_getInstanceMethod(type(of: instance), selector),
              method_getNumberOfArguments(method) == arguments.count + 2 else { return false }
        let resultType = method_copyReturnType(method)
        defer { free(resultType) }
        guard String(cString: resultType) == returnType else { return false }
        for (index, expected) in arguments.enumerated() {
            guard let actual = method_copyArgumentType(method, UInt32(index + 2)) else { return false }
            defer { free(actual) }
            guard String(cString: actual) == expected else { return false }
        }
        return true
    }

    var currentBrightness: Float? {
        guard isLoaded, let client, let msgSend = Self.msgSend, client.responds(to: getBrightnessSel) else {
            return nil
        }
        typealias GetFunc = @convention(c) (AnyObject, Selector, UInt64) -> Float
        let fn = unsafeBitCast(msgSend, to: GetFunc.self)
        let result = fn(client, getBrightnessSel, keyboardID)
        return result.isFinite ? min(max(result, 0), 1) : nil
    }

    var isAutoBrightnessEnabled: Bool? {
        guard isLoaded, let client, let msgSend = Self.msgSend,
              client.responds(to: isAutoBrightnessSel) else { return nil }
        typealias GetAutoFunc = @convention(c) (AnyObject, Selector, UInt64) -> Bool
        return unsafeBitCast(msgSend, to: GetAutoFunc.self)(client, isAutoBrightnessSel, keyboardID)
    }

    @discardableResult
    func setBrightness(_ level: Float) -> Bool {
        if !isLoaded {
            guard load() else { return false }
        }
        guard level.isFinite, let client, let msgSend = Self.msgSend, client.responds(to: setBrightnessSel) else {
            return false
        }
        let clamped = min(max(level, 0.0), 1.0)
        typealias SetFunc = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool
        let fn = unsafeBitCast(msgSend, to: SetFunc.self)
        return fn(client, setBrightnessSel, clamped, keyboardID)
    }

    @discardableResult
    func setAutoBrightnessEnabled(_ enabled: Bool) -> Bool {
        if !isLoaded {
            guard load() else { return false }
        }
        guard let client, let msgSend = Self.msgSend, client.responds(to: setAutoBrightnessSel) else {
            return false
        }
        typealias SetAutoFunc = @convention(c) (AnyObject, Selector, Bool, UInt64) -> Bool
        let fn = unsafeBitCast(msgSend, to: SetAutoFunc.self)
        return fn(client, setAutoBrightnessSel, enabled, keyboardID)
    }
}
