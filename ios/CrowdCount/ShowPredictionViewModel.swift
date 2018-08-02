//
//  ShowPredictionViewModel.swift
//  CrowdCount
//
//  Created by Dimitri Roche on 8/1/18.
//  Copyright © 2018 Dimitri Roche. All rights reserved.
//

import UIKit
import RxSwift
import RxCocoa
import Promises
import CrowdCountApi

class ShowPredictionViewModel {
    let image: UIImage
    let frameSize: CGSize
    let predictor = FriendlyPredictor()

    private let predictionsSubject = PublishSubject<PredictionRowViewModel>()
    var predictions: Driver<PredictionRowViewModel> {
        return predictionsSubject.asDriver(onErrorJustReturn: PredictionRowViewModel.empty)
    }

    private let thumbnailSubject = PublishSubject<UIImage>()
    var thumbnail: Driver<UIImage> {
        return thumbnailSubject.asDriver(onErrorJustReturn: UIImage())
    }

    init(_ image: UIImage, size: CGSize) {
        self.image = image
        self.frameSize = size
    }

    func start() {
        generateThumbnail()

        let classificationPromise = Promise<FriendlyClassification> {
            self.predictor.classify(image: self.image)
        }

        let predictionPromises = all(on: DispatchQueue.global(qos: .utility), [
            predictor.predictPromise(image: image, strategy: SinglesPredictionStrategy()),
            predictor.predictPromise(image: image, strategy: TensPredictionStrategy()),
            predictor.predictPromise(image: image, strategy: HundredsPredictionStrategy())
        ])

        all(on: DispatchQueue.global(qos: .utility), classificationPromise, predictionPromises).then { (tuple) in
            let (cl, ps) = tuple
            let predictionMap = Dictionary(uniqueKeysWithValues: ps.map { ($0.name, $0)})
            self.publishPredictions(cl, predictionMap)
        }
    }

    private func publishPredictions(_ classification: FriendlyClassification, _ predictionMap: [String: FriendlyPrediction]) {
        let sortedPredictions: [PredictionRowViewModel?] = classification.observations.map { obs in
            guard let prediction = predictionMap[obs.identifier] else {
                return nil
            }

            return PredictionRowViewModel.from(prediction, obs.confidence)
        }

        sortedPredictions
            .filter { $0 != nil }
            .forEach { predictionsSubject.onNext($0!) }
        predictionsSubject.onCompleted()
    }

    private func generateThumbnail() {
        DispatchQueue.global().async {
            guard let thumbnail = self.image.resizeImageFit(self.frameSize) else {
                print("Unable to generate thumbnail")
                self.thumbnailSubject.onError(CCError.runtimeError("Unable to generate thumbnail"))
                return
            }

            self.thumbnailSubject.onNext(thumbnail)
            self.thumbnailSubject.onCompleted()
        }
    }
}
