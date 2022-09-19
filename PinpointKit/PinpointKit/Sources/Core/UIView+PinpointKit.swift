//
//  UIView+PinpointKit.swift
//  Pods
//
//  Created by Kenneth Parker Ackerson on 4/25/16.
//
//

import UIKit

/// Extends `UIView` to take a snapshot of the screen.
extension UIView {
    
    /// The `UIImage` representation of this view at the time of access.
    var pinpoint_screenshot: UIImage? {
        UIGraphicsBeginImageContextWithOptions(bounds.size, true, 0)
        defer { UIGraphicsEndImageContext() }

        drawHierarchy(in: bounds, afterScreenUpdates: true)
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}
