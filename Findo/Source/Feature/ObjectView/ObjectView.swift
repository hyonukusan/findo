//
//  VC.swift
//  Findo
//
//  Created by Mercen on 5/14/24.
//

import SwiftUI

struct ObjectView: NSViewControllerRepresentable {
    
    typealias NSViewControllerType = ObjectViewController
    
    func makeNSViewController(context: Context) -> NSViewControllerType {
        let pageController = NSViewControllerType()
        return pageController
    }
    
    func updateNSViewController(_ nsViewController: NSViewControllerType, context: Context) {
        
    }
}
