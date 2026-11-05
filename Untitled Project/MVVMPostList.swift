// MVVMPostList.swift
// MVVM + List + modern concurrency, written to avoid retain cycles.
// Requires iOS 17+ (uses @Observable). Swift 6 / Xcode 16 friendly.

import SwiftUI

// MARK: - Model
struct Post: Identifiable, Codable, Hashable, Sendable {
    let id: Int
    let title: String
    let body: String
}

// MARK: - Service layer (Sendable, no references back to the UI)
protocol PostServicing: Sendable {
    func fetchPosts() async throws -> [Post]
}

struct PostService: PostServicing {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func fetchPosts() async throws -> [Post] {
        let url = URL(string: "https://jsonplaceholder.typicode.com/posts")!
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([Post].self, from: data)
    }
}

// MARK: - ViewModel
@MainActor
@Observable
final class PostListViewModel {

    enum State: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    // Output state (the View only reads these)
    private(set) var state: State = .idle
    private(set) var visiblePosts: [Post] = []

    // Input state (the View writes this through a binding)
    var searchText = "" {
        didSet { scheduleFilter() }
    }

    private var allPosts: [Post] = []
    private let service: any PostServicing

    // Stored Task: this is the ONE place a cycle could form, so it captures [weak self].
    private var filterTask: Task<Void, Never>?

    init(service: any PostServicing) {
        self.service = service
    }

    // MARK: Intents

    /// Called from `.task` and `.refreshable`.
    /// The VIEW owns this task, so SwiftUI cancels it when the view goes away.
    /// The view model never stores it, so there is no cycle to break.
    func load() async {
        if allPosts.isEmpty { state = .loading }
        do {
            allPosts = try await service.fetchPosts()
            applyFilter()
            state = .loaded
        } catch is CancellationError {
            // View disappeared or pull-to-refresh was cancelled: not an error.
        } catch let error as URLError where error.code == .cancelled {
            // Same as above, URLSession flavor.
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Long-lived async sequence. Because the view owns the task (via `.task`),
    /// leaving the screen cancels the `for await` loop and releases everything.
    func reloadWhenDayChanges() async {
        for await _ in NotificationCenter.default.notifications(named: .NSCalendarDayChanged) {
            await load()
        }
    }

    func delete(at offsets: IndexSet) {
        let ids = offsets.map { visiblePosts[$0].id }
        allPosts.removeAll { ids.contains($0.id) }
        applyFilter()
    }

    // MARK: Debounced filtering (the stored-Task case)

    private func scheduleFilter() {
        filterTask?.cancel()
        filterTask = Task { [weak self] in          // weak: the Task must not keep the VM alive
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }   // strong only for the short body
            self.applyFilter()
        }
    }

    private func applyFilter() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        visiblePosts = query.isEmpty
            ? allPosts
            : allPosts.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }
}

// MARK: - View
struct PostListView: View {
    @State private var viewModel: PostListViewModel

    init(service: any PostServicing = PostService()) {
        _viewModel = State(initialValue: PostListViewModel(service: service))
    }

    var body: some View {
        @Bindable var viewModel = viewModel   // enables $viewModel.searchText

        NavigationStack {
            content
                .navigationTitle("Posts")
                .searchable(text: $viewModel.searchText, prompt: "Search titles")
                .refreshable { await viewModel.load() }
        }
        // `.task` runs when the view appears and is auto-cancelled on disappear.
        .task { await viewModel.load() }
        .task { await viewModel.reloadWhenDayChanges() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading where viewModel.visiblePosts.isEmpty:
            ProgressView("Loading…")

        case .failed(let message) where viewModel.visiblePosts.isEmpty:
            ContentUnavailableView {
                Label("Couldn't load", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Retry") { Task { await viewModel.load() } }   // short-lived, no cycle
            }

        default:
            List {
                ForEach(viewModel.visiblePosts) { post in
                    NavigationLink(value: post) { PostRow(post: post) }
                        .contextMenu {
                            NavigationLink("Open Post", value: post)
                        } preview: {
                            PostPreviewView(post: post)
                        }
                        .accessibilityHint("Touch and hold to preview this post.")
                }
                .onDelete(perform: viewModel.delete)
            }
            .navigationDestination(for: Post.self) { PostDetailView(post: $0) }
            .overlay {
                if viewModel.visiblePosts.isEmpty {
                    ContentUnavailableView.search(text: viewModel.searchText)
                }
            }
        }
    }
}

struct PostRow: View {
    let post: Post
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(post.title).font(.headline).lineLimit(1)
            Text(post.body).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
        }
    }
}

private struct PostPreviewView: View {
    let post: Post

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(post.title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(post.body)
                    .font(.body)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .frame(idealWidth: 320, idealHeight: 360)
        .background(.background)
    }
}

struct PostDetailView: View {
    let post: Post
    var body: some View {
        ScrollView {
            Text(post.body).padding()
        }
        .navigationTitle(post.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Preview with a mock service (the payoff of protocol-based DI)
private struct MockPostService: PostServicing {
    func fetchPosts() async throws -> [Post] {
        try await Task.sleep(for: .seconds(1))
        return (1...20).map { Post(id: $0, title: "Post \($0)", body: "Body text for post \($0).") }
    }
}

#Preview {
    PostListView(service: MockPostService())
}
