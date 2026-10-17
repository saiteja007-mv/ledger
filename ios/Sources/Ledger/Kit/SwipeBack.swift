import UIKit

/// Every screen hides the navigation bar to draw the kit's own top bar, and a hidden bar also switches off
/// UIKit's swipe-from-the-edge to go back. This turns the swipe back on for every navigation stack: it may
/// start whenever there is a screen to go back to.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
