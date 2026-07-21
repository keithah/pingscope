import Foundation

public struct HostDisplayColor: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public var validatedComponents: HostDisplayColor? {
        guard red.isFinite, green.isFinite, blue.isFinite,
              (0...1).contains(red), (0...1).contains(green), (0...1).contains(blue) else {
            return nil
        }
        return self
    }
}
