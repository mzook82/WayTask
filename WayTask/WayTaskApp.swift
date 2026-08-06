//
//  WayTaskApp.swift
//  WayTask
//
//  Created by Mordechai Zukerman on 27/06/2026.
//

import SwiftUI
import SwiftData

@main
struct WayTaskApp: App {
    private let accountSyncFoundation: WayTaskAccountSyncFoundation
    @StateObject private var productStateLaunch:
        ProductStateRuntimeLaunchState
    @StateObject private var onboardingCoordinator: OnboardingCoordinator

    init() {
        SentryReportingService.shared.startIfConfigured()
        let accountSyncFoundation = WayTaskAccountSyncFoundation.startup()
        self.accountSyncFoundation = accountSyncFoundation
        _productStateLaunch = StateObject(
            wrappedValue: ProductStateRuntimeLaunchState()
        )
        let onboardingCoordinator = OnboardingCoordinator()
        _onboardingCoordinator = StateObject(
            wrappedValue: onboardingCoordinator
        )
        #if DEBUG
        print(SecretsManager.isGeminiConfigured ? "Gemini configured ✔" : "Gemini unavailable")
        print(
            "Account foundation: \(String(describing: accountSyncFoundation.configurationStatus.environment)) " +
                "accounts=\(accountSyncFoundation.featureFlags.accountsEnabled) " +
                "sync=\(accountSyncFoundation.featureFlags.synchronizationEnabled)"
        )
        #endif
    }

    var body: some Scene {
        WindowGroup {
            if let runtime = productStateLaunch.runtime {
                Group {
                    if onboardingCoordinator.isPresented {
                        OnboardingFlowView(
                            onSkip: onboardingCoordinator.complete,
                            onComplete: onboardingCoordinator.complete
                        )
                    } else {
                        WayTaskProductionRuntimeView()
                            .environmentObject(runtime)
                    }
                }
                .modelContainer(runtime.modelContainer)
            } else {
                ProductStateRuntimeCutoverBlockedView(
                    message: productStateLaunch.failureMessage
                        ?? "Product State is unavailable."
                )
            }
        }
    }
}

private struct ProductStateRuntimeCutoverBlockedView: View {
    let message: String

    var body: some View {
        VStack(spacing: WayTaskDesign.Spacing.lg) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(WayTaskDesign.accent)
            Text("Product State unavailable")
                .font(WayTaskDesign.Typography.title)
                .foregroundStyle(WayTaskDesign.primaryText)
            Text(message)
                .font(WayTaskDesign.Typography.body)
                .foregroundStyle(WayTaskDesign.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(WayTaskDesign.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WayTaskDesign.background.ignoresSafeArea())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("product-state-runtime-cutover-blocked")
    }
}
