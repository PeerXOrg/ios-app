import SwiftUI

public enum Spacing {
    public static let tight: CGFloat = 8
    public static let element: CGFloat = 12
    public static let group: CGFloat = 16
    public static let section: CGFloat = 24
    public static let large: CGFloat = 32
    public static let hero: CGFloat = 48

    public static let edge: CGFloat = section
}

public enum ContentWidth {
    public static let form: CGFloat = 400
    public static let content: CGFloat = 440
    public static let text: CGFloat = 320
}

public enum Radius {
    public static let field: CGFloat = 14
    public static let button: CGFloat = 16
    public static let card: CGFloat = 24
}

public enum ControlSize {
    public static let height: CGFloat = 52
}

extension View {
    func peerxPageInset() -> some View {
        self.padding(.horizontal, Spacing.edge)
    }
}
