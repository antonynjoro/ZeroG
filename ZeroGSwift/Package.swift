// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ZeroG",
    platforms: [
        .macOS(.v14) // Sonoma — required for WhisperKit ANE optimization
    ],
    products: [
        .executable(name: "ZeroG", targets: ["ZeroG"]),
    ],
    dependencies: [
        // WhisperKit: On-device speech recognition via Neural Engine
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),

        // FluidAudio: SPIKE ONLY (branch spike/fluidaudio-parakeet) — NVIDIA Parakeet TDT
        // on the ANE, evaluated as a possible WhisperKit replacement. Remove if the spike
        // is rejected. See docs/spikes/fluidaudio-parakeet-spike.md.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.0"),
    ],
    targets: [
        .executableTarget(
            name: "ZeroG",
            dependencies: [
                "WhisperKit",
                .product(name: "FluidAudio", package: "FluidAudio"), // SPIKE — see deps note
            ],
            path: "ZeroG",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "ZeroGTests",
            dependencies: ["ZeroG"],
            path: "ZeroGTests"
        ),
    ]
)
