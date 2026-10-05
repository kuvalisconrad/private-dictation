import CoreAudio

/// AVAudioRecorder on macOS uses the system's default input. Choose a real
/// built-in input before creating it; never fall back to a headset microphone.
enum BuiltInMicrophone {
    static func selectDefault() -> Bool {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var devicesAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &devicesAddress, 0, nil, &size) == noErr,
              size > 0, size % UInt32(MemoryLayout<AudioDeviceID>.size) == 0 else { return false }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        let status = devices.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(system, &devicesAddress, 0, nil, &size, $0.baseAddress!)
        }
        guard status == noErr, var selected = devices.first(where: isBuiltInInput) else { return false }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var current: AudioDeviceID = 0
        size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &current) == noErr else { return false }
        if current == selected { return true }
        var writable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(system, &address, &writable) == noErr, writable.boolValue,
              AudioObjectSetPropertyData(system, &address, 0, nil, size, &selected) == noErr else { return false }
        return AudioObjectGetPropertyData(system, &address, 0, nil, &size, &current) == noErr && current == selected
    }

    private static func isBuiltInInput(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var transport: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr,
              transport == kAudioDeviceTransportTypeBuiltIn else { return false }
        address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                             mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioBufferList>.size else { return false }
        let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, storage) == noErr else { return false }
        let buffers = UnsafeMutableAudioBufferListPointer(storage.assumingMemoryBound(to: AudioBufferList.self))
        return buffers.contains { $0.mNumberChannels > 0 }
    }
}
