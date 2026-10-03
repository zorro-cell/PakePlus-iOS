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
    @State private var refreshRequest = 0
    @State private var isRefreshing = false

    var body: some View {
        // BottomMenuView()
        ZStack {
            // Keep the native host transparent so the Hermes web wallpaper can
            // extend behind the status bar and Home indicator.
            Color.clear
                .ignoresSafeArea(.container, edges: .all)

            // webview
            WebView(
                webUrl: URL(string: webUrl)!,
                debug: debug,
                onLoadFinished: {
                    isWebLoaded = true
                    isRefreshing = false
                },
                refreshRequest: refreshRequest
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, -4)
            .ignoresSafeArea(.container, edges: .all)
            .allowsHitTesting(isWebLoaded)
            
            // loading screen
            if !isWebLoaded && launchImage {
                Image("LaunchScreen")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            // Native control remains available even when the webpage's JS is stalled.
            Button {
                guard !isRefreshing else { return }
                isRefreshing = true
                refreshRequest &+= 1
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(.white.opacity(0.72))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isRefreshing)
            .accessibilityLabel("刷新")
            .padding(.top, 51)
            .padding(.trailing, 72)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .ignoresSafeArea(.container, edges: .all)
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
