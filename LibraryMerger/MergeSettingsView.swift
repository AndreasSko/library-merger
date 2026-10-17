//
//  MergeSettingsView.swift
//  LibraryMerger
//
//  Created by Andreas Skorczyk on 11.10.20.
//

import SwiftUI

struct MergeSettingsView: View {
    @ObservedObject var mergerController: MergerController

    @State private var helpOpened = false

    var body: some View {
        VStack {
            HStack {
                Text("Conflict Autoresolution").font(.headline)
                Spacer()
                Button(action: {
                    helpOpened.toggle()
                },
                    label: {
                    Image(systemName: "questionmark.circle")
                })
                .sheet(isPresented: $helpOpened) {
                    HelpView(isPresented: $helpOpened,
                             title: NSLocalizedString("help.conflictAutoresolution.title",
                                                      comment: "Title for conflictAutoresolution help text"),
                             helpText: NSLocalizedString("help.conflictAutoresolution.text",
                                                      comment: "Help text for conflictAutoresolution"),
                             additionalViews: [AnyView(MergeSettingsLegendHelp())])
                }
            }
            .padding(.top, 10.0)
            .padding([.leading, .trailing])

            Divider()
                .padding(.top, -1)
                .background(Color(.sRGB, red: 150/255, green: 150/255, blue: 150/255, opacity: 0.1))

            HStack {
                SolverMenu(systemImage: "bookmark", solver: $mergerController.settings.bookmarkResolver)
                SolverMenu(systemImage: "pencil.tip", solver: $mergerController.settings.markingResolver)
                SolverMenu(systemImage: "note.text", solver: $mergerController.settings.noteResolver,
                           choices: [.disabled, .chooseNewest, .chooseLeft, .chooseRight])
                SolverMenu(systemImage: "textbox", solver: $mergerController.settings.inputFieldResolver)
                SolverMenu(systemImage: "list.and.film", solver: $mergerController.settings.playlistResolver)
            }
            .padding(.horizontal)
            .font(.title2)
            .padding(.bottom, 4)
        }
    }
}

struct MergeSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        let mergerController = MergerController()
        MergeSettingsView(mergerController: mergerController)
    }
}

private struct SolverMenu: View {
    let systemImage: String
    @Binding var solver: ConflictSolver
    var choices: [ConflictSolver] = [.disabled, .chooseLeft, .chooseRight]

    var body: some View {
        Menu {
            ForEach(choices, id: \.self) { choice in
                Button(action: {
                    solver = choice
                }, label: {
                    Text(choice.title)
                    Image(systemName: choice.icon)
                })
            }
        } label: {
            VStack {
                Image(systemName: systemImage)
                Image(systemName: solver.icon)
                    .font(.footnote)
                    .foregroundColor(.gray)
                    .padding(.top, 0.3)
            }
            .frame(maxWidth: .infinity, minHeight: 60)
        }
    }
}

private extension ConflictSolver {
    var title: LocalizedStringKey {
        switch self {
        case .disabled: return "Manual"
        case .chooseLeft: return "Left"
        case .chooseRight: return "Right"
        case .chooseNewest: return "Newest"
        }
    }

    var icon: String {
        switch self {
        case .disabled: return "minus.circle"
        case .chooseLeft: return "arrow.left"
        case .chooseRight: return "arrow.right"
        case .chooseNewest: return "sparkles"
        }
    }
}
