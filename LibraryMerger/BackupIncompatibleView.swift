//
//  BackupIncompatibleView.swift
//  LibraryMerger
//
//  Created by Andreas Skorczyk on 01.09.23.
//

import SwiftUI

struct BackupIncompatibleView: View {
    enum Incompatibility {
        case tooOld
        case tooNew
        case unknown
    }

    @Binding var error: String

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Label("Backup not compatible",
                      systemImage: "exclamationmark.triangle")
                .font(.title)
                Spacer()
            }.padding(.bottom, 5)

            switch determineIncompatibility() {
            case .tooNew:
                Text("backupIncompatibleView.tooNew")
            case .tooOld:
                Text("backupIncompatibleView.tooOld")
            case .unknown:
                Text("backupIncompatibleView.unknown")
            }
            Spacer()
        }
        .padding()
    }

    func determineIncompatibility() -> Incompatibility {
        if error.lowercased().contains("too old") {
            return Incompatibility.tooOld
        }
        if error.lowercased().contains("too new") {
            return Incompatibility.tooNew
        }
        return Incompatibility.unknown
    }
}

struct BackupIncompatibleView_Previews: PreviewProvider {
    static var previews: some View {
        BackupIncompatibleView(error: .constant("schema version is too new"))
    }
}
