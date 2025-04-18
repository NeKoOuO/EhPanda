//
//  SearchRootReducer.swift
//  EhPanda
//
//  Created by 荒木辰造 on R 4/01/09.
//

import ComposableArchitecture

@Reducer
struct SearchRootReducer {
    @CasePathable
    enum Route: Equatable {
        case search
        case filters(EquatableVoid = .init())
        case quickSearch(EquatableVoid = .init())
        case detail(String)
    }

    @ObservableState
    struct State: Equatable {
        var route: Route?
        var keyword = ""
        var historyGalleries = [Gallery]()

        var historyKeywords = [String]()
        var quickSearchWords = [QuickSearchWord]()

        var searchState = SearchReducer.State()
        var filtersState = FiltersReducer.State()
        var quickSearchState = QuickSearchReducer.State()
        var detailState: Heap<DetailReducer.State?>

        init() {
            detailState = .init(.init())
        }

        mutating func appendHistoryKeywords(_ keywords: [String]) {
            guard !keywords.isEmpty else { return }
            var historyKeywords = historyKeywords

            keywords.forEach { keyword in
                guard !keyword.isEmpty else { return }
                if let index = historyKeywords.firstIndex(where: {
                    $0.caseInsensitiveEqualsTo(keyword)
                }) {
                    if historyKeywords.last != keyword {
                        historyKeywords.remove(at: index)
                        historyKeywords.append(keyword)
                    }
                } else {
                    historyKeywords.append(keyword)
                    let overflow = historyKeywords.count - 20
                    if overflow > 0 {
                        historyKeywords = Array(
                            historyKeywords.dropFirst(overflow)
                        )
                    }
                }
            }
            self.historyKeywords = historyKeywords
        }

        mutating func removeHistoryKeyword(_ keyword: String) {
            historyKeywords = historyKeywords.filter { $0 != keyword }
        }
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case setNavigation(Route?)
        case setKeyword(String)
        case clearSubStates

        case syncHistoryKeywords
        case fetchDatabaseInfos
        case fetchDatabaseInfosDone(AppEnv)
        case appendHistoryKeyword(String)
        case removeHistoryKeyword(String)
        case fetchHistoryGalleries
        case fetchHistoryGalleriesDone([Gallery])

        case search(SearchReducer.Action)
        case filters(FiltersReducer.Action)
        case quickSearch(QuickSearchReducer.Action)
        case detail(DetailReducer.Action)
    }

    @Dependency(\.databaseClient) private var databaseClient
    @Dependency(\.hapticsClient) private var hapticsClient

    var body: some Reducer<State, Action> {
        BindingReducer()
            .onChange(of: \.route) { _, newValue in
                Reduce { _, _ in
                    newValue == nil
                    ? .merge(
                        .send(.clearSubStates),
                        .send(.fetchDatabaseInfos)
                    )
                    : .none
                }
            }

        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .setNavigation(let route):
                state.route = route
                return route == nil
                ? .merge(
                    .send(.clearSubStates),
                    .send(.fetchDatabaseInfos)
                )
                : .none

            case .setKeyword(let keyword):
                state.keyword = keyword
                return .none

            case .clearSubStates:
                state.searchState = .init()
                state.detailState.wrappedValue = .init()
                state.filtersState = .init()
                state.quickSearchState = .init()
                return .merge(
                    .send(.search(.teardown)),
                    .send(.quickSearch(.teardown)),
                    .send(.detail(.teardown))
                )

            case .syncHistoryKeywords:
                return .run { [state] _ in
                    await databaseClient.updateHistoryKeywords(state.historyKeywords)
                }

            case .fetchDatabaseInfos:
                return .run { send in
                    let appEnv = await databaseClient.fetchAppEnv()
                    await send(.fetchDatabaseInfosDone(appEnv))
                }

            case .fetchDatabaseInfosDone(let appEnv):
                state.historyKeywords = appEnv.historyKeywords
                state.quickSearchWords = appEnv.quickSearchWords
                return .none

            case .appendHistoryKeyword(let keyword):
                state.appendHistoryKeywords([keyword])
                return .send(.syncHistoryKeywords)

            case .removeHistoryKeyword(let keyword):
                state.removeHistoryKeyword(keyword)
                return .send(.syncHistoryKeywords)

            case .fetchHistoryGalleries:
                return .run { send in
                    let historyGalleries = await databaseClient.fetchHistoryGalleries(fetchLimit: 10)
                    await send(.fetchHistoryGalleriesDone(historyGalleries))
                }

            case .fetchHistoryGalleriesDone(let galleries):
                state.historyGalleries = Array(galleries.prefix(min(galleries.count, 10)))
                return .none

            case .search(.fetchGalleries(let keyword)):
                if let keyword = keyword {
                    state.appendHistoryKeywords([keyword])
                } else {
                    state.appendHistoryKeywords([state.searchState.lastKeyword])
                }
                return .send(.syncHistoryKeywords)

            case .search:
                return .none

            case .filters:
                return .none

            case .quickSearch:
                return .none

            case .detail:
                return .none
            }
        }
        .haptics(
            unwrapping: \.route,
            case: \.quickSearch,
            hapticsClient: hapticsClient
        )
        .haptics(
            unwrapping: \.route,
            case: \.filters,
            hapticsClient: hapticsClient
        )

        Scope(state: \.searchState, action: \.search, child: SearchReducer.init)
        Scope(state: \.filtersState, action: \.filters, child: FiltersReducer.init)
        Scope(state: \.quickSearchState, action: \.quickSearch, child: QuickSearchReducer.init)
        Scope(state: \.detailState.wrappedValue!, action: \.detail, child: DetailReducer.init)
    }
}
