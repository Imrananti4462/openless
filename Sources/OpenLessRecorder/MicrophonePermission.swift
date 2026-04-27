import AVFAudio

public enum MicrophonePermission {
    public static func isGranted() -> Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }

    public static func request() async -> Bool {
        await withCheckedContinuation { continuation in
            let lock = NSLock()
            var didResume = false

            func resumeOnce(_ granted: Bool) {
                lock.lock()
                guard !didResume else {
                    lock.unlock()
                    return
                }
                didResume = true
                lock.unlock()
                continuation.resume(returning: granted)
            }

            DispatchQueue.global(qos: .userInitiated).async {
                AVAudioApplication.requestRecordPermission { granted in
                    resumeOnce(granted)
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                resumeOnce(false)
            }
        }
    }

    public static var statusDescription: String {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return "granted"
        case .denied: return "denied"
        case .undetermined: return "undetermined"
        @unknown default: return "unknown"
        }
    }
}
