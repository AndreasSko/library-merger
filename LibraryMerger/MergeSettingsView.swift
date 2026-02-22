//
//  MergeSettingsView.swift
//  LibraryMerger
//
//  Created by Andreas Skorczyk on 11.10.20.
//

import SwiftUI

struct MergeSettingsView: View {
    @ObservedObject var mergerController: MergerController

    @State private var bookmarkSolverIcon = "minus.circle"
    @State private var markingSolverIcon = "minus.circle"
    @State private var noteSolverIcon = "minus.circle"
    @State private var inputFieldSolverIcon = "minus.circle"
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
                VStack {
                    Menu {
                        Button(action: {
                            mergerController.settings.bookmarkResolver = ConflictSolver.disabled
                            bookmarkSolverIcon = confSolverToIcon(solver: mergerController.settings.bookmarkResolver)
                        }, label: {
                            Text("Manual")
                            Image(systemName: "minus.circle")
                        })
                        Button(action: {
                            mergerController.settings.bookmarkResolver = ConflictSolver.chooseLeft
                            bookmarkSolverIcon = confSolverToIcon(solver: mergerController.settings.bookmarkResolver)
                        }, label: {
                            Text("Left")
                            Image(systemName: "arrow.left")
                        })
                        Button(action: {
                            mergerController.settings.bookmarkResolver = ConflictSolver.chooseRight
                            bookmarkSolverIcon = confSolverToIcon(solver: mergerController.settings.bookmarkResolver)
                        }, label: {
                            Text("Right")
                            Image(systemName: "arrow.right")
                        })
                    } label: {
                        Spacer()
                        Spacer()
                        VStack {
                            Image(systemName: "bookmark")
                            Image(systemName: bookmarkSolverIcon)
                                .font(.footnote)
                                .foregroundColor(.gray)
                                .padding(.top, 0.3)
                        }
                        .frame(height: 60)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Spacer()
                VStack {
                    Menu {
                        Button(action: {
                            mergerController.settings.markingResolver = ConflictSolver.disabled
                            markingSolverIcon = confSolverToIcon(solver: mergerController.settings.markingResolver)
                        }, label: {
                            Text("Manual")
                            Image(systemName: "minus.circle")
                        })
                        Button(action: {
                            mergerController.settings.markingResolver = ConflictSolver.chooseLeft
                            markingSolverIcon = confSolverToIcon(solver: mergerController.settings.markingResolver)
                        }, label: {
                            Text("Left")
                            Image(systemName: "arrow.left")
                        })
                        Button(action: {
                            mergerController.settings.markingResolver = ConflictSolver.chooseRight
                            markingSolverIcon = confSolverToIcon(solver: mergerController.settings.markingResolver)
                        }, label: {
                            Text("Right")
                            Image(systemName: "arrow.right")
                        })
                    } label: {
                        VStack {
                            Image(systemName: "pencil.tip")
                            Image(systemName: markingSolverIcon)
                                .font(.footnote)
                                .foregroundColor(.gray)
                                .padding(.top, 0.3)

                        }
                        .frame(height: 60)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                Spacer()
                VStack {
                    Menu {
                        Button(action: {
                            mergerController.settings.noteResolver = ConflictSolver.disabled
                            noteSolverIcon = confSolverToIcon(solver: mergerController.settings.noteResolver)
                        }, label: {
                            Text("Manual")
                            Image(systemName: "minus.circle")
                        })
                        Button(action: {
                            mergerController.settings.noteResolver = ConflictSolver.chooseNewest
                            noteSolverIcon = confSolverToIcon(solver: mergerController.settings.noteResolver)
                        }, label: {
                            Text("Newest")
                            Image(systemName: "sparkles")
                        })
                        Button(action: {
                            mergerController.settings.noteResolver = ConflictSolver.chooseLeft
                            noteSolverIcon = confSolverToIcon(solver: mergerController.settings.noteResolver)
                        }, label: {
                            Text("Left")
                            Image(systemName: "arrow.left")
                        })
                        Button(action: {
                            mergerController.settings.noteResolver = ConflictSolver.chooseRight
                            noteSolverIcon = confSolverToIcon(solver: mergerController.settings.noteResolver)
                        }, label: {
                            Text("Right")
                            Image(systemName: "arrow.right")
                        })
                    } label: {
                        VStack {
                            Image(systemName: "note.text")
                            Image(systemName: noteSolverIcon)
                                .font(.footnote)
                                .foregroundColor(.gray)
                                .padding(.top, 0.3)
                        }
                        .frame(height: 60)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        Spacer()
                        Spacer()
                    }
                }
                Spacer()
                VStack {
                    Menu {
                        Button(action: {
                            mergerController.settings.inputFieldResolver = ConflictSolver.disabled
                            inputFieldSolverIcon = confSolverToIcon(solver: mergerController.settings.inputFieldResolver)
                        }, label: {
                            Text("Manual")
                            Image(systemName: "minus.circle")
                        })
                        Button(action: {
                            mergerController.settings.inputFieldResolver = ConflictSolver.chooseLeft
                            inputFieldSolverIcon = confSolverToIcon(solver: mergerController.settings.inputFieldResolver)
                        }, label: {
                            Text("Left")
                            Image(systemName: "arrow.left")
                        })
                        Button(action: {
                            mergerController.settings.inputFieldResolver = ConflictSolver.chooseRight
                            inputFieldSolverIcon = confSolverToIcon(solver: mergerController.settings.inputFieldResolver)
                        }, label: {
                            Text("Right")
                            Image(systemName: "arrow.right")
                        })
                    } label: {
                        VStack {
                            Image(systemName: "textbox")
                            Image(systemName: inputFieldSolverIcon)
                                .font(.footnote)
                                .foregroundColor(.gray)
                                .padding(.top, 0.3)
                        }
                        .frame(height: 60)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        Spacer()
                        Spacer()
                    }
                }
            }
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

func confSolverToIcon(solver: ConflictSolver) -> String {
    switch solver {
    case .disabled:
        return "minus.circle"
    case .chooseLeft:
        return "arrow.left"
    case .chooseRight:
        return "arrow.right"
    case .chooseNewest:
        return "sparkles"
    }
}
