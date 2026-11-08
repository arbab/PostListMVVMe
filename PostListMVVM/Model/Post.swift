//
//  Post.swift
//  PostListMVVM
//
//  Created by Arbab Nawaz on 11/7/26.
//

import Foundation

// MARK: - Model
struct Post: Identifiable, Codable, Hashable, Sendable {
    let id: Int
    let title: String
    let body: String
}
