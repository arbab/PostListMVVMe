// MVVMPostList.swift
// MVVM + List + modern concurrency, written to avoid retain cycles.
// Requires iOS 17+ (uses @Observable). Swift 6 / Xcode 16 friendly.

import SwiftUI

// MARK: - View
struct PostListView: View {
    @State private var viewModel: PostListViewModel
    @State var post: Post? = nil
    
    init(service: any PostServicing = PostService()) {
        _viewModel = State(initialValue: PostListViewModel(service: service))
    }
    
    var body: some View {
        //@Bindable var viewModel = viewModel   // enables $viewModel.searchText
 
     
        NavigationSplitView {
            content
                .navigationTitle("Posts")
                .searchable(text: $viewModel.searchText, prompt: "Search titles")
                .refreshable { await viewModel.load() }
        } detail: {
            PostDetailView(post: post)
        }
        
//        NavigationStack {
//            content
//                .navigationTitle("Posts")
//                .searchable(text: $viewModel.searchText, prompt: "Search titles")
//                .refreshable { await viewModel.load() }
//            
//            
//        }
        
        // `.task` runs when the view appears and is auto-cancelled on disappear.
        .task { await viewModel.load() }
        .task { await viewModel.reloadWhenDayChanges() }
    }
    
    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle,
                .loading where viewModel.visiblePosts.isEmpty:
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
            //            .background(content: {
            //                Image("glass-horizontal")
            //            })
            //If your view has a hero or background image, extend it under a vertical bar
            // backgroundExtensionEffect() // Crashes at this point
            //.toolbarVerticalBehavior(.disabled)
            //.toolbarVerticalCompressionBehavior(.prefersToolbarItems)
            .toolbar {
                if #available(anyAppleOS 27.1, *) {
                    ToolbarOverflowMenu {
                        Button("Scan") { }
                        Button("Connect") {   }
                    }
                    .axisBehavior(.verticalPreferred)
                    
                    ToolbarItem(placement: .topBarPinnedTrailing) {
                        Button("Edit", systemImage: "pencil") { }
                    }.axisBehavior(.horizontalOnly)
                } else {
                    // Fallback on earlier versions
                    ToolbarOverflowMenu {
                        Button("Scan") { }
                        Button("Connect") {   }
                    }.customizationBehavior(.disabled)
                    
                    ToolbarItem(placement: .topBarPinnedTrailing) {
                        Button("Edit", systemImage: "pencil") { }
                    }
                }
            }
            .navigationDestination(for: Post.self) { PostDetailView(post: $0) }
            .navigationSplitViewStyle(.automatic)
            
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
