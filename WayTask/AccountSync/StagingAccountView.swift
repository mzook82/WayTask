import AuthenticationServices
import SwiftData
import SwiftUI
import UIKit

struct StagingAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var account: StagingAccountController
    @EnvironmentObject private var productState: ProductStateRuntime
    @State private var displayName = ""

    var body: some View {
        NavigationStack {
            List {
                environmentSection
                statusSection
                actionsSection
                if isSignedIn {
                    profileSection
                    GuestMigrationPreviewSection(
                        modelContainer: productState.modelContainer,
                        account: account
                    )
                }
            }
            .navigationTitle("Staging Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await account.restoreSessionIfNeeded()
                if displayName.isEmpty {
                    displayName = account.suggestedDisplayName ??
                        account.savedDisplayName ?? ""
                }
            }
            .onChange(of: account.suggestedDisplayName) { _, value in
                guard displayName.isEmpty, let value else { return }
                displayName = value
            }
        }
    }

    private var environmentSection: some View {
        Section("Internal environment") {
            LabeledContent("Cloud", value: account.environmentLabel)
            LabeledContent("Sync", value: "Off")
            LabeledContent("Migration", value: accountMigrationLabel)
            LabeledContent("Secure AI", value: "Off unless separately enabled")
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        Section("Account status") {
            switch account.snapshot.state {
            case .guest:
                statusRow(
                    title: unavailableTitle ?? "Continue as Guest",
                    message: unavailableMessage ??
                        "Everything remains stored on this device."
                )
            case .signingIn:
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Signing in securely…")
                }
            case .signedInLocalDataNotBackedUp,
                    .signedInInitialMigrationPending,
                    .signedInSynchronizationPaused:
                statusRow(
                    title: "Signed in",
                    message: "You’re signed in. Your existing data is still stored on this device until you choose to move it to your account."
                )
                Label("Migration not yet performed", systemImage: "iphone")
                    .foregroundStyle(.orange)
            case .sessionExpired:
                statusRow(
                    title: account.lastFailure == .offline
                        ? "Offline"
                        : "Session expired",
                    message: account.lastFailure?.userFacingMessage ??
                        "Sign in again. Your local data is unchanged."
                )
            case .recoverableSyncError:
                statusRow(
                    title: "Local ownership protected",
                    message: "This device dataset is already pending or linked to another account. It was not transferred."
                )
            case .signedInSynchronizationActive:
                statusRow(
                    title: "Signed in",
                    message: "Account access is active. Cloud synchronization is not part of this staging sprint."
                )
            case .accountDeletionPending:
                statusRow(
                    title: "Account unavailable",
                    message: "Account changes are temporarily unavailable. Local data remains on this device."
                )
            }

            if let failure = account.lastFailure,
               account.snapshot.state != .sessionExpired {
                statusRow(
                    title: failure.userFacingTitle,
                    message: failure.userFacingMessage
                )
            }
        }
    }

    @ViewBuilder
    private var actionsSection: some View {
        Section {
            if !isSignedIn {
                NativeAppleSignInButton {
                    Task { await account.signInWithApple() }
                }
                .frame(height: 50)
                .disabled(!account.canStartAuthentication)

                Button("Continue as Guest") { dismiss() }
            } else {
                Button("Sign out", role: .destructive) {
                    Task { await account.signOut() }
                }
            }

            if account.snapshot.state == .sessionExpired ||
                account.lastFailure == .offline ||
                account.lastFailure == .serviceUnavailable {
                Button("Try again") {
                    Task { await account.restoreSessionIfNeeded(force: true) }
                }
            }
        } footer: {
            Text("Signing in never uploads, deletes, relinks, or synchronizes your current products, lists, stores, or shopping history.")
        }
    }

    private var profileSection: some View {
        Section("Optional profile") {
            TextField("Display name", text: $displayName)
                .textContentType(.name)
                .autocorrectionDisabled()

            if let validation = account.profileValidationError {
                Text(validation.userMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button("Save display name") {
                Task { await account.saveDisplayName(displayName) }
            }
            .disabled(displayName.isEmpty)

            Text("Names may use Hebrew, Arabic, accented Latin, CJK, and emoji. Invisible direction controls and control characters are rejected.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var isSignedIn: Bool {
        switch account.snapshot.authentication {
        case .signedIn, .deletionPending:
            return true
        case .guest, .signingIn, .sessionExpired:
            return false
        }
    }

    private var accountMigrationLabel: String {
        switch account.snapshot.localDataOwnership {
        case .guestOnly: "Not performed"
        case .migrationPending: "Prepared or in progress"
        case .linked: "Completed; Sync off"
        }
    }

    private var unavailableTitle: String? {
        guard !account.canStartAuthentication else { return nil }
        switch account.configurationStatus {
        case .notConfigured, .invalid:
            return "Service unavailable"
        case .configured:
            return account.lastFailure?.userFacingTitle ??
                "Accounts disabled in this build"
        }
    }

    private var unavailableMessage: String? {
        guard !account.canStartAuthentication else { return nil }
        switch account.configurationStatus {
        case .notConfigured, .invalid:
            return "Staging account configuration is missing or invalid. Guest Mode still works."
        case .configured:
            return account.lastFailure?.userFacingMessage ??
                "Use an approved internal staging build to test accounts."
        }
    }

    private func statusRow(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct GuestMigrationPreviewSection: View {
    @ObservedObject var account: StagingAccountController
    @StateObject private var migration: GuestMigrationCoordinator
    @State private var showsConsent = false

    init(
        modelContainer: ModelContainer,
        account: StagingAccountController
    ) {
        self.account = account
        _migration = StateObject(
            wrappedValue: GuestMigrationCoordinator.live(
                modelContainer: modelContainer,
                localDataSetID: account.localDataSetID,
                transport: account.makeGuestMigrationTransport()
            )
        )
    }

    var body: some View {
        Section("Move local data — Staging") {
            if let preview = migration.preview {
                LabeledContent(
                    "Products",
                    value: String(preview.dataset.counts.personalProducts)
                )
                LabeledContent(
                    "Lists",
                    value: String(preview.dataset.counts.shoppingLists)
                )
                LabeledContent(
                    "List items",
                    value: String(preview.dataset.counts.shoppingListEntries)
                )
                Text("Not included: photos, recognition details, shopping history, saved locations, notifications and geofences, or legacy Product Knowledge.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Your existing data stays on this device. Moving it will not turn Sync on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                switch migration.state {
                case .migrationPreparing, .migrationUploading,
                     .migrationVerifying, .migrationInterrupted,
                     .migrationRecoverable:
                    Button("Resume migration") { resumeMigration() }
                    if migration.canCancelBeforeUpload {
                        Button("Cancel before upload", role: .cancel) {
                            try? migration.cancelBeforeUpload()
                        }
                    }
                case .migrationRollbackRequired:
                    Button("Roll back partial migration", role: .destructive) {
                        rollbackMigration()
                    }
                case .migrationCompleted:
                    Text("The verified copy belongs to this account. Your original local data remains available and Sync is still off.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .migrationConflict, .migrationBlocked:
                    EmptyView()
                case .guestLocal, .authenticatedLocalUnlinked,
                     .migrationPreviewAvailable, .migrationConsentRequired:
                    Button("Review consent") {
                        migration.requireConsent()
                        showsConsent = true
                    }
                }
            } else {
                Button("Preview what would move") {
                    guard let userID = account.authenticatedUserID else {
                        return
                    }
                    _ = try? migration.makePreview(targetUserID: userID)
                }
            }

            if migration.state == .migrationConsentRequired {
                Text("A separate confirmation will be required before migration. Migration is currently disabled by the security gate.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let error = migration.lastError {
                Text(error.userMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            LabeledContent("Migration", value: migrationStatusLabel)
            LabeledContent("Sync", value: "Off")
        }
        .task { migration.reconcile(session: account.snapshot) }
        .onChange(of: account.snapshot) { _, value in
            migration.reconcile(session: value)
        }
        .confirmationDialog(
            "Move this local dataset to the signed-in account?",
            isPresented: $showsConsent,
            titleVisibility: .visible
        ) {
            Button("Confirm move to this account") {
                prepareAndStartMigration()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your existing data will stay on this device. Sync will remain off. Switching accounts after preparation can block migration.")
        }
    }

    private var migrationStatusLabel: String {
        switch migration.state {
        case .guestLocal: "Guest data on device"
        case .authenticatedLocalUnlinked: "Ready to preview"
        case .migrationPreviewAvailable: "Preview available"
        case .migrationConsentRequired: "Consent required"
        case .migrationPreparing: "Preparing"
        case .migrationUploading: "Uploading"
        case .migrationVerifying: "Verifying"
        case .migrationInterrupted:
            migration.lastError == .offline ? "Paused offline" : "Interrupted"
        case .migrationRecoverable:
            migration.lastError == .sessionExpired
                ? "Session expired" : "Recovery available"
        case .migrationCompleted: "Completed; Sync off"
        case .migrationConflict: "Account conflict"
        case .migrationRollbackRequired: "Recovery required"
        case .migrationBlocked: "Blocked by security gate"
        }
    }

    private func prepareAndStartMigration() {
        guard let userID = account.authenticatedUserID,
              let preview = migration.preview else { return }
        Task {
            do {
                let activation = account.migrationActivationEvidence()
                try migration.consentAndPrepare(
                    fingerprint: preview.datasetFingerprint,
                    targetUserID: userID,
                    activation: activation,
                    bindAccount: {
                        account.prepareInitialMigrationBinding(
                            expectedUserID: userID
                        )
                    }
                )
                try await executeMigration(
                    userID: userID,
                    activation: activation
                )
            } catch {
                // Only the coordinator's typed, user-safe error is shown.
            }
        }
    }

    private func resumeMigration() {
        guard let userID = account.authenticatedUserID else { return }
        Task {
            do {
                try await executeMigration(
                    userID: userID,
                    activation: account.migrationActivationEvidence()
                )
            } catch {
                // Only the coordinator's typed, user-safe error is shown.
            }
        }
    }

    private func executeMigration(
        userID: UUID,
        activation: GuestMigrationActivationEvidence
    ) async throws {
        try await migration.execute(
            targetUserID: userID,
            activation: activation,
            localOwnership: account.snapshot.localDataOwnership,
            markCompleted: {
                account.markInitialMigrationCompleted(expectedUserID: userID)
            }
        )
    }

    private func rollbackMigration() {
        guard let userID = account.authenticatedUserID else { return }
        Task {
            do {
                try await migration.rollbackBeforeCompletion(
                    targetUserID: userID,
                    activation: account.migrationActivationEvidence(),
                    localOwnership: account.snapshot.localDataOwnership
                )
            } catch {
                // Only the coordinator's typed, user-safe error is shown.
            }
        }
    }
}

private struct NativeAppleSignInButton: UIViewRepresentable {
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(
            authorizationButtonType: .signIn,
            authorizationButtonStyle: .whiteOutline
        )
        button.cornerRadius = 10
        button.addTarget(
            context.coordinator,
            action: #selector(Coordinator.activate),
            for: .touchUpInside
        )
        return button
    }

    func updateUIView(
        _ uiView: ASAuthorizationAppleIDButton,
        context: Context
    ) {
        uiView.isEnabled = context.environment.isEnabled
    }

    @MainActor
    final class Coordinator: NSObject {
        private let action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func activate() {
            action()
        }
    }
}
