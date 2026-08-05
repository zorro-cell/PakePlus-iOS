//
//  ContentView.swift
//  PakePlus
//
//  Created by Song on 2025/3/29.
//

import SwiftUI
import UIKit

struct ContentView: View {
    // read value from info
    let webUrl = Bundle.main.object(forInfoDictionaryKey: "WEBURL") as? String ?? ""
    let debug = Bundle.main.object(forInfoDictionaryKey: "DEBUG") as? Bool ?? false
    let fullScreen = Bundle.main.object(forInfoDictionaryKey: "FULLSCREEN") as? Bool ?? false
    let launchImage = Bundle.main.object(forInfoDictionaryKey: "LAUNCHIMAGE") as? Bool ?? false
    let screenOn = Bundle.main.object(forInfoDictionaryKey: "SCREENON") as? Bool ?? false

    @Environment(\.scenePhase) private var scenePhase
    @State private var isWebLoaded: Bool = false

    var body: some View {
        // BottomMenuView()
        ZStack {
            // Extend only the page background into the physical screen edges.
            // Interactive web content remains inside the SwiftUI safe area.
            Color("HermesBackground")
                .ignoresSafeArea(.container, edges: .all)

            // webview
            WebView(
                webUrl: URL(string: webUrl)!,
                debug: debug,
                onLoadFinished: {
                    isWebLoaded = true
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, -4)
            .allowsHitTesting(isWebLoaded)
            
            // loading screen
            if !isWebLoaded && launchImage {
                Image("LaunchScreen")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .statusBarHidden(fullScreen)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = screenOn
        }
        .onChange(of: scenePhase) { phase in
            UIApplication.shared.isIdleTimerDisabled = screenOn && (phase == .active)
        }
    }
}

// #Preview {
//     ContentView()
// }
