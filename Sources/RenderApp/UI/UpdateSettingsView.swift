import SwiftUI

struct UpdateSettingsView: View {
    @ObservedObject var updates: AppUpdater
    var body: some View {
        Form {
            LabeledContent("Version",value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development")
            LabeledContent("Channel",value: "Development releases")
            Divider()
            Toggle("Check for updates automatically",isOn: Binding(get: { updates.automaticChecks },set: updates.setAutomaticChecks))
            Toggle("Download and install updates automatically",isOn: Binding(get: { updates.automaticDownloads },set: updates.setAutomaticDownloads))
                .disabled(!updates.automaticChecks)
            Text("Updates download in the background and install when Render quits. Save prompts and running exports still apply.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false,vertical: true)
            HStack {
                if let date = updates.lastCheck {
                    Text("Last checked: \(date.formatted(date: .abbreviated,time: .shortened))")
                } else { Text("Not checked yet") }
                Spacer()
                Button("Check Now") { updates.check() }.disabled(!updates.canCheck)
            }.font(.system(size: 11))
        }.padding(24).frame(width: 460)
    }
}
