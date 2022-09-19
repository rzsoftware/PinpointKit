//
//  BlurAnnotationView.swift
//  Pinpoint
//
//  Created by Caleb Davenport on 3/30/15.
//  Copyright (c) 2015 Lickability. All rights reserved.
//

import UIKit
import MetalKit
import CoreImage

/// The default blur annotation view.
open class BlurAnnotationView: AnnotationView, MTKViewDelegate {

    // MARK: - Properties

    private let commandQueue: MTLCommandQueue?
    private let mtkView: MTKView?
    private let ciContext: CIContext?

    /// The corresponding annotation.
    var annotation: BlurAnnotation? {
        didSet {
            setNeedsDisplay()

            let layer = CAShapeLayer()
            if let annotationFrame = annotationFrame {
                layer.path = UIBezierPath(rect: annotationFrame).cgPath
            }

            mtkView?.layer.mask = layer
            mtkView?.drawableSize = annotation?.image.extent.size ?? .zero
        }
    }

    /// Whether to draw a border on the blur view.
    var drawsBorder = false {
        didSet {
            if drawsBorder != oldValue {
                setNeedsDisplay()
            }
        }
    }

    override var annotationFrame: CGRect? {
        return annotation?.frame
    }

    private var touchTargetFrame: CGRect? {
        guard let annotationFrame = annotationFrame else { return nil }

        let size = frame.size
        let maximumWidth = max(4.0, min(size.width, size.height) * 0.075)
        let outsideStrokeWidth = min(maximumWidth, 14.0) * 1.5

        return annotationFrame.inset(
            by: UIEdgeInsets(
                top: -outsideStrokeWidth,
                left: -outsideStrokeWidth,
                bottom: -outsideStrokeWidth,
                right: -outsideStrokeWidth
            )
        )
    }

    // MARK: - Initializers

    public convenience init() {
        self.init(frame: CGRect.zero)
    }

    public override init(frame: CGRect) {
        let bounds = CGRect(origin: CGPoint.zero, size: frame.size)

        if let MTLDevice = MTLCreateSystemDefaultDevice() {
            commandQueue = MTLDevice.makeCommandQueue()
            mtkView = MetalKit.MTKView(frame: bounds, device: MTLDevice)
            ciContext = CoreImage.CIContext(
                mtlDevice: MTLDevice,
                options: [.useSoftwareRenderer: false]
            )
        } else {
            commandQueue = nil
            mtkView = nil
            ciContext = nil
        }

        super.init(frame: frame)

        isOpaque = false

        mtkView?.isUserInteractionEnabled = false
        mtkView?.delegate = self
        mtkView?.contentMode = .redraw
        mtkView?.enableSetNeedsDisplay = true
        mtkView?.framebufferOnly = false

        if let mtkView = mtkView {
            addSubview(mtkView)
        }
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UIView

    override open func layoutSubviews() {
        super.layoutSubviews()
        mtkView?.frame = bounds
    }

    override open func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return touchTargetFrame?.contains(point) ?? false
    }

    override open func draw(_ rect: CGRect) {
        super.draw(rect)

        if drawsBorder {
            guard let context = UIGraphicsGetCurrentContext() else { return }

            tintColor?.withAlphaComponent(type(of: self).BorderAlpha).setStroke()

            // Since this draws under the MTKView, and strokes extend both inside and outside, we have to double the intended width.
            let strokeWidth: CGFloat = 1.0
            context.setLineWidth(strokeWidth * 2.0)

            let rect = annotationFrame ?? CGRect.zero
            context.stroke(rect)
        }
    }

    // MARK: - AnnotationView

    override func setSecondControlPoint(_ point: CGPoint) {
        guard let previousAnnotation = annotation else { return }

        annotation = BlurAnnotation(
            startLocation: previousAnnotation.startLocation,
            endLocation: point,
            image: previousAnnotation.image
        )
    }

    override func move(controlPointsBy translationAmount: CGPoint) {
        guard let previousAnnotation = annotation else { return }
        let startLocation = CGPoint(
            x: previousAnnotation.startLocation.x + translationAmount.x,
            y: previousAnnotation.startLocation.y + translationAmount.y
        )
        let endLocation = CGPoint(
            x: previousAnnotation.endLocation.x + translationAmount.x,
            y: previousAnnotation.endLocation.y + translationAmount.y
        )

        annotation = BlurAnnotation(
            startLocation: startLocation,
            endLocation: endLocation,
            image: previousAnnotation.image
        )
    }

    override func scale(controlPointsBy scaleFactor: CGFloat) {
        guard let previousAnnotation = annotation else { return }
        let startLocation = previousAnnotation.scaledPoint(
            previousAnnotation.startLocation,
            scale: scaleFactor
        )
        let endLocation = previousAnnotation.scaledPoint(
            previousAnnotation.endLocation,
            scale: scaleFactor
        )

        annotation = BlurAnnotation(
            startLocation: startLocation,
            endLocation: endLocation,
            image: previousAnnotation.image
        )
    }

    // MARK: - MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    }

    public func draw(in view: MTKView) {
        guard
            let ciContext = self.ciContext,
            var image = annotation?.blurredImage,
            let drawable = view.currentDrawable
        else { return }

        // A workaround to resolve the issue of image flipping vertically when run in the simulator
        #if targetEnvironment(simulator)
        image = image
            .transformed(by: CGAffineTransform(scaleX: 1, y: -1))
            .transformed(by: CGAffineTransform(translationX: 0, y: image.extent.height))
        #endif

        let commandBuffer = commandQueue?.makeCommandBuffer()
        let drawableRect = CGRect(origin: CGPoint.zero, size: view.drawableSize)
        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        ciContext.render(
            image,
            to: drawable.texture,
            commandBuffer: commandBuffer,
            bounds: drawableRect,
            colorSpace: colorSpace
        )
        commandBuffer?.present(drawable)
        commandBuffer?.commit()
        commandBuffer?.waitUntilCompleted()
    }
}
