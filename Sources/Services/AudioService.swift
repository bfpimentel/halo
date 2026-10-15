import AudioToolbox
import CoreAudio
import Foundation

/// The default output device's volume and mute, from CoreAudio property listeners; follows device switches.
@MainActor
final class AudioService: Service {
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var publish: (@MainActor ([String: Any]) -> Void)?
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    private static let volume = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
    private static let mute = address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
    private static let name = address(kAudioObjectPropertyName)
    private static let defaultOutput = address(kAudioHardwarePropertyDefaultOutputDevice)

    func start(publish: @escaping @MainActor ([String: Any]) -> Void) {
        self.publish = publish
        listen(AudioObjectID(kAudioObjectSystemObject), Self.defaultOutput) { [weak self] in self?.bindDefaultDevice() }
        bindDefaultDevice()
    }

    func stop() {
        for (object, address, block) in listeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(object, &address, DispatchQueue.main, block)
        }
        listeners.removeAll()
        publish = nil
    }

    func perform(_ action: String, _ value: Any?) -> Bool {
        switch action {
        case "setVolume":
            guard let level = (value as? NSNumber)?.floatValue else { return false }
            return set(Self.volume, Float32(min(1, max(0, level))))
        case "setMuted":
            guard let muted = value as? Bool else { return false }
            return set(Self.mute, UInt32(muted ? 1 : 0))
        default:
            return false
        }
    }

    private func bindDefaultDevice() {
        listeners.removeAll { listener in
            guard listener.0 == device else { return false }
            var address = listener.1
            AudioObjectRemovePropertyListenerBlock(listener.0, &address, DispatchQueue.main, listener.2)
            return true
        }
        device = Self.read(AudioObjectID(kAudioObjectSystemObject), Self.defaultOutput) ?? AudioObjectID(kAudioObjectUnknown)
        for property in [Self.volume, Self.mute] { listen(device, property) { [weak self] in self?.refresh() } }
        refresh()
    }

    private func refresh() {
        let volume: Float32? = Self.read(device, Self.volume)
        let muted: UInt32? = Self.read(device, Self.mute)
        publish?([
            "volume": volume.map { Double($0) as Any } ?? NSNull(),
            "muted": (muted ?? 0) != 0,
            "adjustable": volume != nil,
            "device": deviceName().map { $0 as Any } ?? NSNull(),
        ])
    }

    private func deviceName() -> String? {
        var address = Self.name
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }

    private func listen(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ handler: @escaping @MainActor () -> Void) {
        var address = address
        guard object != kAudioObjectUnknown, AudioObjectHasProperty(object, &address) else { return }
        let block: AudioObjectPropertyListenerBlock = { _, _ in MainActor.assumeIsolated { handler() } }
        if AudioObjectAddPropertyListenerBlock(object, &address, DispatchQueue.main, block) == noErr {
            listeners.append((object, address, block))
        }
    }

    private func set<T: Numeric>(_ address: AudioObjectPropertyAddress, _ value: T) -> Bool {
        var address = address
        guard device != kAudioObjectUnknown, AudioObjectHasProperty(device, &address) else { return false }
        return withUnsafeBytes(of: value) { bytes in
            guard let base = bytes.baseAddress else { return false }
            return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(bytes.count), base) == noErr
        }
    }

    private static func read<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> T? {
        var address = address
        guard object != kAudioObjectUnknown, AudioObjectHasProperty(object, &address) else { return nil }
        var size = UInt32(MemoryLayout<T>.size)
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, value) == noErr else { return nil }
        return value.pointee
    }

    private static func address(
        _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
}
