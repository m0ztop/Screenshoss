#!/usr/bin/env swift

import Foundation

let sampleRate = 48_000
let duration = 0.36
let sampleCount = Int(Double(sampleRate) * duration)
let outputPath = CommandLine.arguments.dropFirst().first ?? "Assets/screenshot-delete.wav"

var randomState: UInt64 = 0x53484F5353
var leftUpperLowPass = 0.0
var leftLowerLowPass = 0.0
var rightUpperLowPass = 0.0
var rightLowerLowPass = 0.0
var leftSamples = [Int16]()
var rightSamples = [Int16]()
leftSamples.reserveCapacity(sampleCount)
rightSamples.reserveCapacity(sampleCount)

func smoothStep(_ value: Double) -> Double {
    let clamped = min(max(value, 0), 1)
    return clamped * clamped * (3 - 2 * clamped)
}

func nextNoise() -> Double {
    randomState = randomState &* 6_364_136_223_846_793_005 &+ 1
    let unit = Double((randomState >> 40) & 0xFFFFFF) / Double(0xFFFFFF)
    return unit * 2 - 1
}

for index in 0..<sampleCount {
    let time = Double(index) / Double(sampleRate)
    let progress = min(time / duration, 1)
    let attack = smoothStep(progress / 0.42)
    let release = 1 - smoothStep((progress - 0.42) / 0.58)
    let envelope = pow(attack * release, 1.25)

    let sharedNoise = nextNoise()
    let leftNoise = sharedNoise * 0.82 + nextNoise() * 0.18
    let rightNoise = sharedNoise * 0.82 + nextNoise() * 0.18
    let upperCutoff = 1_050 + 2_700 * smoothStep(progress)
    let lowerCutoff = 170 + 720 * smoothStep(progress)
    let upperAlpha = 1 - exp(-2 * .pi * upperCutoff / Double(sampleRate))
    let lowerAlpha = 1 - exp(-2 * .pi * lowerCutoff / Double(sampleRate))

    leftUpperLowPass += upperAlpha * (leftNoise - leftUpperLowPass)
    leftLowerLowPass += lowerAlpha * (leftNoise - leftLowerLowPass)
    rightUpperLowPass += upperAlpha * (rightNoise - rightUpperLowPass)
    rightLowerLowPass += lowerAlpha * (rightNoise - rightLowerLowPass)

    let centerPull = 1 + 0.16 * smoothStep(progress)
    let leftAir = (leftUpperLowPass - leftLowerLowPass) * envelope * centerPull
    let rightAir = (rightUpperLowPass - rightLowerLowPass) * envelope * centerPull
    let leftSoftened = tanh(leftAir * 1.15) * 0.30
    let rightSoftened = tanh(rightAir * 1.15) * 0.30

    leftSamples.append(
        Int16((min(max(leftSoftened, -1), 1) * Double(Int16.max)).rounded())
    )
    rightSamples.append(
        Int16((min(max(rightSoftened, -1), 1) * Double(Int16.max)).rounded())
    )
}

func appendASCII(_ string: String, to data: inout Data) {
    data.append(string.data(using: .ascii)!)
}

func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
    var littleEndianValue = value.littleEndian
    withUnsafeBytes(of: &littleEndianValue) { bytes in
        data.append(contentsOf: bytes)
    }
}

let channelCount: UInt16 = 2
let bitsPerSample: UInt16 = 16
let bytesPerSample = Int(bitsPerSample / 8)
let dataByteCount = leftSamples.count * Int(channelCount) * bytesPerSample
var wave = Data()

appendASCII("RIFF", to: &wave)
appendLittleEndian(UInt32(36 + dataByteCount), to: &wave)
appendASCII("WAVE", to: &wave)
appendASCII("fmt ", to: &wave)
appendLittleEndian(UInt32(16), to: &wave)
appendLittleEndian(UInt16(1), to: &wave)
appendLittleEndian(channelCount, to: &wave)
appendLittleEndian(UInt32(sampleRate), to: &wave)
appendLittleEndian(UInt32(sampleRate * Int(channelCount) * bytesPerSample), to: &wave)
appendLittleEndian(UInt16(Int(channelCount) * bytesPerSample), to: &wave)
appendLittleEndian(bitsPerSample, to: &wave)
appendASCII("data", to: &wave)
appendLittleEndian(UInt32(dataByteCount), to: &wave)

for index in 0..<leftSamples.count {
    appendLittleEndian(leftSamples[index], to: &wave)
    appendLittleEndian(rightSamples[index], to: &wave)
}

let outputURL = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try wave.write(to: outputURL, options: .atomic)
print("Generated \(outputURL.path) (\(duration)s, \(sampleRate) Hz, stereo PCM)")
