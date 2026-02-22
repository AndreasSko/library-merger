//
//  If.swift
//  LibraryMerger
//
//  Created by Andreas Skorczyk on 14.11.20.
//

import SwiftUI

// https://blog.kaltoun.cz/conditionally-applying-view-modifiers-in-swiftui/
extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, content: (Self) -> Content) -> some View {
        if condition {
            content(self)
        } else {
            self
        }
    }
}
