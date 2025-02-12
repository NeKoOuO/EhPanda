//
//  DetailReducer.swift
//  EhPanda
//
//  Created by 荒木辰造 on R 4/01/10.
//

import SwiftUI
import Foundation
import ComposableArchitecture

@Reducer
struct DetailReducer {
    @CasePathable
    enum Route: Equatable {
        case reading(EquatableVoid = .init())
        case archives(URL, URL)
        case torrents(EquatableVoid = .init())
        case previews
        case comments(URL)
        case share(URL)
        case postComment(EquatableVoid = .init())
        case newDawn(Greeting)
        case detailSearch(String)
        case tagDetail(TagDetail)
        case galleryInfos(Gallery, GalleryDetail)
    }

    private enum CancelID: CaseIterable {
        case fetchDatabaseInfos, fetchGalleryDetail, rateGallery, favorGallery, unfavorGallery, postComment, voteTag
    }

    @ObservableState
    struct State: Equatable {
        var route: Route?
        var commentContent = ""
        var postCommentFocused = false

        var showsNewDawnGreeting = false
        var showsUserRating = false
        var showsFullTitle = false
        var userRating = 0

        var apiKey = ""
        var loadingState: LoadingState = .idle
        var gallery: Gallery = .empty
        var galleryDetail: GalleryDetail?
        var galleryTags = [GalleryTag]()
        var galleryPreviewURLs = [Int: URL]()
        var galleryComments = [GalleryComment]()

        var readingState = ReadingReducer.State()
        var archivesState = ArchivesReducer.State()
        var torrentsState = TorrentsReducer.State()
        var previewsState = PreviewsReducer.State()
        var commentsState: Heap<CommentsReducer.State?>
        var galleryInfosState = GalleryInfosReducer.State()
        var detailSearchState: Heap<DetailSearchReducer.State?>

        init() {
            commentsState = .init(nil)
            detailSearchState = .init(nil)
        }

        mutating func updateRating(value: DragGesture.Value) {
            let rating = Int(value.location.x / 31 * 2) + 1
            userRating = min(max(rating, 1), 10)
        }
    }

    indirect enum Action: BindableAction {
        case binding(BindingAction<State>)
        case setNavigation(Route?)
        case clearSubStates
        case onPostCommentAppear
        case onAppear(String, Bool)

        case toggleShowFullTitle
        case toggleShowUserRating
        case setCommentContent(String)
        case setPostCommentFocused(Bool)
        case updateRating(DragGesture.Value)
        case confirmRating(DragGesture.Value)
        case confirmRatingDone

        case syncGalleryTags
        case syncGalleryDetail
        case syncGalleryPreviewURLs
        case syncGalleryComments
        case syncGreeting(Greeting)
        case syncPreviewConfig(PreviewConfig)
        case saveGalleryHistory
        case updateReadingProgress(Int)

        case teardown
        case fetchDatabaseInfos(String)
        case fetchDatabaseInfosDone(GalleryState)
        case fetchGalleryDetail
        case fetchGalleryDetailDone(Result<(GalleryDetail, GalleryState, String, Greeting?), AppError>)

        case rateGallery
        case favorGallery(Int)
        case unfavorGallery
        case postComment(URL)
        case voteTag(String, Int)
        case anyGalleryOpsDone(Result<Any, AppError>)

        case reading(ReadingReducer.Action)
        case archives(ArchivesReducer.Action)
        case torrents(TorrentsReducer.Action)
        case previews(PreviewsReducer.Action)
        case comments(CommentsReducer.Action)
        case galleryInfos(GalleryInfosReducer.Action)
        case detailSearch(DetailSearchReducer.Action)
    }

    @Dependency(\.databaseClient) private var databaseClient
    @Dependency(\.hapticsClient) private var hapticsClient
    @Dependency(\.cookieClient) private var cookieClient

    func coreReducer(self: Reduce<State, Action>) -> some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .setNavigation(let route):
                state.route = route
                return route == nil ? .send(.clearSubStates) : .none

            case .clearSubStates:
                state.readingState = .init()
                state.archivesState = .init()
                state.torrentsState = .init()
                state.previewsState = .init()
                state.commentsState.wrappedValue = .init()
                state.commentContent = .init()
                state.postCommentFocused = false
                state.galleryInfosState = .init()
                state.detailSearchState.wrappedValue = .init()
                return .merge(
                    .send(.reading(.teardown)),
                    .send(.archives(.teardown)),
                    .send(.torrents(.teardown)),
                    .send(.previews(.teardown)),
                    .send(.comments(.teardown)),
                    .send(.detailSearch(.teardown))
                )

            case .onPostCommentAppear:
                return .run { send in
                    try await Task.sleep(for: .milliseconds(750))
                    await send(.setPostCommentFocused(true))
                }

            case .onAppear(let gid, let showsNewDawnGreeting):
                state.showsNewDawnGreeting = showsNewDawnGreeting
                if state.detailSearchState.wrappedValue == nil {
                    state.detailSearchState.wrappedValue = .init()
                }
                if state.commentsState.wrappedValue == nil {
                    state.commentsState.wrappedValue = .init()
                }
                return .send(.fetchDatabaseInfos(gid))

            case .toggleShowFullTitle:
                state.showsFullTitle.toggle()
                return .run(operation: { _ in hapticsClient.generateFeedback(.soft) })

            case .toggleShowUserRating:
                state.showsUserRating.toggle()
                return .run(operation: { _ in hapticsClient.generateFeedback(.soft) })

            case .setCommentContent(let content):
                state.commentContent = content
                return .none

            case .setPostCommentFocused(let isFocused):
                state.postCommentFocused = isFocused
                return .none

            case .updateRating(let value):
                state.updateRating(value: value)
                return .none

            case .confirmRating(let value):
                state.updateRating(value: value)
                return .merge(
                    .send(.rateGallery),
                    .run(operation: { _ in hapticsClient.generateFeedback(.soft) }),
                    .run { send in
                        try await Task.sleep(for: .seconds(1))
                        await send(.confirmRatingDone)
                    }
                )

            case .confirmRatingDone:
                state.showsUserRating = false
                return .none

            case .syncGalleryTags:
                return .run { [state] _ in
                    await databaseClient.updateGalleryTags(gid: state.gallery.id, tags: state.galleryTags)
                }

            case .syncGalleryDetail:
                guard let detail = state.galleryDetail else { return .none }
                return .run(operation: { _ in await databaseClient.cacheGalleryDetail(detail) })

            case .syncGalleryPreviewURLs:
                return .run { [state] _ in
                    await databaseClient
                        .updatePreviewURLs(gid: state.gallery.id, previewURLs: state.galleryPreviewURLs)
                }

            case .syncGalleryComments:
                return .run { [state] _ in
                    await databaseClient.updateComments(gid: state.gallery.id, comments: state.galleryComments)
                }

            case .syncGreeting(let greeting):
                return .run(operation: { _ in await databaseClient.updateGreeting(greeting) })

            case .syncPreviewConfig(let config):
                return .run { [state] _ in
                    await databaseClient.updatePreviewConfig(gid: state.gallery.id, config: config)
                }

            case .saveGalleryHistory:
                return .run { [state] _ in
                    await databaseClient.updateLastOpenDate(gid: state.gallery.id)
                }

            case .updateReadingProgress(let progress):
                return .run { [state] _ in
                    await databaseClient.updateReadingProgress(gid: state.gallery.id, progress: progress)
                }

            case .teardown:
                return .merge(CancelID.allCases.map(Effect.cancel(id:)))

            case .fetchDatabaseInfos(let gid):
                guard let gallery = databaseClient.fetchGallery(gid: gid) else { return .none }
                state.gallery = gallery
                if let detail = databaseClient.fetchGalleryDetail(gid: gid) {
                    state.galleryDetail = detail
                }
                return .merge(
                    .send(.saveGalleryHistory),
                    .run { [galleryID = state.gallery.id] send in
                        guard let dbState = await databaseClient.fetchGalleryState(gid: galleryID) else { return }
                        await send(.fetchDatabaseInfosDone(dbState))
                    }
                        .cancellable(id: CancelID.fetchDatabaseInfos)
                )

            case .fetchDatabaseInfosDone(let galleryState):
                state.galleryTags = galleryState.tags
                state.galleryPreviewURLs = galleryState.previewURLs
                state.galleryComments = galleryState.comments
                return .send(.fetchGalleryDetail)

            case .fetchGalleryDetail:
                guard state.loadingState != .loading,
                      let galleryURL = state.gallery.galleryURL
                else { return .none }
                state.loadingState = .loading
                return .run { [galleryID = state.gallery.id] send in
                    let response = await GalleryDetailRequest(gid: galleryID, galleryURL: galleryURL).response()
                    await send(.fetchGalleryDetailDone(response))
                }
                .cancellable(id: CancelID.fetchGalleryDetail)

            case .fetchGalleryDetailDone(let result):
                state.loadingState = .idle
                switch result {
                case .success(let (galleryDetail, galleryState, apiKey, greeting)):
                    var effects: [Effect<Action>] = [
                        .send(.syncGalleryTags),
                        .send(.syncGalleryDetail),
                        .send(.syncGalleryPreviewURLs),
                        .send(.syncGalleryComments)
                    ]
                    state.apiKey = apiKey
                    state.galleryDetail = galleryDetail
                    state.galleryTags = galleryState.tags
                    state.galleryPreviewURLs = galleryState.previewURLs
                    state.galleryComments = galleryState.comments
                    state.userRating = Int(galleryDetail.userRating) * 2
                    if let greeting = greeting {
                        effects.append(.send(.syncGreeting(greeting)))
                        if !greeting.gainedNothing && state.showsNewDawnGreeting {
                            effects.append(.send(.setNavigation(.newDawn(greeting))))
                        }
                    }
                    if let config = galleryState.previewConfig {
                        effects.append(.send(.syncPreviewConfig(config)))
                    }
                    return .merge(effects)
                case .failure(let error):
                    state.loadingState = .failed(error)
                }
                return .none

            case .rateGallery:
                guard let apiuid = Int(cookieClient.apiuid), let gid = Int(state.gallery.id)
                else { return .none }
                return .run { [state] send in
                    let response = await RateGalleryRequest(
                        apiuid: apiuid,
                        apikey: state.apiKey,
                        gid: gid,
                        token: state.gallery.token,
                        rating: state.userRating
                    )
                        .response()
                    await send(.anyGalleryOpsDone(response))
                }.cancellable(id: CancelID.rateGallery)

            case .favorGallery(let favIndex):
                return .run { [state] send in
                    let response = await FavorGalleryRequest(
                        gid: state.gallery.id,
                        token: state.gallery.token,
                        favIndex: favIndex
                    )
                        .response()
                    await send(.anyGalleryOpsDone(response))
                }
                .cancellable(id: CancelID.favorGallery)

            case .unfavorGallery:
                return .run { [galleryID = state.gallery.id] send in
                    let response = await UnfavorGalleryRequest(gid: galleryID).response()
                    await send(.anyGalleryOpsDone(response))
                }
                .cancellable(id: CancelID.unfavorGallery)

            case .postComment(let galleryURL):
                guard !state.commentContent.isEmpty else { return .none }
                return .run { [commentContent = state.commentContent] send in
                    let response = await CommentGalleryRequest(
                        content: commentContent, galleryURL: galleryURL
                    )
                        .response()
                    await send(.anyGalleryOpsDone(response))
                }
                .cancellable(id: CancelID.postComment)

            case .voteTag(let tag, let vote):
                guard let apiuid = Int(cookieClient.apiuid), let gid = Int(state.gallery.id)
                else { return .none }
                return .run { [state] send in
                    let response = await VoteGalleryTagRequest(
                        apiuid: apiuid,
                        apikey: state.apiKey,
                        gid: gid,
                        token: state.gallery.token,
                        tag: tag,
                        vote: vote
                    )
                        .response()
                    await send(.anyGalleryOpsDone(response))
                }
                .cancellable(id: CancelID.voteTag)

            case .anyGalleryOpsDone(let result):
                if case .success = result {
                    return .merge(
                        .send(.fetchGalleryDetail),
                        .run(operation: { _ in hapticsClient.generateNotificationFeedback(.success) })
                    )
                }
                return .run(operation: { _ in hapticsClient.generateNotificationFeedback(.error) })

            case .reading(.onPerformDismiss):
                return .send(.setNavigation(nil))

            case .reading:
                return .none

            case .archives:
                return .none

            case .torrents:
                return .none

            case .previews:
                return .none

            case .comments(.performCommentActionDone(let result)):
                return .send(.anyGalleryOpsDone(result))

            case .comments(.detail(let recursiveAction)):
                guard state.commentsState.wrappedValue != nil else { return .none }
                return self.reduce(
                    into: &state.commentsState.wrappedValue!.detailState.wrappedValue!, action: recursiveAction
                )
                .map({ Action.comments(.detail($0)) })

            case .comments:
                return .none

            case .galleryInfos:
                return .none

            case .detailSearch(.detail(let recursiveAction)):
                guard state.detailSearchState.wrappedValue != nil else { return .none }
                return self.reduce(
                    into: &state.detailSearchState.wrappedValue!.detailState.wrappedValue!, action: recursiveAction
                )
                .map({ Action.detailSearch(.detail($0)) })

            case .detailSearch:
                return .none
            }
        }
        .ifLet(
            \.commentsState.wrappedValue,
             action: \.comments,
             then: CommentsReducer.init
        )
        .ifLet(
            \.detailSearchState.wrappedValue,
             action: \.detailSearch,
             then: DetailSearchReducer.init
        )
    }

    func hapticsReducer(
        @ReducerBuilder<State, Action> reducer: () -> some Reducer<State, Action>
    ) -> some Reducer<State, Action> {
        reducer()
            .haptics(
                unwrapping: \.route,
                case: \.detailSearch,
                hapticsClient: hapticsClient,
                style: .soft
            )
            .haptics(
                unwrapping: \.route,
                case: \.postComment,
                hapticsClient: hapticsClient
            )
            .haptics(
                unwrapping: \.route,
                case: \.tagDetail,
                hapticsClient: hapticsClient
            )
            .haptics(
                unwrapping: \.route,
                case: \.torrents,
                hapticsClient: hapticsClient
            )
            .haptics(
                unwrapping: \.route,
                case: \.archives,
                hapticsClient: hapticsClient
            )
            .haptics(
                unwrapping: \.route,
                case: \.reading,
                hapticsClient: hapticsClient
            )
            .haptics(
                unwrapping: \.route,
                case: \.share,
                hapticsClient: hapticsClient
            )
    }

    var body: some Reducer<State, Action> {
        RecurseReducer { (self) in
            BindingReducer()
                .onChange(of: \.route) { _, newValue in
                    Reduce({ _, _ in newValue == nil ? .send(.clearSubStates) : .none })
                }

            coreReducer(self: self)

            Scope(state: \.readingState, action: \.reading, child: ReadingReducer.init)
            Scope(state: \.archivesState, action: \.archives, child: ArchivesReducer.init)
            Scope(state: \.torrentsState, action: \.torrents, child: TorrentsReducer.init)
            Scope(state: \.previewsState, action: \.previews, child: PreviewsReducer.init)
            Scope(state: \.galleryInfosState, action: \.galleryInfos, child: GalleryInfosReducer.init)
        }
    }
}
