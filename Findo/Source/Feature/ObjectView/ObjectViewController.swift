//
//  OrgVC.swift
//  Findo
//
//  Created by Mercen on 5/14/24.
//

import SwiftUI
import Vision
import AVFoundation

class ObjectViewController: NSViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    var bufferSize: CGSize = .zero
    
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private let videoDataOutput = AVCaptureVideoDataOutput()
    
    private let videoDataOutputQueue = DispatchQueue(
        label: "VideoDataOutput",
        qos: .userInitiated,
        attributes: [],
        autoreleaseFrequency: .workItem
    )
    private var detectionOverlay: CALayer!
    private var requests = [VNRequest]()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupAVCapture()
    }
    
    func startCaptureSession() {
        session.startRunning()
    }
    
    func teardownAVCapture() {
        previewLayer.removeFromSuperlayer()
        previewLayer = nil
    }
    
    @discardableResult
    func setupVision() -> NSError? {
        let error: NSError! = nil
        
        guard let modelURL = Bundle.main.url(
            forResource: "ObjectDetector",
            withExtension: "mlmodelc"
        ) else {
            return NSError(
                domain: "ObjectViewController",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Model file is missing"]
            )
        }
        do {
            let visionModel = try VNCoreMLModel(for: MLModel(contentsOf: modelURL))
            let objectRecognition = VNCoreMLRequest(model: visionModel) { (request, error) in
                DispatchQueue.main.async(execute: {
                    if let results = request.results {
                        self.drawVisionRequestResults(results)
                    }
                })
            }
            self.requests = [objectRecognition]
        } catch let error as NSError {
            print("Model loading went wrong: \(error)")
        }
        
        return error
    }
    
    func drawVisionRequestResults(_ results: [Any]) {
        CATransaction.begin()
        CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
        detectionOverlay.sublayers = nil
        for observation in results where observation is VNRecognizedObjectObservation {
            guard let objectObservation = observation as? VNRecognizedObjectObservation else {
                continue
            }
            
            let topLabelObservation = objectObservation.labels[0]
            let objectBounds = VNImageRectForNormalizedRect(
                objectObservation.boundingBox,
                Int(bufferSize.width),
                Int(bufferSize.height)
            )
            
            let shapeLayer = self.createRoundedRectLayerWithBounds(
                objectBounds,
                identifier: topLabelObservation.identifier
            )
            
            let textLayer = self.createTextSubLayerInBounds(
                objectBounds,
                identifier: topLabelObservation.identifier,
                confidence: topLabelObservation.confidence
            )
            shapeLayer.addSublayer(textLayer)
            detectionOverlay.addSublayer(shapeLayer)
        }
        self.updateLayerGeometry()
        CATransaction.commit()
    }
    
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try imageRequestHandler.perform(self.requests)
        } catch {
            print(error)
        }
    }
    
    func setupAVCapture() {
        var deviceInput: AVCaptureDeviceInput!
        
        let videoDevice = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .back
        ).devices.first
        do {
            deviceInput = try AVCaptureDeviceInput(device: videoDevice!)
        } catch {
            print("Could not create video device input: \(error)")
            return
        }
        
        session.beginConfiguration()
        session.sessionPreset = .vga640x480
        
        guard session.canAddInput(deviceInput) else {
            print("Could not add video device input to the session")
            session.commitConfiguration()
            return
        }
        session.addInput(deviceInput)
        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
            
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            videoDataOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String:
                    Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
            ]
            videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        } else {
            print("Could not add video data output to the session")
            session.commitConfiguration()
            return
        }
        let captureConnection = videoDataOutput.connection(with: .video)
        
        captureConnection?.isEnabled = true
        do {
            try  videoDevice!.lockForConfiguration()
            let dimensions = CMVideoFormatDescriptionGetDimensions(
                (videoDevice?.activeFormat.formatDescription)!
            )
            bufferSize.width = CGFloat(dimensions.width)
            bufferSize.height = CGFloat(dimensions.height)
            videoDevice!.unlockForConfiguration()
        } catch {
            print(error)
        }
        session.commitConfiguration()
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
        view.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        view.layer = view.makeBackingLayer()
        previewLayer.frame = view.layer!.bounds
        view.layer!.addSublayer(previewLayer)
        
        setupLayers()
        updateLayerGeometry()
        setupVision()
        startCaptureSession()
    }
    
    func setupLayers() {
        detectionOverlay = CALayer()
        detectionOverlay.name = "DetectionOverlay"
        detectionOverlay.bounds = CGRect(
            x: 0.0,
            y: 0.0,
            width: bufferSize.width,
            height: bufferSize.height)
        detectionOverlay.position = CGPoint(
            x: view.layer!.bounds.midX,
            y: view.layer!.bounds.midY
        )
        view.layer!.addSublayer(detectionOverlay)
    }
    
    func updateLayerGeometry() {
        let bounds = view.layer!.bounds
        var scale: CGFloat
        
        let xScale: CGFloat = bounds.size.width / bufferSize.height
        let yScale: CGFloat = bounds.size.height / bufferSize.width
        
        scale = fmax(xScale, yScale)
        if scale.isInfinite {
            scale = 1.0
        }
        CATransaction.begin()
        CATransaction.setValue(
            kCFBooleanTrue,
            forKey: kCATransactionDisableActions
        )
        
        detectionOverlay.setAffineTransform(
            CGAffineTransform(rotationAngle: CGFloat(.pi / 2.0))
                .scaledBy(x: scale, y: -scale)
        )
        detectionOverlay.position = CGPoint(x: bounds.midX, y: bounds.midY)
        
        CATransaction.commit()
        
    }
    
    func createTextSubLayerInBounds(
        _ bounds: CGRect,
        identifier: String,
        confidence: VNConfidence
    ) -> CATextLayer {
        let textLayer = CATextLayer()
        textLayer.name = "Object Label"
        let formattedString = NSMutableAttributedString(
            string: String(format: "\(identifier)\n일치율: %.2f", confidence)
        )
        let largeFont = NSFont(name: "Helvetica", size: 24.0)!
        formattedString.addAttributes(
            [NSAttributedString.Key.font: largeFont],
            range: NSRange(location: 0, length: identifier.count)
        )
        textLayer.string = formattedString
        textLayer.bounds = CGRect(
            x: 0,
            y: 0,
            width: bounds.size.height - 10,
            height: bounds.size.width - 10
        )
        textLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        textLayer.foregroundColor = CGColor(
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            components: [0.0, 0.0, 0.0, 1.0]
        )
        textLayer.contentsScale = 2.0
        textLayer.setAffineTransform(
            CGAffineTransform(rotationAngle: CGFloat(.pi / 2.0))
                .scaledBy(x: 1.0, y: -1.0)
        )
        return textLayer
    }
    
    func createRoundedRectLayerWithBounds(
        _ bounds: CGRect,
        identifier: String
    ) -> CALayer {
        let shapeLayer = CALayer()
        shapeLayer.bounds = bounds
        shapeLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        shapeLayer.name = "Found Object"
        shapeLayer.borderWidth = 5.0
        shapeLayer.borderColor = CGColor(
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            components: [1.0, 1.0, 0.2, 1.0]
        )
        shapeLayer.cornerRadius = 7
        return shapeLayer
    }
}
