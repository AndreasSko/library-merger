//
//  OnboardingView.swift
//  LibraryMerger
//
//  Created by Andreas Skorczyk on 29.11.20.
//

import SwiftUI

struct OnboardingView: View {
    @Binding var needsOnboarding: Bool
    @State private var currentTab: Int = 1

    var body: some View {
        VStack {
            ScrollView {
                LazyHStack {
                    TabView(selection: $currentTab) {
                        Onboarding1().tag(1)
                        Onboarding2().tag(2)
                        Onboarding3().tag(3)
                        Onboarding4().tag(4)
                        Onboarding5(needsOnboarding: $needsOnboarding).tag(5)
                    }
                    .frame(width: UIScreen.main.bounds.width,
                           height: UIScreen.main.bounds.height - 120)
                    .tabViewStyle(PageTabViewStyle())
                    .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))
                }
            }
            if currentTab != 5 {
                Button(action: {
                    needsOnboarding = false
                }, label: {
                    Text("Skip Tutorial")
                })
                .padding(.bottom)
            }
        }
    }
}

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView(needsOnboarding: .constant(true))
    }
}

struct Onboarding1: View {
    var body: some View {
        VStack(alignment: .leading) {
            Text("onboarding.1")
                .font(.title2).bold()
                .padding(.bottom, 40)
            HStack {
                Spacer()
                Image("merge-illustration")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: UIScreen.main.bounds.width - 20,
                           maxHeight: 400)
                Spacer()
            }
            Spacer()
        }
        .padding()
    }
}

struct Onboarding2: View {
    var body: some View {
        VStack(alignment: .leading) {
            Text("onboarding.2.first")
                .font(.title2).bold()

            HStack {
                let mergerController = MergerController()
                BackupView(side: MergeSide.leftSide,
                           mergerController: mergerController,
                           sharedUrl: .constant(nil),
                           fileSelected: .constant(false),
                           doneMerging: .constant(false))
                    .disabled(true)

                BackupView(side: MergeSide.rightSide,
                           mergerController: mergerController,
                           sharedUrl: .constant(nil),
                           fileSelected: .constant(false),
                           doneMerging: .constant(false))
                    .disabled(true)
            }.padding()

            Text("Pro Tips:")
                .font(.title2)
                .padding(.bottom, 0.5)

            HStack {
                Image(systemName: "wave.3.right")
                    .frame(width: 20)
                Text("onboarding.2.proTip.first")
            }
            .padding(.bottom, 0.5)

            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "square.and.arrow.up")
                    .frame(width: 20)
                Text("onboarding.2.proTip.second")
            }
            .padding(.bottom, 0.5)

            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "icloud")
                    .frame(width: 20)
                Text("onboarding.2.proTip.third")
            }
            .padding(.bottom, 0.5)

            Spacer()
        }
        .padding()
    }
}

struct Onboarding3: View {
    var body: some View {
        VStack(alignment: .leading) {
            Text("onboarding.3.first")
                .font(.title2).bold()

            let mergerController = MergerController()
            MergeSettingsView(mergerController: mergerController)
                .background(Color.white)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(.sRGB, red: 150/255, green: 150/255, blue: 150/255, opacity: 0.1), lineWidth: 1)
                )
                .shadow(color: Color.gray.opacity(0.2), radius: 20)
                .padding()
                .disabled(true)

            Text("onboarding.3.second")

            Text("onboarding.3.third").font(.title2).bold()
                .padding(.top)

            Text("Merge").font(.title)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()

            Spacer()
        }
        .padding()
    }
}

struct Onboarding4: View {
    var body: some View {
        VStack(alignment: .leading) {
            Text("onboarding.4.first")
                .font(.title2).bold()
            Text("onboarding.4.second")
                .padding(.bottom, 5)

            VStack {
                VStack {
                    HStack {
                        Text("Title:").bold()
                        Spacer()
                    }.padding([.horizontal, .top])
                    HStack {
                        Text("Exodus") + Text(" 37")
                        Spacer()
                    }.padding([.horizontal, .bottom])

                }
                .background(Color.white)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(.sRGB, red: 150/255, green: 150/255, blue: 150/255, opacity: 0.1), lineWidth: 1)
                )
                .shadow(color: Color.gray.opacity(0.2), radius: 20)
                .contentShape(Rectangle())

                VStack {
                    HStack {
                        Text("Title:").bold()
                        Spacer()
                    }.padding([.horizontal, .top])
                    HStack {
                        Text("Exodus") + Text(" 33")
                        Spacer()
                    }.padding([.horizontal, .bottom])

                }
                .background(Color.white)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.blue, lineWidth: 1)
                )
                .shadow(color: Color.gray.opacity(0.2), radius: 20)
                .contentShape(Rectangle())
            }
            .padding([.horizontal, .bottom])

            HStack {
                Text("🤨")
                Text("onboarding.4.third")
            }
            .padding(.bottom, 5)

            HStack {
                Text("🎉")
                Text("onboarding.4.fourth")
            }

            Spacer()
        }
        .padding()
    }
}

struct Onboarding5: View {
    @Binding var needsOnboarding: Bool
    @Environment(\.openURL) var openURL

    var body: some View {
        VStack(alignment: .leading) {
            Text("onboarding.5.first")
                .font(.title2).bold()
                .padding(.bottom)

            Text("onboarding.5.second")
                .padding(.bottom)

            HStack {
                Spacer()
                Button(action: {
                    needsOnboarding = false
                }, label: {
                    Text("🚀 ") + Text("onboarding.5.startButton").font(.title2)
                })
                Spacer()
            }
            Spacer()

            Text("By the way:").font(.title3).bold()
            Link("onboarding.5.third",
                 destination: URL(string: "https://github.com/AndreasSko/library-merger")!)
                .padding(.bottom, 40)
        }
        .padding()
    }
}
