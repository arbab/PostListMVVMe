//
//  PostServicing.swift
//  PostListMVVM
//
//  Created by Arbab Nawaz on 11/7/26.
//

import Foundation

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
