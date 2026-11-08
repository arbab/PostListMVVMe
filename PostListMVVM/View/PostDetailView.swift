//
//  PostDetailView.swift
//  PostListMVVM
//
//  Created by Arbab Nawaz on 11/7/26.
//

import SwiftUI

struct PostDetailView: View {
    let post: Post?
    var body: some View {
        if let post = post {
            ScrollView {
                Text(post.body).padding()
            }
            .background(content: {
                Rectangle()
                    .fill( Color.blue.gradient.opacity(0.1))
            })
            .navigationTitle(post.title)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Select Post", image: "list.bullet")
        }
    }
}
