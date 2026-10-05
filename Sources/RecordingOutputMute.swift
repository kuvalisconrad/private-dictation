import Foundation
import CoreAudio

struct AudioOutputControl: Hashable {
    enum Kind { case mute, volume }
    let device: AudioDeviceID
    let element: AudioObjectPropertyElement
    let kind: Kind
    var silentValue: Float32 { kind == .mute ? 1 : 0 }
}

protocol AudioOutputAccess {
    func controls() -> [AudioOutputControl]?
    func read(_ control: AudioOutputControl) -> Float32?
    func write(_ value: Float32, to control: AudioOutputControl) -> Bool
}

/// Keeps only output-control state, never audio. New routes are remembered
/// before muting; stopping restores each route's original state.
final class OutputMuteSession {
    private let access: AudioOutputAccess
    private var originals: [AudioOutputControl: Float32] = [:]
    init(access: AudioOutputAccess) { self.access = access }

    @discardableResult func reassert() -> Bool {
        guard let controls = access.controls(), !controls.isEmpty else { return false }
        var success = true
        for control in controls {
            guard let value = access.read(control) else { success = false; continue }
            if originals[control] == nil { originals[control] = value }
            if value != control.silentValue {
                if !access.write(control.silentValue, to: control) || access.read(control) != control.silentValue {
                    success = false
                }
            }
        }
        return success
    }

    @discardableResult func restore() -> Bool {
        var success = true
        for (control, original) in originals {
            // Preserve a manual adjustment made after our last mute update.
            if access.read(control) == control.silentValue, original != control.silentValue {
                if !access.write(original, to: control) { success = false }
            }
        }
        originals.removeAll()
        return success
    }
}

struct CoreAudioOutputAccess: AudioOutputAccess {
    private func address(_ control: AudioOutputControl) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: control.kind == .mute ? kAudioDevicePropertyMute : kAudioDevicePropertyVolumeScalar,
                                   mScope: kAudioObjectPropertyScopeOutput, mElement: control.element)
    }
    private func settable(_ control: AudioOutputControl) -> Bool {
        var address = address(control), writable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(control.device, &address, &writable) == noErr && writable.boolValue
    }

    func controls() -> [AudioOutputControl]? {
        var devices = Set<AudioDeviceID>()
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice] {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            var device: AudioDeviceID = 0, size = UInt32(MemoryLayout<AudioDeviceID>.size)
            if AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
               device != kAudioObjectUnknown { devices.insert(device) }
        }
        guard !devices.isEmpty else { return nil }
        var result: [AudioOutputControl] = []
        for device in devices {
            let masterMute = AudioOutputControl(device: device, element: kAudioObjectPropertyElementMain, kind: .mute)
            if settable(masterMute), read(masterMute) != nil { result.append(masterMute); continue }
            let masterVolume = AudioOutputControl(device: device, element: kAudioObjectPropertyElementMain, kind: .volume)
            if settable(masterVolume), read(masterVolume) != nil { result.append(masterVolume); continue }
            // Devices without a master control may expose channel controls.
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                     mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            var size: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size >= MemoryLayout<AudioBufferList>.size else { return nil }
            let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
            defer { storage.deallocate() }
            guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, storage) == noErr else { return nil }
            let buffers = UnsafeMutableAudioBufferListPointer(storage.assumingMemoryBound(to: AudioBufferList.self))
            let channels = buffers.reduce(UInt32(0)) { $0 + $1.mNumberChannels }
            guard channels > 0 else { return nil }
            for channel in 1...channels {
                let mute = AudioOutputControl(device: device, element: channel, kind: .mute)
                let volume = AudioOutputControl(device: device, element: channel, kind: .volume)
                if settable(mute), read(mute) != nil { result.append(mute) }
                else if settable(volume), read(volume) != nil { result.append(volume) }
                else { return nil }
            }
        }
        return result
    }

    func read(_ control: AudioOutputControl) -> Float32? {
        var address = address(control), size: UInt32 = 4
        if control.kind == .mute {
            var value: UInt32 = 0
            return AudioObjectGetPropertyData(control.device, &address, 0, nil, &size, &value) == noErr ? Float32(value) : nil
        }
        var value: Float32 = 0
        return AudioObjectGetPropertyData(control.device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }
    func write(_ value: Float32, to control: AudioOutputControl) -> Bool {
        var address = address(control)
        if control.kind == .mute {
            var value = UInt32(value)
            return AudioObjectSetPropertyData(control.device, &address, 0, nil, 4, &value) == noErr
        }
        var value = value
        return AudioObjectSetPropertyData(control.device, &address, 0, nil, 4, &value) == noErr
    }
}

final class RecordingOutputMute {
    private let session = OutputMuteSession(access: CoreAudioOutputAccess())
    private var timer: Timer?
    private var pendingRestore: DispatchWorkItem?
    private var listener: AudioObjectPropertyListenerBlock?
    private var active = false
    private let selectors = [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice]

    func begin() -> Bool {
        pendingRestore?.cancel(); pendingRestore = nil
        guard session.reassert() else { stopImmediately(); return false }
        guard !active else { return true }
        active = true
        let callback: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.reassert() }
        listener = callback
        for selector in selectors {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, callback)
        }
        // Bluetooth profile changes can reset controls without changing the
        // default device. Recheck while recording, never while idle.
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.reassert() }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
        return true
    }
    func reassert() { if active { session.reassert() } }
    func end() {
        pendingRestore?.cancel()
        // Let the headset leave its microphone mode before resuming playback.
        let task = DispatchWorkItem { [weak self] in self?.stopImmediately() }
        pendingRestore = task; DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: task)
    }
    func stopImmediately() {
        pendingRestore?.cancel(); pendingRestore = nil
        active = false; timer?.invalidate(); timer = nil
        if let callback = listener {
            for selector in selectors {
                var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                         mElement: kAudioObjectPropertyElementMain)
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, callback)
            }
        }
        listener = nil; session.restore()
    }
}
