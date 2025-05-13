import UIKit //grafikus interface
import AVFoundation
/*
 Kamera hozzáférés:
 - adatfolyam kezelés: AVCaptureSession, AVCaptureDevice
 - képkockák streamelése: AVCaptureVideoDataOutputSampleBufferDelegate
 - kamerakép orientációja: AVCaptureConnection.videoOrientation
 - élő kamerakép megjelenítése a guihoz AVCaptureVideoPreviewLayer
 */
import Vision
/*
 - OCR: VNRecognizeTextRequest
 - VNImageRequestHandler: kamera képen szövegkeresés
 - bounding bocok lekérése: VNRecognizedTextObservation
 - karakterek döntési szögeinek lekérése: BoundingBox(for:)
 
 */

//AVFoundation orientációt alakítja a vision számára CGImagePropertyOrientation-ra
extension CGImagePropertyOrientation {
    init(_ orientation: AVCaptureVideoOrientation) {
        switch orientation {
        case .portrait: self = .right //függőleges
        case .portraitUpsideDown: self = .left //fejjel lefelé
        case .landscapeRight: self = .down //jobbra forog
        case .landscapeLeft: self = .up //balra forog
        @unknown default:
            self = .right
        }
    }
}

//minden framet feldolgoz
class CameraOCRViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {

    private var captureSession: AVCaptureSession!
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var overlayLayers: [CAShapeLayer] = []
    private var clusterLineLayers: [CAShapeLayer] = []

    private var pitchBox: UIView?
    private var yawBox: UIView?
    private var frames: Int = 0

    struct BoundingBoxInfo: Hashable {
        let x : CGFloat
        let y : CGFloat
        let height : CGFloat
        let text: String //debugból
    }
    
    struct RowAverage {
        let avgY: CGFloat         // a sor középvonala
        let avgHeight: CGFloat   // a karakterek átlagos magassága
        let texts: [String]         //debug célból
                        
    }
    
    
    struct ColumnAverage {
        let avgX: CGFloat
        let avgHeight: CGFloat
        let texts: [String]
    }

    
    private var boundingBoxFrames: [FrameBoundingBoxes] = [] //minden frame bounding boxa
    private var currentFrameBoxes: [BoundingBoxInfo] = [] //aktuális frame bounding boxai
    private var boundingBoxBuffer: [BoundingBoxInfo] = []
    struct FrameBoundingBoxes {
        let timestamp: Date
        let boxes: [BoundingBoxInfo]
    }

    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    }

    // MARK: - Camera Setup

    private func setupCamera() {
        captureSession = AVCaptureSession()
        guard let videoDevice = AVCaptureDevice.default(for: .video),//hátsó kamera
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
              captureSession.canAddInput(videoInput) else {
            return
        }
        
        captureSession.addInput(videoInput)

        let output = AVCaptureVideoDataOutput() //framek
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        captureSession.addOutput(output)

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspect //nem vágja le a képet
        view.layer.addSublayer(previewLayer)

        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.startRunning()
        }
    }
    
    
    private func drawRecognizedBox(observation: VNRecognizedTextObservation, label: String?) {
        let convertedRect = self.previewLayer.layerRectConverted(fromMetadataOutputRect: observation.boundingBox)

        let path = UIBezierPath(rect: convertedRect)
        let shape = CAShapeLayer()
        shape.path = path.cgPath
        shape.strokeColor = UIColor.red.cgColor
        shape.fillColor = UIColor.clear.cgColor
        shape.lineWidth = 2
        self.view.layer.addSublayer(shape)
        overlayLayers.append(shape)

        


        if let label = label {
            let labelView = UILabel(frame: CGRect(x: convertedRect.minX, y: convertedRect.minY - 20, width: 100, height: 20))
            labelView.text = label
            labelView.font = UIFont.systemFont(ofSize: 12, weight: .bold)
            labelView.textColor = .white
            labelView.backgroundColor = UIColor.black.withAlphaComponent(0.6)
            labelView.sizeToFit()
            view.addSubview(labelView)
        }
    }


    // MARK: - OCR Pipeline
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return } //képkocka adatai

            let videoOrientation = connection.videoOrientation //kamera orientációja
            let orientation = CGImagePropertyOrientation(videoOrientation) //vision formára alakítás

        
            let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:]) //OCR feldolgozás
        let request = VNRecognizeTextRequest { [weak self] req, err in
            guard let self = self else { return }
            guard let results = req.results as? [VNRecognizedTextObservation] else { return }

            DispatchQueue.main.async {
                self.clearOverlays() //boxok törlése
                for observation in results {
                    //self.drawRecognizedBox(observation: observation, label: observation.topCandidates(1).first?.string)
                    if let candidate = observation.topCandidates(1).first {
                        //print("Recognized: \(candidate.string)")
                    }
                    self.drawRotatedBoundingBox(for: observation) //minden felismerésre boxot rajzol
                    
                }
                let frameData = FrameBoundingBoxes(timestamp: Date(), boxes: self.currentFrameBoxes)

                if self.boundingBoxFrames.count >= 100 {
                    self.boundingBoxFrames.removeFirst()
                }

                self.boundingBoxFrames.append(frameData)
                
                
                /*utolsó 10 box mergelve*/
                let index = 0;
                let mergedBoxes = self.boundingBoxFrames
                    .suffix(60)
                    .flatMap { $0.boxes }
                self.frames += 1

                //----------
                //  ROWS
                //----------
                let clusteredByRow = self.clusterBoundingBoxesByRow(boxes: self.currentFrameBoxes, eps: 20, minPts: 1)
                let rowAverages = self.averageRowInfo(from: clusteredByRow)
                for (index, rowInfo) in rowAverages.enumerated() {
                    print("=== [\(index)] sor - rowAverages.count=\(rowAverages.count), frames=\(self.frames) ===")
                    print("Pozíció: \(rowInfo.avgY), Magasság: \(rowInfo.avgHeight)")
                    print("Szövegek: \(rowInfo.texts.joined(separator: ", "))")
                    print("======================")
                }


                if rowAverages.count >= 2 {
                    let regressionPoints = rowAverages.map { (x: $0.avgHeight, y: $0.avgY) }
                    if let pitchLine = self.ransacRegression(points: regressionPoints) {
                        self.drawRegressionLinePitch(
                            slope: pitchLine.slope,
                            intercept: pitchLine.intercept,
                            in: self.view
                        )
                        print("PITCH (sorátlagok alapján) = \(pitchLine.slope) * y + \(pitchLine.intercept)")
                    } else {
                        print("PITCH - Nem sikerült regressziót illeszteni a sorátlagokra.")
                    }
                }
                
                //------------
                //  CULOMNS
                //-------------
                let clusteredByCulomn = self.clusterBoundingBoxesByColumn(boxes: self.currentFrameBoxes, eps: 20, minPts: 1)
                let culomnAverages = self.averageColumnInfo(from: clusteredByRow)
                for (index, culomnInfo) in culomnAverages.enumerated()
                {
                    print("=== [\(index)] oszlop - culomnAverages.count=\(culomnAverages.count), frames=\(self.frames) ===")
                    print("Pozíció: \(culomnInfo.avgX), Magasság: \(culomnInfo.avgHeight)")
                    print("Szövegek: \(culomnInfo.texts.joined(separator: ", "))")
                    print("======================")
                }
                if culomnAverages.count >= 2 {
                    let regressionPoints = culomnAverages.map { (x: $0.avgHeight, y: $0.avgX) }
                    if let yawLine = self.ransacRegression(points: regressionPoints) {
                        self.drawRegressionLineYaw(
                            slope: yawLine.slope,
                            intercept: yawLine.intercept,
                            in: self.view
                        )
                        print("YAW(oszlopátlagok alapján) = \(yawLine.slope) * y + \(yawLine.intercept)")
                    } else {
                        print("YAW - Nem sikerült regressziót illeszteni az oszlopátlagokra.")
                    }
                }
                
                
                

                //self.drawClusterLines(clusters: clusteredByRow, color: .systemYellow)




                self.currentFrameBoxes.removeAll()

                
     


            }
        }

        request.recognitionLevel = .accurate //pontos feldolgozás (.fast is van)
        request.recognitionLanguages = ["en-US", "hu-HU"/*"und"*/]
        request.minimumTextHeight = 0.0001 //legkisebb felismerhető karaktermagasság
        request.usesLanguageCorrection = true //nyelvi korrekció
        request.customWords = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]

        try? requestHandler.perform([request]) //ocr kérés
    }











    // MARK: - Drawing

    private func drawRotatedBoundingBox(for observation: VNRecognizedTextObservation) {
        guard let candidate = observation.topCandidates(1).first else { return }

        let text = candidate.string

        // Teljes szöveg bounding boxa (a teljes sztringre)
        let fullRange = text.startIndex..<text.endIndex
        guard let fullBox = try? candidate.boundingBox(for: fullRange) else { return }

        // Az első és utolsó karakter indexei
        let firstIndex = text.startIndex
        let secondIndex = text.index(after: firstIndex)
        let lastIndex = text.index(before: text.endIndex)

        // Az első és utolsó karakter bounding boxai
        guard let firstBox = try? candidate.boundingBox(for: firstIndex..<text.index(firstIndex, offsetBy: 1)),
              let lastBox = try? candidate.boundingBox(for: lastIndex..<text.endIndex) else {
            return
        }

        // Teljes szöveg négy sarka (zöld trapéz)
        let p1 = convertPoint(fullBox.topLeft)      // bal felső
        let p2 = convertPoint(fullBox.topRight)     // jobb felső
        let p3 = convertPoint(fullBox.bottomRight)  // jobb alsó
        let p4 = convertPoint(fullBox.bottomLeft)   // bal alsó

        // Teljes bounding box (zöld)
        let path = UIBezierPath()
        path.move(to: p1)
        path.addLine(to: p2)
        path.addLine(to: p3)
        path.addLine(to: p4)
        path.close()

        let shape = CAShapeLayer()
        shape.path = path.cgPath
        shape.strokeColor = UIColor.green.cgColor
        shape.fillColor = UIColor.clear.cgColor
        shape.lineWidth = 2
        view.layer.addSublayer(shape)
        overlayLayers.append(shape)

        // --- Első karakter bounding box (piros) ---
        let firstCharPath = UIBezierPath()
        firstCharPath.move(to: convertPoint(firstBox.topLeft))
        firstCharPath.addLine(to: convertPoint(firstBox.topRight))
        firstCharPath.addLine(to: convertPoint(firstBox.bottomRight))
        firstCharPath.addLine(to: convertPoint(firstBox.bottomLeft))
        firstCharPath.close()

        let firstCharShape = CAShapeLayer()
        firstCharShape.path = firstCharPath.cgPath
        firstCharShape.strokeColor = UIColor.red.cgColor
        firstCharShape.fillColor = UIColor.clear.cgColor
        firstCharShape.lineWidth = 1.5
        view.layer.addSublayer(firstCharShape)
        overlayLayers.append(firstCharShape)

        // --- Utolsó karakter bounding box (kék) ---
        let lastCharPath = UIBezierPath()
        lastCharPath.move(to: convertPoint(lastBox.topLeft))
        lastCharPath.addLine(to: convertPoint(lastBox.topRight))
        lastCharPath.addLine(to: convertPoint(lastBox.bottomRight))
        lastCharPath.addLine(to: convertPoint(lastBox.bottomLeft))
        lastCharPath.close()

        let lastCharShape = CAShapeLayer()
        lastCharShape.path = lastCharPath.cgPath
        lastCharShape.strokeColor = UIColor.blue.cgColor
        lastCharShape.fillColor = UIColor.clear.cgColor
        lastCharShape.lineWidth = 1.5
        view.layer.addSublayer(lastCharShape)
        overlayLayers.append(lastCharShape)

        // Középpont kiszámítása a teljes doboz alapján
        let midPoint = CGPoint(x: (p1.x + p3.x) / 2, y: (p1.y + p3.y) / 2)

        // Felismert szöveg kiírása
        let labelView = UILabel(frame: CGRect(x: midPoint.x - 50, y: midPoint.y - 10, width: 100, height: 20))
        labelView.text = candidate.string
        labelView.font = UIFont.systemFont(ofSize: 10, weight: .semibold)
        labelView.textColor = .white
        labelView.textAlignment = .center
        labelView.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        labelView.layer.cornerRadius = 3
        labelView.layer.masksToBounds = true
        view.addSubview(labelView)

        // Roll szög kiszámítása a felső él alapján
        let roll = atan2(p2.y - p1.y, p2.x - p1.x) * 180 / .pi

        let rollLabel = UILabel(frame: CGRect(x: midPoint.x - 50, y: midPoint.y + 15, width: 100, height: 15))
        rollLabel.text = String(format: "Roll: %.1f°", roll)
        rollLabel.font = UIFont.systemFont(ofSize: 10)
        rollLabel.textColor = .yellow
        rollLabel.textAlignment = .center
        rollLabel.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        rollLabel.layer.cornerRadius = 3
        rollLabel.layer.masksToBounds = true
        view.addSubview(rollLabel)
        
        let convertedRect = previewLayer.layerRectConverted(fromMetadataOutputRect: observation.boundingBox)
        let bboxInfo = BoundingBoxInfo(x: convertedRect.minX,
                                       y: convertedRect.minY,
                                       height: convertedRect.height, text: candidate.string)
        currentFrameBoxes.append(bboxInfo)
        //print("--------------------------------------------")
        //print("Height: \(bboxInfo.height), X: \(bboxInfo.x), Y: \(bboxInfo.y), TEXT: \(candidate.string)")
        //print("--------------------------------------------")

    }
    
    struct RegressionLine {
        let slope: CGFloat
        let intercept: CGFloat
    }

    func ransacRegression(
        points: [(x: CGFloat, y: CGFloat)],
        iterations: Int = 200,
        threshold: CGFloat = 20,
        minInlierRatio: CGFloat = 0.3,
        earlyStopRatio: CGFloat = 0.9
    ) -> RegressionLine? {
        guard points.count >= 2 else { return nil }

        let epsilon: CGFloat = 1e-6
        var bestInliers: [(x: CGFloat, y: CGFloat)] = []

        for _ in 0..<iterations {
            //2 különböző pont
            let sample = points.shuffled().prefix(2)
            guard sample.count == 2 else { continue }
            let (x1, y1) = sample[0]
            let (x2, y2) = sample[1]

            //ne folytassuk, ha a két pont túl közel van egymáshoz
            guard abs(x2 - x1) > epsilon else { continue }

            //egyenes együtthatók
            let m = (y2 - y1) / (x2 - x1)
            let b = y1 - m * x1

            var inliers: [(x: CGFloat, y: CGFloat)] = []

            for (x, y) in points {
                let distance = abs(m * x - y + b) / sqrt(m * m + 1)
                if distance < threshold {
                    inliers.append((x, y))
                }
            }

            if inliers.count > bestInliers.count &&
                CGFloat(inliers.count) >= CGFloat(points.count) * minInlierRatio {
                bestInliers = inliers

                //korai kilépés, ha elérjük az elvárt jó modell minőséget
                if CGFloat(inliers.count) >= CGFloat(points.count) * earlyStopRatio {
                    break
                }
            }
        }

        guard bestInliers.count >= 2 else { return nil }

        //klasszikus lineáris regresszió a legjobb inlierekre
        let n = CGFloat(bestInliers.count)
        let sumX = bestInliers.reduce(0) { $0 + $1.x }
        let sumY = bestInliers.reduce(0) { $0 + $1.y }
        let sumXY = bestInliers.reduce(0) { $0 + $1.x * $1.y }
        let sumXX = bestInliers.reduce(0) { $0 + $1.x * $1.x }

        let meanX = sumX / n
        let meanY = sumY / n

        let numerator = sumXY - n * meanX * meanY
        let denominator = sumXX - n * meanX * meanX

        guard abs(denominator) > epsilon else { return nil }

        let finalSlope = numerator / denominator
        let finalIntercept = meanY - finalSlope * meanX

        return RegressionLine(slope: finalSlope, intercept: finalIntercept)
    }

    func clusterBoundingBoxesByColumn(
        boxes: [BoundingBoxInfo],
        eps: CGFloat = 15, //mekkora sugarú körben keresse a szomszédokat
        minPts: Int = 2 //minimális számú pont a klazster egy tagjának tekinteni
    ) -> [String: [BoundingBoxInfo]] {
        let dbscan = DBSCAN(aDB: boxes)

        dbscan.DBSCAN(
            distFunc: { a, b in Double(abs(a.x - b.x)) }, //távolságfüggvény az x tengely mentén
            eps: Double(eps),
            minPts: minPts
        )

        let clusters = Dictionary(grouping: dbscan.label.keys, by: { dbscan.label[$0]! }) //minden boundingBoxInfo elemhez tartozik egy label, ami azt jelenti melyik klaszterhez tartozik
        //a klasztercímke szerint csoportosítja a boxokat
        //kulcs egy String a klaszter azonosítója
        //az érték a boundingBoxInfo, a klaszterhez tartozó elemek
        return clusters
    }


    func clusterBoundingBoxesByRow(
        boxes: [BoundingBoxInfo],
        eps: CGFloat = 15,
        minPts: Int = 2
    ) -> [String: [BoundingBoxInfo]] {
        let dbscan = DBSCAN(aDB: boxes)

        dbscan.DBSCAN(
            distFunc: { a, b in Double(abs(a.y - b.y)) }, //távolságfüggvény y tengely mentén
            eps: Double(eps),
            minPts: minPts
        )

        // Csoportosítjuk a címkék alapján
        let clusters = Dictionary(grouping: dbscan.label.keys, by: { dbscan.label[$0]! })

        return clusters
    }
    func averageRowInfo(from clusters: [String: [BoundingBoxInfo]]) -> [RowAverage] {
        var result: [RowAverage] = []

        for (label, boxes) in clusters where label != "Noise" && !boxes.isEmpty { //végigiterál a klaszteren, kihagyja a noise-t és az üres klasztereket
            let avgY = boxes.map { $0.y }.reduce(0, +) / CGFloat(boxes.count) //kiszámolja az átlag y-t , reduce összeadja őket
            let avgHeight = boxes.map { $0.height }.reduce(0, +) / CGFloat(boxes.count)
            let rowTexts = boxes.map { $0.text } //összegyűjti a klaszterhez tartozó szövegeket
            result.append(RowAverage(avgY: avgY, avgHeight: avgHeight, texts: rowTexts))
        }

        return result
    }
    
    func averageColumnInfo(from clusters: [String: [BoundingBoxInfo]]) -> [ColumnAverage] {
        var result: [ColumnAverage] = []

        for (label, boxes) in clusters where label != "Noise" && !boxes.isEmpty {
            let avgX = boxes.map { $0.x }.reduce(0, +) / CGFloat(boxes.count)
            let avgHeight = boxes.map { $0.height }.reduce(0, +) / CGFloat(boxes.count)
            let texts = boxes.map { $0.text }
            result.append(ColumnAverage(avgX: avgX, avgHeight: avgHeight, texts: texts))
        }

        return result
    }






    
    
    private func convertPoint(_ point: CGPoint) -> CGPoint { //a vision koordinátái alulról-felfele épül, az UIkit viszont felülről lefelé
        let converted = previewLayer.layerPointConverted(fromCaptureDevicePoint: point)
        return CGPoint(x: converted.x, y: view.bounds.height - converted.y)
    }
    func drawRegressionLinePitch(slope: CGFloat, intercept: CGFloat, in view: UIView) {
        pitchBox?.removeFromSuperview()

        let boxWidth: CGFloat = 150
        let boxHeight: CGFloat = 150

        let box = UIView()
        box.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        box.layer.cornerRadius = 8
        box.translatesAutoresizingMaskIntoConstraints = false
        box.clipsToBounds = true
        box.isUserInteractionEnabled = false
        view.addSubview(box)

        NSLayoutConstraint.activate([
            box.widthAnchor.constraint(equalToConstant: boxWidth),
            box.heightAnchor.constraint(equalToConstant: boxHeight),
            box.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            box.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16)
        ])

        self.pitchBox = box

        let centerX = boxWidth / 2
        let centerY = boxHeight / 2
        let deltaX: CGFloat = boxWidth
        let deltaY = slope * deltaX

        let leftStart = CGPoint(x: centerX, y: centerY)
        let leftEnd = CGPoint(x: centerX - deltaX / 2, y: centerY - deltaY / 2)

        let rightStart = CGPoint(x: centerX, y: centerY)
        let rightEnd = CGPoint(x: centerX + deltaX / 2, y: centerY + deltaY / 2)

        let leftPath = UIBezierPath()
        leftPath.move(to: leftStart)
        leftPath.addLine(to: leftEnd)

        let rightPath = UIBezierPath()
        rightPath.move(to: rightStart)
        rightPath.addLine(to: rightEnd)

        let leftLayer = CAShapeLayer()
        leftLayer.path = leftPath.cgPath
        let rightLayer = CAShapeLayer()
        rightLayer.path = rightPath.cgPath

        if slope >= 0 {
            // lefelé megy balra → bal oldal zöld, jobb piros
            leftLayer.strokeColor = UIColor.green.cgColor
            rightLayer.strokeColor = UIColor.red.cgColor
        } else {
            // lefelé megy jobbra → bal piros, jobb zöld
            leftLayer.strokeColor = UIColor.red.cgColor
            rightLayer.strokeColor = UIColor.green.cgColor
        }

        leftLayer.lineWidth = 2.0
        rightLayer.lineWidth = 2.0
        leftLayer.frame = CGRect(x: 0, y: 0, width: boxWidth, height: boxHeight)
        rightLayer.frame = CGRect(x: 0, y: 0, width: boxWidth, height: boxHeight)

        box.layer.addSublayer(leftLayer)
        box.layer.addSublayer(rightLayer)
    }


    
    func drawRegressionLineYaw(slope: CGFloat, intercept: CGFloat, in view: UIView) {
        yawBox?.removeFromSuperview()

        let boxWidth: CGFloat = 150
        let boxHeight: CGFloat = 150

        let box = UIView()
        box.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        box.layer.cornerRadius = 8
        box.translatesAutoresizingMaskIntoConstraints = false
        box.clipsToBounds = true
        box.isUserInteractionEnabled = false
        view.addSubview(box)

        NSLayoutConstraint.activate([
            box.widthAnchor.constraint(equalToConstant: boxWidth),
            box.heightAnchor.constraint(equalToConstant: boxHeight),
            box.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            box.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16)
        ])

        self.yawBox = box

        let centerX = boxWidth / 2
        let centerY = boxHeight / 2
        let deltaX: CGFloat = boxWidth
        let deltaY = slope * deltaX

        let leftStart = CGPoint(x: centerX, y: centerY)
        let leftEnd = CGPoint(x: centerX - deltaX / 2, y: centerY - deltaY / 2)

        let rightStart = CGPoint(x: centerX, y: centerY)
        let rightEnd = CGPoint(x: centerX + deltaX / 2, y: centerY + deltaY / 2)

        let leftPath = UIBezierPath()
        leftPath.move(to: leftStart)
        leftPath.addLine(to: leftEnd)

        let rightPath = UIBezierPath()
        rightPath.move(to: rightStart)
        rightPath.addLine(to: rightEnd)

        let leftLayer = CAShapeLayer()
        leftLayer.path = leftPath.cgPath
        leftLayer.lineWidth = 2.0
        leftLayer.frame = CGRect(x: 0, y: 0, width: boxWidth, height: boxHeight)

        let rightLayer = CAShapeLayer()
        rightLayer.path = rightPath.cgPath
        rightLayer.lineWidth = 2.0
        rightLayer.frame = CGRect(x: 0, y: 0, width: boxWidth, height: boxHeight)

        // Irányjelző színek a slope alapján
        if slope >= 0 {
            // Jobbra felfelé tart: jobb oldal zöld (előre), bal oldal kék (hátra)
            rightLayer.strokeColor = UIColor.green.cgColor
            leftLayer.strokeColor = UIColor.blue.cgColor
        } else {
            // Jobbra lefelé tart: jobb oldal kék (hátra), bal oldal zöld (előre)
            rightLayer.strokeColor = UIColor.blue.cgColor
            leftLayer.strokeColor = UIColor.green.cgColor
        }

        box.layer.addSublayer(leftLayer)
        box.layer.addSublayer(rightLayer)
    }




/*
    func drawClusterLines(clusters: [String: [BoundingBoxInfo]], color: UIColor) {
        for (label, boxes) in clusters where label != "Noise" {
            let sorted = boxes.sorted { $0.x < $1.x }

            let path = UIBezierPath()
            for (i, box) in sorted.enumerated() {
                let point = CGPoint(x: box.x, y: box.y + box.height / 2) // UIKit koordináta, NE konvertáld!
                if i == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }

            let shape = CAShapeLayer()
            shape.path = path.cgPath
            shape.strokeColor = color.cgColor
            shape.lineWidth = 2
            shape.fillColor = UIColor.clear.cgColor
            view.layer.addSublayer(shape)
            clusterLineLayers.append(shape)
        }
    }*/




    private func clearOverlays() {
        overlayLayers.forEach { $0.removeFromSuperlayer() }
        overlayLayers.removeAll()

        clusterLineLayers.forEach { $0.removeFromSuperlayer() }
        clusterLineLayers.removeAll()

        view.subviews.forEach {
            if $0 is UILabel { $0.removeFromSuperview() }
        }
    }

}
