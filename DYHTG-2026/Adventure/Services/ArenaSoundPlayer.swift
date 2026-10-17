import AVFoundation
import Foundation

/// Small, locally generated cues: no downloaded assets, microphone, or network access.
@MainActor
final class ArenaSoundPlayer {
  static let shared = ArenaSoundPlayer()
  static let preferenceKey = "arena.soundEffectsEnabled"

  enum Cue: String, CaseIterable {
    case tap, success, levelUp, tryAgain
    var notes: [(frequency: Double, duration: Double)] {
      switch self {
      case .tap: [(880, 0.035)]
      case .success: [(659.25, 0.08), (783.99, 0.08), (1046.5, 0.14)]
      case .levelUp: [(523.25, 0.08), (659.25, 0.08), (783.99, 0.10), (1046.5, 0.18)]
      case .tryAgain: [(440, 0.07)]
      }
    }
  }

  private var player: AVAudioPlayer?
  private var finishTask: Task<Void, Never>?
  private var sessionActive = false
  private var sounds: [Cue: Data] = [:]

  private init() {}

  @discardableResult
  func play(_ cue: Cue) -> Bool {
    let defaults = UserDefaults.standard
    guard
      defaults.object(forKey: Self.preferenceKey) == nil
        || defaults.bool(forKey: Self.preferenceKey)
    else { return false }
    do {
      let session = AVAudioSession.sharedInstance()
      if !sessionActive {
        // Ambient respects the Ring/Silent switch and mixes with music and VoiceOver.
        try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
        sessionActive = true
      }
      finishTask?.cancel()
      player?.stop()
      let data = sounds[cue] ?? Self.wave(for: cue)
      sounds[cue] = data
      let next = try AVAudioPlayer(data: data, fileTypeHint: AVFileType.wav.rawValue)
      next.volume = 0.55
      next.prepareToPlay()
      guard next.play() else {
        stop()
        return false
      }
      player = next
      let duration = next.duration
      finishTask = Task { [weak self] in
        do { try await Task.sleep(for: .seconds(duration + 0.08)) } catch { return }
        guard !Task.isCancelled else { return }
        self?.stop()
      }
      return true
    } catch {
      stop()
      return false  // Sound must never block a button action or a saved reward.
    }
  }

  func stop() {
    finishTask?.cancel()
    finishTask = nil
    player?.stop()
    player = nil
    if sessionActive {
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
      sessionActive = false
    }
  }

  /// Mono PCM, with short attack/release envelopes to avoid sharp clicks.
  private static func wave(for cue: Cue) -> Data {
    let rate = 22_050
    var samples: [Int16] = []
    for note in cue.notes {
      let count = Int(note.duration * Double(rate))
      for frame in 0..<count {
        let time = Double(frame) / Double(rate)
        let attack = min(1, time / 0.004)
        let release = min(1, (note.duration - time) / 0.008)
        let decay = exp(-4 * time / note.duration)
        let phase = 2 * Double.pi * note.frequency * time
        let tone = sin(phase) + 0.18 * sin(phase * 2)
        let value = tone * attack * release * decay * 0.18
        samples.append(Int16((value * Double(Int16.max)).rounded()))
      }
      samples.append(contentsOf: repeatElement(0, count: Int(Double(rate) * 0.012)))
    }
    var data = Data()
    func append<T: FixedWidthInteger>(_ value: T) {
      var little = value.littleEndian
      withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }
    let byteCount = UInt32(samples.count * 2)
    data.append(contentsOf: "RIFF".utf8)
    append(byteCount + 36)
    data.append(contentsOf: "WAVEfmt ".utf8)
    append(UInt32(16))
    append(UInt16(1))
    append(UInt16(1))
    append(UInt32(rate))
    append(UInt32(rate * 2))
    append(UInt16(2))
    append(UInt16(16))
    data.append(contentsOf: "data".utf8)
    append(byteCount)
    for sample in samples { append(sample) }
    return data
  }
}
