// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "LockServer",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.92.4"),
        .package(url: "https://github.com/vapor/fluent-mysql-driver.git", from: "4.0.0"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.0.0"),
        .package(url: "https://github.com/vapor/jwt.git", from: "4.0.0"),
        .package(url: "https://github.com/Kitura/Swift-SMTP", from: "5.1.0")
    ],
    targets: [
        .target(
            name: "LockServerContracts",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "JWT", package: "jwt")
            ],
            path: "contracts/Sources/LockServerContracts",
            swiftSettings: swiftSettings
        ),
        .target(
            name: "LockServerCore",
            dependencies: [
                .target(name: "LockServerContracts"),
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentMySQLDriver", package: "fluent-mysql-driver")
            ],
            path: "shared/Sources/LockServerCore",
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "App",
            dependencies: [
                .target(name: "LockServerContracts"),
                .target(name: "LockServerCore"),
                .product(name: "Vapor", package: "vapor")
            ],
            path: "services/api-gateway/Sources/App",
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "AuthService",
            dependencies: [
                .target(name: "LockServerContracts"),
                .target(name: "LockServerCore"),
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentMySQLDriver", package: "fluent-mysql-driver"),
                .product(name: "JWT", package: "jwt"),
                .product(name: "SwiftSMTP", package: "Swift-SMTP")
            ],
            path: "services/auth-service/Sources/AuthService",
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "DirectoryService",
            dependencies: [
                .target(name: "LockServerContracts"),
                .target(name: "LockServerCore"),
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentMySQLDriver", package: "fluent-mysql-driver")
            ],
            path: "services/directory-service/Sources/DirectoryService",
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "AccessService",
            dependencies: [
                .target(name: "LockServerContracts"),
                .target(name: "LockServerCore"),
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentMySQLDriver", package: "fluent-mysql-driver")
            ],
            path: "services/access-service/Sources/AccessService",
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "DeviceService",
            dependencies: [
                .target(name: "LockServerContracts"),
                .target(name: "LockServerCore"),
                .product(name: "Vapor", package: "vapor")
            ],
            path: "services/device-service/Sources/DeviceService",
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "AttendanceAnalysisService",
            dependencies: [
                .target(name: "LockServerContracts"),
                .target(name: "LockServerCore"),
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentMySQLDriver", package: "fluent-mysql-driver")
            ],
            path: "services/attendance-analysis-service/Sources/AttendanceAnalysisService",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "LockServerTests",
            dependencies: [
                .target(name: "App"),
                .target(name: "AccessService"),
                .target(name: "AttendanceAnalysisService"),
                .target(name: "DeviceService"),
                .target(name: "LockServerCore"),
                .target(name: "LockServerContracts"),
                .product(name: "XCTVapor", package: "vapor")
            ],
            path: "Tests/LockServerTests",
            swiftSettings: swiftSettings
        )
    ]
)

var swiftSettings: [SwiftSetting] { [
    .enableUpcomingFeature("DisableOutwardActorInference"),
    .enableExperimentalFeature("StrictConcurrency"),
] }
