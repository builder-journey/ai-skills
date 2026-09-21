// Multi-Output Device 자동 생성 (Audio MIDI Setup의 GUI 4단계를 Core Audio API로 대체).
//
// 사용: swift setup-multi-output.swift
//
// 동작:
//   1. "MacBook Pro Speakers"와 "BlackHole 2ch" 장치 UID를 시스템에서 조회
//   2. AudioHardwareCreateAggregateDevice로 Multi-Output Device 생성
//      - 이름: "Multi-Output Device"
//      - Master: BlackHole 2ch (Chrome/Meet 호환을 위해 필수)
//      - 서브 장치: Speakers (drift compensation ON) + BlackHole (drift OFF)
//      - Stacked: true → Aggregate가 아니라 Multi-Output Device로 표시
//
// 종료 코드: 0=성공, 1=장치 미발견 또는 API 실패
// 이미 존재하면 0 반환 (idempotent).

import CoreAudio
import Foundation

let TARGET_NAME = "Multi-Output Device"
let SPEAKERS_NAME_HINT = "Speakers"   // "MacBook Pro Speakers" 또는 외장 스피커 이름에 매칭
let BLACKHOLE_NAME = "BlackHole 2ch"

// ─── 시스템 장치 목록 가져오기 ───
func allDeviceIDs() -> [AudioDeviceID] {
    var size = UInt32(0)
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size)
    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    var devices = [AudioDeviceID](repeating: 0, count: count)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &devices)
    return devices
}

func stringProperty(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
    var addr = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var cfString: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>>.size)
    let status = withUnsafeMutablePointer(to: &cfString) {
        AudioObjectGetPropertyData(device, &addr, 0, nil, &size, $0)
    }
    guard status == 0, let cf = cfString?.takeRetainedValue() else { return nil }
    return cf as String
}

// ─── 장치 검색 ───
struct DeviceInfo {
    let id: AudioDeviceID
    let name: String
    let uid: String
}

func findDevices() -> [DeviceInfo] {
    return allDeviceIDs().compactMap { id in
        guard let name = stringProperty(id, kAudioObjectPropertyName),
              let uid = stringProperty(id, kAudioDevicePropertyDeviceUID) else { return nil }
        return DeviceInfo(id: id, name: name, uid: uid)
    }
}

// ─── --remove 옵션 처리 ───
let args = CommandLine.arguments
if args.contains("--remove") || args.contains("-r") {
    let devices = findDevices()
    if let target = devices.first(where: { $0.name == TARGET_NAME }) {
        let status = AudioHardwareDestroyAggregateDevice(target.id)
        if status == 0 {
            print("✅ '\(TARGET_NAME)' 삭제 완료")
            exit(0)
        } else {
            fputs("❌ 삭제 실패 (OSStatus \(status))\n", stderr)
            exit(1)
        }
    } else {
        print("ℹ️ '\(TARGET_NAME)'가 이미 없음.")
        exit(0)
    }
}

// ─── 이미 Multi-Output Device가 있는지 확인 ───
let devices = findDevices()
if devices.contains(where: { $0.name == TARGET_NAME }) {
    print("ℹ️ '\(TARGET_NAME)' 이미 존재. 건너뜀. (재생성하려면 --remove 후 다시 실행)")
    exit(0)
}

// ─── 필수 장치 찾기 ───
guard let blackhole = devices.first(where: { $0.name == BLACKHOLE_NAME }) else {
    fputs("❌ '\(BLACKHOLE_NAME)' 장치를 찾을 수 없음.\n", stderr)
    fputs("   brew install blackhole-2ch 후 ⚠️ 재부팅 필요.\n", stderr)
    exit(1)
}

// Speakers는 이름이 정확히 일치하지 않을 수 있어 휴리스틱 적용:
//   1순위: 이름에 "Speakers" 포함하는 장치
//   2순위: 첫 번째 출력 장치 (BlackHole 제외)
let speakersCandidate = devices.first(where: {
    $0.name.contains(SPEAKERS_NAME_HINT) && $0.name != BLACKHOLE_NAME
})

guard let speakers = speakersCandidate else {
    fputs("❌ 출력 스피커 장치를 찾을 수 없음.\n", stderr)
    fputs("   사용 가능한 장치: \(devices.map { $0.name }.joined(separator: ", "))\n", stderr)
    exit(1)
}

print("📡 발견:")
print("   Speakers: \(speakers.name) (uid=\(speakers.uid))")
print("   BlackHole: \(blackhole.name) (uid=\(blackhole.uid))")

// ─── Multi-Output Device 생성 ───
let aggregateDescription: [String: Any] = [
    kAudioAggregateDeviceNameKey as String: TARGET_NAME,
    kAudioAggregateDeviceUIDKey as String: "com.rec-meeting.multi-output",
    // Master Device = BlackHole (Chrome/Meet이 Master로만 오디오를 보내는 이슈 해결)
    kAudioAggregateDeviceMasterSubDeviceKey as String: blackhole.uid,
    // 1 = Multi-Output Device (mirror sound), 0 = Aggregate Device (combine inputs)
    kAudioAggregateDeviceIsStackedKey as String: 1,
    kAudioAggregateDeviceSubDeviceListKey as String: [
        [
            kAudioSubDeviceUIDKey as String: speakers.uid,
            // 1 = Drift Correction ON (Master가 아닌 장치에 켜는 게 원칙)
            kAudioSubDeviceDriftCompensationKey as String: 1
        ],
        [
            kAudioSubDeviceUIDKey as String: blackhole.uid,
            kAudioSubDeviceDriftCompensationKey as String: 0
        ]
    ]
]

var newDeviceID: AudioDeviceID = 0
let status = AudioHardwareCreateAggregateDevice(
    aggregateDescription as CFDictionary,
    &newDeviceID
)

if status != 0 {
    fputs("❌ AudioHardwareCreateAggregateDevice 실패 (OSStatus \(status))\n", stderr)
    exit(1)
}

print("✅ '\(TARGET_NAME)' 생성 완료 (id=\(newDeviceID))")
print("   - Master: \(blackhole.name)")
print("   - Sub: \(speakers.name) (drift ON), \(blackhole.name) (drift OFF)")
exit(0)
