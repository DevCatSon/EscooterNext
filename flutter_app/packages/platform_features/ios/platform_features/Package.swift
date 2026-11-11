// swift-tools-version: 5.9
import PackageDescription
let package = Package(
  name: "platform_features",
  platforms: [.iOS("15.0")],
  products: [.library(name: "platform-features", targets: ["platform_features"])],
  dependencies: [.package(name: "FlutterFramework", path: "../FlutterFramework")],
  targets: [.target(name: "platform_features",
    dependencies: [.product(name: "FlutterFramework", package: "FlutterFramework")],
    resources: [.process("PrivacyInfo.xcprivacy")])]
)
