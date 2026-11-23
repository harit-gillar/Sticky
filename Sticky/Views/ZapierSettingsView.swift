import SwiftUI

struct ZapierSettingsView: View {
    @Environment(\.dismiss) var dismiss

    @State private var isEnabled: Bool
    @State private var taskCompletedURL: String
    @State private var taskCreatedURL: String
    @State private var taskDeletedURL: String

    /// Per-field result of the Test button. Editing a URL resets it, so a
    /// result always belongs to the URL that's showing.
    enum WebhookTest: Equatable {
        case untested, testing, passed, failed
    }
    @State private var tests: [String: WebhookTest] = [:]

    private var isTestingAny: Bool { tests.values.contains(.testing) }

    private let service = ZapierWebhookService.shared

    init() {
        let svc = ZapierWebhookService.shared
        _isEnabled = State(initialValue: svc.isEnabled)
        _taskCompletedURL = State(initialValue: svc.taskCompletedURL)
        _taskCreatedURL = State(initialValue: svc.taskCreatedURL)
        _taskDeletedURL = State(initialValue: svc.taskDeletedURL)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Zapier Integration")
                .font(.title2.bold())

            Text("Connect Sticky to hundreds of apps via Zapier webhooks.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Enable Zapier Integration", isOn: $isEnabled)

            if isEnabled {
                VStack(alignment: .leading, spacing: 12) {
                    Text("How to set up:")
                        .font(.subheadline.bold())
                    Text("1. Create a Zap on zapier.com\n2. Choose \"Webhooks by Zapier\" → \"Catch Hook\" as trigger\n3. Copy the webhook URL and paste it below")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider()

                    webhookField(
                        label: "Task Completed",
                        url: $taskCompletedURL,
                        key: "completed"
                    )

                    webhookField(
                        label: "Task Created",
                        url: $taskCreatedURL,
                        key: "created"
                    )

                    webhookField(
                        label: "Task Deleted",
                        url: $taskDeletedURL,
                        key: "deleted"
                    )
                }
                .padding(.leading, 4)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    service.isEnabled = isEnabled
                    service.taskCompletedURL = taskCompletedURL
                    service.taskCreatedURL = taskCreatedURL
                    service.taskDeletedURL = taskDeletedURL
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480, height: isEnabled ? 500 : 200)
    }

    @ViewBuilder
    private func webhookField(label: String, url: Binding<String>, key: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline.bold())

            HStack {
                TextField("https://hooks.zapier.com/hooks/catch/...", text: url)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))

                Button(action: {
                    testWebhook(urlString: url.wrappedValue, key: key)
                }) {
                    switch tests[key] ?? .untested {
                    case .testing:
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 50)
                    case .passed, .failed:
                        let passed = tests[key] == .passed
                        HStack(spacing: 2) {
                            Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(passed ? .green : .red)
                            Text(passed ? "OK" : "Fail")
                                .font(.caption)
                        }
                        .frame(width: 50)
                    case .untested:
                        Text("Test")
                            .frame(width: 50)
                    }
                }
                .disabled(url.wrappedValue.isEmpty || isTestingAny)
            }
            .onChange(of: url.wrappedValue) { _, _ in
                // An old OK/Fail doesn't describe a URL you've since changed
                if tests[key] != .testing { tests[key] = .untested }
            }
        }
    }

    private func testWebhook(urlString: String, key: String) {
        tests[key] = .testing

        Task {
            let passed = await service.testWebhook(urlString: urlString)
            await MainActor.run {
                tests[key] = passed ? .passed : .failed
            }
        }
    }
}
