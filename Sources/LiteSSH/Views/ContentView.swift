import SwiftUI

struct ContentView: View {
    @EnvironmentObject var profileStore: ProfileStore
    @EnvironmentObject var sessionStore: SessionStore

    @State private var showingEditor = false
    @State private var editingProfile: ServerProfile?

    var body: some View {
        NavigationSplitView {
            ServerListView(editingProfile: $editingProfile, showingEditor: $showingEditor)
        } detail: {
            if let id = sessionStore.selectedProfileID,
               let profile = profileStore.profiles.first(where: { $0.id == id }) {
                DetailView(
                    profile: profile,
                    connection: sessionStore.connection(for: profile),
                    onEdit: {
                        editingProfile = profile
                        showingEditor = true
                    }
                )
                .id(profile.id)
            } else {
                EmptyStateView {
                    editingProfile = nil
                    showingEditor = true
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            ServerEditView(initialProfile: editingProfile ?? ServerProfile.newDraft(), isNew: editingProfile == nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: .liteSSHNewProfile)) { _ in
            editingProfile = nil
            showingEditor = true
        }
    }
}
