import Foundation
import Testing
@testable import MyApp

@MainActor
struct PostListViewModelTests {
    private let posts = [
        Post(id: 10, title: "Swift Concurrency", body: "First body"),
        Post(id: 20, title: "Testing Apps", body: "Swift appears only in the body"),
        Post(id: 30, title: "SwiftUI Layout", body: "Third body")
    ]

    @Test func startsIdleWithNoPosts() {
        let model = PostListViewModel(service: StubPostService(result: .success(posts)))

        #expect(model.state == .idle)
        #expect(model.visiblePosts.isEmpty)
        #expect(model.searchText.isEmpty)
    }

    @Test func loadPublishesPostsInServiceOrder() async {
        let model = PostListViewModel(service: StubPostService(result: .success(posts)))

        await model.load()

        #expect(model.state == .loaded)
        #expect(model.visiblePosts == posts)
    }

    @Test func emptyResponseIsLoaded() async {
        let model = PostListViewModel(service: StubPostService(result: .success([])))

        await model.load()

        #expect(model.state == .loaded)
        #expect(model.visiblePosts.isEmpty)
    }

    @Test func failurePublishesErrorMessage() async {
        let error = URLError(.notConnectedToInternet)
        let model = PostListViewModel(service: StubPostService(result: .failure(error)))

        await model.load()

        #expect(model.state == .failed(error.localizedDescription))
        #expect(model.visiblePosts.isEmpty)
    }

    @Test(arguments: [false, true])
    func cancellationDoesNotPublishFailure(urlCancellation: Bool) async {
        let error: any Error = urlCancellation ? URLError(.cancelled) : CancellationError()
        let model = PostListViewModel(service: StubPostService(result: .failure(error)))

        await model.load()

        if case .failed = model.state {
            Issue.record("Cancellation should not be presented as a failure")
        }
        #expect(model.visiblePosts.isEmpty)
    }

    @Test(arguments: ["  sWiFt  ", "   ", "missing"])
    func loadAppliesCurrentSearch(query: String) async {
        let model = PostListViewModel(service: StubPostService(result: .success(posts)))
        model.searchText = query

        await model.load()

        let expected = query == "   " ? posts : query == "missing" ? [] : [posts[0], posts[2]]
        #expect(model.visiblePosts == expected)
        #expect(model.state == .loaded)
    }

    @Test func searchChangesEventuallyUpdateVisiblePosts() async throws {
        let model = PostListViewModel(service: StubPostService(result: .success(posts)))
        await model.load()

        model.searchText = "Swift"
        model.searchText = "Testing"
        try await waitForPosts([posts[1]], in: model)

        model.searchText = ""
        try await waitForPosts(posts, in: model)
    }

    @Test func deletingFilteredRowRemovesCorrectPostFromFullList() async throws {
        let model = PostListViewModel(service: StubPostService(result: .success(posts)))
        model.searchText = "Testing"
        await model.load()
        try #require(model.visiblePosts == [posts[1]])

        model.delete(at: IndexSet(integer: 0))

        #expect(model.visiblePosts.isEmpty)
        model.searchText = ""
        try await waitForPosts([posts[0], posts[2]], in: model)
    }

    @Test func deleteSupportsMultipleOffsets() async {
        let model = PostListViewModel(service: StubPostService(result: .success(posts)))
        await model.load()

        model.delete(at: IndexSet([0, 2]))

        #expect(model.visiblePosts == [posts[1]])
    }

    // Poll with a deadline so debounce tests tolerate scheduler delays.
    private func waitForPosts(_ expected: [Post], in model: PostListViewModel) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while model.visiblePosts != expected && clock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(model.visiblePosts == expected)
    }
}

private struct StubPostService: PostServicing {
    let result: Result<[Post], any Error>

    func fetchPosts() async throws -> [Post] {
        try result.get()
    }
}
