//
//  PostListViewModel.swift
//  PostListMVVM
//
//  Created by Arbab Nawaz on 11/7/26.
//

import Foundation

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
