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
        
        // Google Generative AI: Optional Gemini API for text polishing
        .package(url: "https://github.com/google-gemini/generative-ai-swift.git", from: "0.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "ZeroG",
            dependencies: [
                "WhisperKit",
                .product(name: "GoogleGenerativeAI", package: "generative-ai-swift"),
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
