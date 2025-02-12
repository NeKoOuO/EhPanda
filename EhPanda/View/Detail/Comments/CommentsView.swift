//
//  CommentsView.swift
//  EhPanda
//
//  Created by 荒木辰造 on R 3/01/02.
//

import SwiftUI
import Kingfisher
import ComposableArchitecture

struct CommentsView: View {
    @Bindable private var store: StoreOf<CommentsReducer>
    private let gid: String
    private let token: String
    private let apiKey: String
    private let galleryURL: URL
    private let comments: [GalleryComment]
    private let user: User
    @Binding private var setting: Setting
    private let blurRadius: Double
    private let tagTranslator: TagTranslator

    init(
        store: StoreOf<CommentsReducer>,
        gid: String, token: String, apiKey: String, galleryURL: URL,
        comments: [GalleryComment], user: User, setting: Binding<Setting>,
        blurRadius: Double, tagTranslator: TagTranslator
    ) {
        self.store = store
        self.gid = gid
        self.token = token
        self.apiKey = apiKey
        self.galleryURL = galleryURL
        self.comments = comments
        self.user = user
        _setting = setting
        self.blurRadius = blurRadius
        self.tagTranslator = tagTranslator
    }

    // MARK: CommentView
    var body: some View {
        ScrollViewReader { proxy in
            List(comments) { comment in
                CommentCell(
                    gid: gid, comment: comment,
                    linkAction: { store.send(.handleCommentLink($0)) }
                )
                .opacity(
                    comment.commentID == store.scrollCommentID
                    ? store.scrollRowOpacity : 1
                )
                .swipeActions(edge: .leading) {
                    if comment.votable {
                        Button {
                            store.send(.voteComment(gid, token, apiKey, comment.commentID, -1))
                        } label: {
                            Image(systemSymbol: .handThumbsdown)
                        }
                        .tint(.red)
                    }
                }
                .swipeActions(edge: .trailing) {
                    if comment.votable {
                        Button {
                            store.send(.voteComment(gid, token, apiKey, comment.commentID, 1))
                        } label: {
                            Image(systemSymbol: .handThumbsup)
                        }
                        .tint(.green)
                    }
                    if comment.editable {
                        Button {
                            store.send(.setCommentContent(comment.plainTextContent))
                            store.send(.setNavigation(.postComment(comment.commentID)))
                        } label: {
                            Image(systemSymbol: .squareAndPencil)
                        }
                    }
                }
            }
            .onAppear {
                if let scrollCommentID = store.scrollCommentID {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                        withAnimation {
                            proxy.scrollTo(scrollCommentID, anchor: .top)
                        }
                    }
                }
            }
        }
        .sheet(item: $store.route.sending(\.setNavigation).postComment, id: \.self) { route in
            let hasCommentID = !route.wrappedValue.isEmpty
            PostCommentView(
                title: hasCommentID
                ? L10n.Localizable.PostCommentView.Title.editComment
                : L10n.Localizable.PostCommentView.Title.postComment,
                content: $store.commentContent,
                isFocused: $store.postCommentFocused,
                postAction: {
                    if hasCommentID {
                        store.send(.postComment(galleryURL, route.wrappedValue))
                    } else {
                        store.send(.postComment(galleryURL))
                    }
                    store.send(.setNavigation(nil))
                },
                cancelAction: { store.send(.setNavigation(nil)) },
                onAppearAction: { store.send(.onPostCommentAppear) }
            )
            .accentColor(setting.accentColor)
            .autoBlur(radius: blurRadius)
        }
        .progressHUD(
            config: store.hudConfig,
            unwrapping: $store.route,
            case: \.hud
        )
        .animation(.default, value: store.scrollRowOpacity)
        .onAppear {
            store.send(.onAppear)
        }
        .background(navigationLink)
        .toolbar(content: toolbar)
        .navigationTitle(L10n.Localizable.CommentsView.Title.comments)
    }

    private func toolbar() -> some ToolbarContent {
        CustomToolbarItem {
            Button {
                store.send(.setNavigation(.postComment("")))
            } label: {
                Image(systemSymbol: .squareAndPencil)
            }
            .disabled(!CookieUtil.didLogin)
        }
    }
}

// MARK: NavigationLinks
private extension CommentsView {
    @ViewBuilder var navigationLink: some View {
        NavigationLink(unwrapping: $store.route, case: \.detail) { route in
            DetailView(
                store: store.scope(state: \.detailState.wrappedValue!, action: \.detail),
                gid: route.wrappedValue, user: user, setting: $setting,
                blurRadius: blurRadius, tagTranslator: tagTranslator
            )
        }
    }
}

// MARK: CommentCell
private struct CommentCell: View {
    private let gid: String
    private var comment: GalleryComment
    private let linkAction: (URL) -> Void

    init(gid: String, comment: GalleryComment, linkAction: @escaping (URL) -> Void) {
        self.gid = gid
        self.comment = comment
        self.linkAction = linkAction
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(comment.author).font(.subheadline.bold())
                Spacer()
                Group {
                    ZStack {
                        Image(systemSymbol: .handThumbsupFill)
                            .opacity(comment.votedUp ? 1 : 0)
                        Image(systemSymbol: .handThumbsdownFill)
                            .opacity(comment.votedDown ? 1 : 0)
                    }
                    Text(comment.score ?? "")
                    Text(comment.formattedDateString)
                }
                .font(.footnote).foregroundStyle(.secondary)
            }
            .minimumScaleFactor(0.75).lineLimit(1)
            ForEach(comment.contents) { content in
                switch content.type {
                case .plainText:
                    if let text = content.text {
                        LinkedText(text: text, action: linkAction)
                    }
                case .linkedText:
                    if let text = content.text, let link = content.link {
                        Text(text).foregroundStyle(.tint)
                            .onTapGesture { linkAction(link) }
                    }
                case .singleLink:
                    if let link = content.link {
                        Text(link.absoluteString).foregroundStyle(.tint)
                            .onTapGesture { linkAction(link) }
                    }
                case .singleImg, .doubleImg, .linkedImg, .doubleLinkedImg:
                    generateWebImages(
                        imgURL: content.imgURL, secondImgURL: content.secondImgURL,
                        link: content.link, secondLink: content.secondLink
                    )
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
    }

    @ViewBuilder private func generateWebImages(
        imgURL: URL?, secondImgURL: URL?,
        link: URL?, secondLink: URL?
    ) -> some View {
        // Double
        if let imgURL = imgURL, let secondImgURL = secondImgURL {
            HStack(spacing: 0) {
                if let link = link, let secondLink = secondLink {
                    imageContainer(url: imgURL, widthFactor: 4) {
                        linkAction(link)
                    }
                    imageContainer(url: secondImgURL, widthFactor: 4) {
                        linkAction(secondLink)
                    }
                } else {
                    imageContainer(url: imgURL, widthFactor: 4)
                    imageContainer(url: secondImgURL, widthFactor: 4)
                }
            }
        }
        // Single
        else if let imgURL = imgURL {
            if let link = link {
                imageContainer(url: imgURL, widthFactor: 2) {
                    linkAction(link)
                }
            } else {
                imageContainer(url: imgURL, widthFactor: 2)
            }
        }
    }
    @ViewBuilder func imageContainer(
        url: URL, widthFactor: Double, action: (() -> Void)? = nil
    ) -> some View {
        let image = KFImage(url)
            .commentDefaultModifier().scaledToFit()
            .frame(width: DeviceUtil.windowW / widthFactor)
        if let action = action {
            Button(action: action) {
                image
            }
            .buttonStyle(.plain)
        } else {
            image
        }
    }
}

private extension KFImage {
    func commentDefaultModifier() -> KFImage {
        defaultModifier()
            .placeholder {
                Placeholder(style: .activity(ratio: 1))
            }
    }
}

struct CommentsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            CommentsView(
                store: .init(initialState: .init(), reducer: CommentsReducer.init),
                gid: .init(),
                token: .init(),
                apiKey: .init(),
                galleryURL: .mock,
                comments: [],
                user: .init(),
                setting: .constant(.init()),
                blurRadius: 0,
                tagTranslator: .init()
            )
        }
    }
}
