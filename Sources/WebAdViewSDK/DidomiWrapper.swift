import SwiftUI
import Didomi

class DidomiViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        Didomi.shared.setupUI(containerController: self)
    }
}

/// Hosts the Didomi consent UI. Place one in your view hierarchy (e.g. as a
/// `.background(DidomiWrapper())`) so Didomi has a UIViewController to
/// present notices and preferences from.
public struct DidomiWrapper: UIViewControllerRepresentable {
    public init() {}
    public func makeUIViewController(context: Context) -> UIViewController {
        DidomiViewController()
    }
    public func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
