//
//  CameraOCRView.swift
//  GyroReader
//
//  Created by Gergő Gelegonya on 2025. 04. 02..
//


import SwiftUI
import AVFoundation
import Vision

struct CameraOCRView: UIViewControllerRepresentable {
    @Binding var flattenRequested: Bool


    func makeUIViewController(context: Context) -> CameraOCRViewController {
        let controller = CameraOCRViewController()
        //controller.flattenRequestedBinding = $flattenRequested
        return controller
    }
/*
    func updateUIViewController(_ uiViewController: CameraOCRViewController, context: Context) {
        uiViewController.flattenRequestedBinding = $flattenRequested
    }*/
    
    func updateUIViewController(_ uiViewController: CameraOCRViewController, context: Context) {
        //uiViewController.flattenRequestedBinding = $flattenRequested
        if flattenRequested {
            //uiViewController.updateFlattenState()
        }
    }
    
    

}

