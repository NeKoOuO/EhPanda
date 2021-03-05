//
//  Store.swift
//  EhPanda
//
//  Created by 荒木辰造 on R 2/12/26.
//

import SwiftUI
import Combine

class Store: ObservableObject {
    @Published var appState = AppState()
    
    func dispatch(_ action: AppAction) {
        print("[ACTION]: \(action)")
        let result = reduce(state: appState, action: action)
        appState = result.0
        
        guard let command = result.1 else { return }
        print("[COMMAND]: \(command)")
        command.execute(in: self)
    }
    
    func reduce(state: AppState, action: AppAction) -> (AppState, AppCommand?) {
        var appState = state
        var appCommand: AppCommand?
        
        switch action {
        // MARK: アプリ関数操作
        case .replaceUser(let user):
            appState.settings.user = user
        case .clearCachedList:
            appState.cachedList.items = nil
        case .clearHistoryItems:
            appState.homeInfo.historyItems = nil
        case .initiateUser:
            appState.settings.user = User()
        case .initiateFilter:
            appState.settings.filter = Filter()
        case .initiateSetting:
            appState.settings.setting = Setting()
        case .saveReadingProgress(let id, let tag):
            appState.cachedList.insertReadingProgress(id: id, progress: tag)
        case .updateDiskImageCacheSize(let size):
            appState.settings.setting?.diskImageCacheSize = size
        case .updateAppIconType(let iconType):
            appState.settings.setting?.appIconType = iconType
        case .updateHistoryItems(let id):
            let item = appState.cachedList.items?[id]
            appState.homeInfo.insertHistoryItem(manga: item)
        case .resetDownloadCommandResponse:
            appState.detailInfo.downloadCommandResponse = nil
            appState.detailInfo.downloadCommandSending = false
            appState.detailInfo.downloadCommandFailed = false
        case .replaceMangaCommentJumpID(let id):
            appState.environment.mangaItemReverseID = id
        case .updateIsSlideMenuClosed(let isClosed):
            appState.environment.isSlideMenuClosed = isClosed
            
        // MARK: アプリ環境
        case .toggleAppUnlocked(let isUnlocked):
            appState.environment.isAppUnlocked = isUnlocked
        case .toggleBlurEffect(let on):
            withAnimation(.linear(duration: 0.1)) {
                appState.environment.blurRadius = on ? 10 : 0
            }
        case .toggleHomeListType(let type):
            appState.environment.homeListType = type
        case .toggleFavoriteIndex(let index):
            appState.environment.favoritesIndex = index
        case .toggleNavBarHidden(let isHidden):
            appState.environment.navBarHidden = isHidden
        case .toggleHomeViewSheetState(let state):
            impactFeedback(style: .light)
            appState.environment.homeViewSheetState = state
        case .toggleHomeViewSheetNil:
            appState.environment.homeViewSheetState = nil
        case .toggleSettingViewSheetState(let state):
            impactFeedback(style: .light)
            appState.environment.settingViewSheetState = state
        case .toggleSettingViewSheetNil:
            appState.environment.settingViewSheetState = nil
        case .toggleSettingViewActionSheetState(let state):
            appState.environment.settingViewActionSheetState = state
        case .toggleFilterViewActionSheetState(let state):
            appState.environment.filterViewActionSheetState = state
        case .toggleDetailViewSheetState(let state):
            impactFeedback(style: .light)
            appState.environment.detailViewSheetState = state
        case .toggleDetailViewSheetNil:
            appState.environment.detailViewSheetState = nil
        case .toggleCommentViewSheetState(let state):
            impactFeedback(style: .light)
            appState.environment.commentViewSheetState = state
        case .toggleCommentViewSheetNil:
            appState.environment.commentViewSheetState = nil
            
        case .cleanDetailViewCommentContent:
            appState.detailInfo.commentContent = ""
        case .cleanCommentViewCommentContent:
            appState.commentInfo.commentContent = ""
            
        // MARK: データ取得
        case .fetchUserInfo(let uid):
            if !didLogin && exx { break }
            if appState.settings.userInfoLoading { break }
            appState.settings.userInfoLoading = true
        
            appCommand = FetchUserInfoCommand(uid: uid)
        case .fetchUserInfoDone(let result):
            appState.settings.userInfoLoading = false
            
            switch result {
            case .success(let user):
                appState.settings.updateUser(user)
            case .failure(let error):
                print(error)
            }
            
        case .fetchFavoriteNames:
            if appState.settings.favoriteNamesLoading { break }
            appState.settings.favoriteNamesLoading = true
            
            appCommand = FetchFavoriteNamesCommand()
        case .fetchFavoriteNamesDone(let result):
            appState.settings.favoriteNamesLoading = false
            
            switch result {
            case .success(let names):
                appState.settings.user?.favoriteNames = names
            case .failure(let error):
                print(error)
            }
            
        case .fetchMangaItemReverse(let detailURL):
            if !didLogin || !exx { break }
            appState.environment.mangaItemReverseLoadFailed = false
            
            if appState.environment.mangaItemReverseLoading { break }
            appState.environment.mangaItemReverseLoading = true
            
            appCommand = FetchMangaItemReverseCommand(detailURL: detailURL)
        case .fetchMangaItemReverseDone(let result):
            appState.environment.mangaItemReverseLoading = false
            
            switch result {
            case .success(let manga):
                appState.cachedList.cache(mangas: [manga])
                appState.environment.mangaItemReverseID = manga.id
            case .failure(let error):
                appState.environment.mangaItemReverseLoadFailed = true
                print(error)
            }
            
        case .fetchSearchItems(let keyword):
            if !didLogin && exx { break }
            appState.homeInfo.searchNotFound = false
            appState.homeInfo.searchLoadFailed = false
            
            if appState.homeInfo.searchLoading { break }
            appState.homeInfo.searchCurrentPageNum = 0
            appState.homeInfo.searchLoading = true
            
            let filter = appState.settings.filter ?? Filter()
            appCommand = FetchSearchItemsCommand(keyword: keyword, filter: filter)
        case .fetchSearchItemsDone(let result):
            appState.homeInfo.searchLoading = false
            
            switch result {
            case .success(let mangas):
                appState.homeInfo.searchCurrentPageNum = mangas.0.current
                appState.homeInfo.searchPageNumMaximum = mangas.0.maximum
                
                if mangas.1.isEmpty {
                    appState.homeInfo.searchNotFound = true
                } else {
                    appState.homeInfo.searchItems = mangas.1
                    appState.cachedList.cache(mangas: mangas.1)
                }
            case .failure(let error):
                print(error)
                appState.homeInfo.searchLoadFailed = true
            }
            
        case .fetchMoreSearchItems(let keyword):
            appState.homeInfo.moreSearchLoadFailed = false
            
            let currentNum = appState.homeInfo.searchCurrentPageNum
            let maximumNum = appState.homeInfo.searchPageNumMaximum
            if currentNum + 1 >= maximumNum { break }
            
            if appState.homeInfo.moreSearchLoading { break }
            appState.homeInfo.moreSearchLoading = true
            
            let filter = appState.settings.filter ?? Filter()
            let lastID = appState.homeInfo.searchItems?.last?.id ?? ""
            let pageNum = appState.homeInfo.searchCurrentPageNum + 1
            appCommand = FetchMoreSearchItemsCommand(
                keyword: keyword,
                filter: filter,
                lastID: lastID,
                pageNum: pageNum
            )
        case .fetchMoreSearchItemsDone(let result):
            appState.homeInfo.moreSearchLoading = false
            
            switch result {
            case .success(let mangas):
                appState.homeInfo.searchCurrentPageNum = mangas.1.current
                appState.homeInfo.searchPageNumMaximum = mangas.1.maximum
                
                let prev = appState.homeInfo.searchItems?.count ?? 0
                appState.homeInfo.insertSearchItems(mangas: mangas.2)
                appState.cachedList.cache(mangas: mangas.2)
                
                let curr = appState.homeInfo.searchItems?.count ?? 0
                if prev == curr && curr != 0 {
                    dispatch(.fetchMoreSearchItems(keyword: mangas.0))
                }
            case .failure(let error):
                appState.homeInfo.moreSearchLoadFailed = true
                print(error)
            }
            
        case .fetchFrontpageItems:
            if !didLogin && exx { break }
            appState.homeInfo.frontpageNotFound = false
            appState.homeInfo.frontpageLoadFailed = false
            
            if appState.homeInfo.frontpageLoading { break }
            appState.homeInfo.frontpageCurrentPageNum = 0
            appState.homeInfo.frontpageLoading = true
            appCommand = FetchFrontpageItemsCommand()
        case .fetchFrontpageItemsDone(let result):
            appState.homeInfo.frontpageLoading = false
            
            switch result {
            case .success(let mangas):
                appState.homeInfo.frontpageCurrentPageNum = mangas.0.current
                appState.homeInfo.frontpagePageNumMaximum = mangas.0.maximum
                
                if mangas.1.isEmpty {
                    appState.homeInfo.frontpageNotFound = true
                } else {
                    appState.homeInfo.frontpageItems = mangas.1
                    appState.cachedList.cache(mangas: mangas.1)
                }
            case .failure(let error):
                appState.homeInfo.frontpageLoadFailed = true
                print(error)
            }
            
        case .fetchMoreFrontpageItems:
            appState.homeInfo.moreFrontpageLoadFailed = false
            
            if !didLogin || !exx { break }
            let currentNum = appState.homeInfo.frontpageCurrentPageNum
            let maximumNum = appState.homeInfo.frontpagePageNumMaximum
            if currentNum + 1 >= maximumNum { break }
            
            if appState.homeInfo.moreFrontpageLoading { break }
            appState.homeInfo.moreFrontpageLoading = true
            
            let lastID = appState.homeInfo.frontpageItems?.last?.id ?? ""
            let pageNum = appState.homeInfo.frontpageCurrentPageNum + 1
            appCommand = FetchMoreFrontpageItemsCommand(lastID: lastID, pageNum: pageNum)
        case .fetchMoreFrontpageItemsDone(let result):
            appState.homeInfo.moreFrontpageLoading = false
            
            switch result {
            case .success(let mangas):
                appState.homeInfo.frontpageCurrentPageNum = mangas.0.current
                appState.homeInfo.frontpagePageNumMaximum = mangas.0.maximum
                
                appState.homeInfo.insertFrontpageItems(mangas: mangas.1)
                appState.cachedList.cache(mangas: mangas.1)
            case .failure(let error):
                appState.homeInfo.moreFrontpageLoadFailed = true
                print(error)
            }
            
        case .fetchPopularItems:
            if !didLogin && exx { break }
            appState.homeInfo.popularNotFound = false
            appState.homeInfo.popularLoadFailed = false
            
            if appState.homeInfo.popularLoading { break }
            appState.homeInfo.popularLoading = true
            appCommand = FetchPopularItemsCommand()
        case .fetchPopularItemsDone(let result):
            appState.homeInfo.popularLoading = false
            
            switch result {
            case .success(let mangas):
                if mangas.1.isEmpty {
                    appState.homeInfo.popularNotFound = true
                } else {
                    appState.homeInfo.popularItems = mangas.1
                    appState.cachedList.cache(mangas: mangas.1)
                }
            case .failure(let error):
                print(error)
                appState.homeInfo.popularLoadFailed = true
            }
            
        case .fetchWatchedItems:
            if !didLogin || !exx { break }
            appState.homeInfo.watchedNotFound = false
            appState.homeInfo.watchedLoadFailed = false
            
            if appState.homeInfo.watchedLoading { break }
            appState.homeInfo.watchedCurrentPageNum = 0
            appState.homeInfo.watchedLoading = true
            appCommand = FetchWatchedItemsCommand()
        case .fetchWatchedItemsDone(result: let result):
            appState.homeInfo.watchedLoading = false
            
            switch result {
            case .success(let mangas):
                appState.homeInfo.watchedCurrentPageNum = mangas.0.current
                appState.homeInfo.watchedPageNumMaximum = mangas.0.maximum
                
                if mangas.1.isEmpty {
                    appState.homeInfo.watchedNotFound = true
                } else {
                    appState.homeInfo.watchedItems = mangas.1
                    appState.cachedList.cache(mangas: mangas.1)
                }
            case .failure(let error):
                print(error)
                appState.homeInfo.watchedLoadFailed = true
            }
            
        case .fetchMoreWatchedItems:
            appState.homeInfo.moreWatchedLoadFailed = false
            
            let currentNum = appState.homeInfo.watchedCurrentPageNum
            let maximumNum = appState.homeInfo.watchedPageNumMaximum
            if currentNum + 1 >= maximumNum { break }
            
            if appState.homeInfo.moreWatchedLoading { break }
            appState.homeInfo.moreWatchedLoading = true
            
            let lastID = appState.homeInfo.watchedItems?.last?.id ?? ""
            let pageNum = appState.homeInfo.watchedCurrentPageNum + 1
            appCommand = FetchMoreWatchedItemsCommand(lastID: lastID, pageNum: pageNum)
        case .fetchMoreWatchedItemsDone(let result):
            appState.homeInfo.moreWatchedLoading = false
            
            switch result {
            case .success(let mangas):
                appState.homeInfo.watchedCurrentPageNum = mangas.0.current
                appState.homeInfo.watchedPageNumMaximum = mangas.0.maximum
                
                appState.homeInfo.insertWatchedItems(mangas: mangas.1)
                appState.cachedList.cache(mangas: mangas.1)
            case .failure(let error):
                appState.homeInfo.moreWatchedLoadFailed = true
                print(error)
            }
            
        case .fetchFavoritesItems(let favIndex):
            if !didLogin || !exx { break }
            appState.homeInfo.favoritesNotFound[favIndex] = false
            appState.homeInfo.favoritesLoadFailed[favIndex] = false
            
            if appState.homeInfo.favoritesLoading[favIndex] != false { break }
            appState.homeInfo.favoritesCurrentPageNum[favIndex] = 0
            appState.homeInfo.favoritesLoading[favIndex] = true
            appCommand = FetchFavoritesItemsCommand(favIndex: favIndex)
        case .fetchFavoritesItemsDone(let carriedValue, let result):
            appState.homeInfo.favoritesLoading[carriedValue] = false
            
            switch result {
            case .success(let mangas):
                appState.homeInfo.favoritesCurrentPageNum[carriedValue] = mangas.0.current
                appState.homeInfo.favoritesPageNumMaximum[carriedValue] = mangas.0.maximum
                
                if mangas.1.isEmpty {
                    appState.homeInfo.favoritesNotFound[carriedValue] = true
                } else {
                    appState.homeInfo.favoritesItems[carriedValue] = mangas.1
                    appState.cachedList.cache(mangas: mangas.1)
                }
            case .failure(let error):
                appState.homeInfo.favoritesLoadFailed[carriedValue] = true
                print(error)
            }
            
        case .fetchMoreFavoritesItems(let favIndex):
            appState.homeInfo.moreFavoritesLoadFailed[favIndex] = false
            
            let currentNum = appState.homeInfo.favoritesCurrentPageNum[favIndex]
            let maximumNum = appState.homeInfo.favoritesPageNumMaximum[favIndex]
            if (currentNum ?? 0) + 1 >= maximumNum ?? 1 { break }
            
            if appState.homeInfo.moreFavoritesLoading[favIndex] != false { break }
            appState.homeInfo.moreFavoritesLoading[favIndex] = true
            
            let lastID = appState.homeInfo.favoritesItems[favIndex]?.last?.id ?? ""
            let pageNum = (appState.homeInfo.favoritesCurrentPageNum[favIndex] ?? 0) + 1
            appCommand = FetchMoreFavoritesItemsCommand(
                favIndex: favIndex,
                lastID: lastID,
                pageNum: pageNum
            )
        case .fetchMoreFavoritesItemsDone(let carriedValue, let result):
            appState.homeInfo.moreFavoritesLoading[carriedValue] = false
            
            switch result {
            case .success(let mangas):
                appState.homeInfo.favoritesCurrentPageNum[carriedValue] = mangas.0.current
                appState.homeInfo.favoritesPageNumMaximum[carriedValue] = mangas.0.maximum
                
                appState.homeInfo.insertFavoritesItems(favIndex: carriedValue, mangas: mangas.1)
                appState.cachedList.cache(mangas: mangas.1)
            case .failure(let error):
                appState.homeInfo.moreFavoritesLoading[carriedValue] = true
                print(error)
            }
            
        case .fetchMangaDetail(id: let id):
            appState.detailInfo.mangaDetailLoadFailed = false
            
            if appState.detailInfo.mangaDetailLoading { break }
            appState.detailInfo.mangaDetailLoading = true
            
            let detailURL = appState.cachedList.items?[id]?.detailURL ?? ""
            appCommand = FetchMangaDetailCommand(id: id, detailURL: detailURL)
        case .fetchMangaDetailDone(result: let result):
            appState.detailInfo.mangaDetailLoading = false
            
            switch result {
            case .success(let detail):
                appState.settings.user?.apikey = detail.2
                appState.cachedList.insertDetail(id: detail.0, detail: detail.1)
            case .failure(let error):
                print(error)
                appState.detailInfo.mangaDetailLoadFailed = true
            }
            
        case .fetchMangaArchive(id: let id):
            appState.detailInfo.mangaArchiveLoadFailed = false
            
            if appState.detailInfo.mangaArchiveLoading { break }
            appState.detailInfo.mangaArchiveLoading = true
            
            let archiveURL = appState.cachedList.items?[id]?.detail?.archiveURL ?? ""
            appCommand = FetchMangaArchiveCommand(id: id, archiveURL: archiveURL)
        case .fetchMangaArchiveDone(result: let result):
            appState.detailInfo.mangaArchiveLoading = false
            
            switch result {
            case .success(let archive):
                appState.cachedList.insertArchive(id: archive.0, archive: archive.1)
                
                if let currentGP = archive.2,
                   let currentCredits = archive.3
                {
                    appState.settings.updateUser(
                        User(
                            currentGP: currentGP,
                            currentCredits: currentCredits
                        )
                    )
                }
            case .failure(let error):
                print(error)
                appState.detailInfo.mangaArchiveLoadFailed = true
            }
            
        case .fetchMangaArchiveFunds(id: let id):
            if appState.detailInfo.mangaArchiveFundsLoading { break }
            appState.detailInfo.mangaArchiveFundsLoading = true
            
            let detailURL = (appState.cachedList.items?[id]?.detailURL ?? "")
                .replacingOccurrences(of: Defaults.URL.exhentai, with: Defaults.URL.ehentai)
            appCommand = FetchMangaArchiveFundsCommand(id: id, detailURL: detailURL)
        case .fetchMangaArchiveFundsDone(result: let result):
            appState.detailInfo.mangaArchiveFundsLoading = false
            
            switch result {
            case .success(let funds):
                appState.settings.updateUser(
                    User(
                        currentGP: funds.0,
                        currentCredits: funds.1
                    )
                )
            case .failure(let error):
                print(error)
            }
            
        case .fetchMangaTorrents(id: let id):
            appState.detailInfo.mangaTorrentsLoadFailed = false
            
            if appState.detailInfo.mangaTorrentsLoading { break }
            appState.detailInfo.mangaTorrentsLoading = true
            
            let token = appState.cachedList.items?[id]?.token ?? ""
            appCommand = FetchMangaTorrentsCommand(id: id, token: token)
        case .fetchMangaTorrentsDone(result: let result):
            appState.detailInfo.mangaTorrentsLoading = false
            
            switch result {
            case .success(let torrents):
                appState.cachedList.insertTorrents(id: torrents.0, torrents: torrents.1)
            case .failure(let error):
                print(error)
                appState.detailInfo.mangaTorrentsLoadFailed = true
            }
            
        case .fetchAssociatedItems(let depth, let keyword):
            appState.detailInfo.associatedItemsNotFound = false
            appState.detailInfo.associatedItemsLoadFailed = false
            
            if appState.detailInfo.associatedItemsLoading { break }
            appState.detailInfo.removeAssociatedItems(depth: depth)
            appState.detailInfo.associatedItemsLoading = true
            
            appCommand = FetchAssociatedItemsCommand(depth: depth, keyword: keyword)
        case .fetchAssociatedItemsDone(let result):
            appState.detailInfo.associatedItemsLoading = false
            
            switch result {
            case .success(let mangas):
                if mangas.3.isEmpty {
                    appState.detailInfo.associatedItemsNotFound = true
                } else {
                    appState.detailInfo.replaceAssociatedItems(
                        depth: mangas.0,
                        keyword: mangas.1,
                        pageNum: mangas.2,
                        items: mangas.3
                    )
                    appState.cachedList.cache(mangas: mangas.3)
                }
            case .failure(let error):
                print(error)
                appState.detailInfo.associatedItemsLoadFailed = true
            }
            
        case .fetchMoreAssociatedItems(let depth, let keyword):
            appState.detailInfo.moreAssociatedItemsLoadFailed = false
            
            guard appState.detailInfo.associatedItems.count >= depth + 1 else { break }
            let currentNum = appState.detailInfo.associatedItems[depth].pageNum.current
            let maximumNum = appState.detailInfo.associatedItems[depth].pageNum.maximum
            if currentNum + 1 >= maximumNum { break }
            
            if appState.detailInfo.moreAssociatedItemsLoading { break }
            appState.detailInfo.moreAssociatedItemsLoading = true
            
            let lastID = appState.detailInfo.associatedItems[depth].mangas.last?.id ?? ""
            let pageNum = currentNum + 1
            appCommand = FetchMoreAssociatedItemsCommand(
                depth: depth,
                keyword: keyword,
                lastID: lastID,
                pageNum: pageNum
            )
        case .fetchMoreAssociatedItemsDone(let result):
            appState.detailInfo.moreAssociatedItemsLoading = false
            
            switch result {
            case .success(let mangas):
                appState.detailInfo.insertAssociatedItems(
                    depth: mangas.0,
                    keyword: mangas.1,
                    pageNum: mangas.2,
                    items: mangas.3
                )
                appState.cachedList.cache(mangas: mangas.3)
            case .failure(let error):
                appState.detailInfo.moreAssociatedItemsLoadFailed = true
                print(error)
            }
            
        case .fetchAlterImages(let id, let doc):
            if appState.detailInfo.alterImagesLoading { break }
            appState.detailInfo.alterImagesLoading = true
            
            appCommand = FetchAlterImagesCommand(id: id, doc: doc)
        case .fetchAlterImagesDone(result: let result):
            appState.detailInfo.alterImagesLoading = false
            
            switch result {
            case .success(let images):
                appState.cachedList.insertAlterImages(id: images.0, images: images.1)
            case .failure(let error):
                print(error)
            }
            
        case .updateMangaDetail(id: let id):
            if appState.detailInfo.mangaDetailUpdating { break }
            appState.detailInfo.mangaDetailUpdating = true
            
            let detailURL = appState.cachedList.items?[id]?.detailURL ?? ""
            appCommand = UpdateMangaDetailCommand(id: id, detailURL: detailURL)
        case .updateMangaDetailDone(result: let result):
            appState.detailInfo.mangaDetailUpdating = false
            
            switch result {
            case .success(let detail):
                appState.cachedList.updateDetail(id: detail.0, detail: detail.1)
            case .failure(let error):
                print(error)
            }
            
        case .updateMangaComments(id: let id):
            if appState.detailInfo.mangaCommentsUpdating { break }
            appState.detailInfo.mangaCommentsUpdating = true
            
            let detailURL = appState.cachedList.items?[id]?.detailURL ?? ""
            appCommand = UpdateMangaCommentsCommand(id: id, detailURL: detailURL)
        case .updateMangaCommentsDone(result: let result):
            appState.detailInfo.mangaCommentsUpdating = false
            
            switch result {
            case .success(let comments):
                appState.cachedList.updateComments(id: comments.0, comments: comments.1)
            case .failure(let error):
                print(error)
            }
            
        case .fetchMangaContents(let id):
            appState.contentInfo.mangaContentsLoadFailed = false
            
            if appState.contentInfo.mangaContentsLoading { break }
            appState.contentInfo.mangaContentsLoading = true
            
            appState.cachedList.items?[id]?.detail?.currentPageNum = 0
            
            let detailURL = appState.cachedList.items?[id]?.detailURL ?? ""
            appCommand = FetchMangaContentsCommand(id: id, detailURL: detailURL)
        case .fetchMangaContentsDone(result: let result):
            appState.contentInfo.mangaContentsLoading = false
            
            switch result {
            case .success(let contents):
                appState.cachedList.insertContents(
                    id: contents.0,
                    pageNum: contents.1,
                    contents: contents.2
                )
            case .failure(let error):
                appState.contentInfo.mangaContentsLoadFailed = true
                print(error)
            }
            
        case .fetchMoreMangaContents(let id):
            appState.contentInfo.moreMangaContentsLoadFailed = false
            
            guard let manga = appState.cachedList.items?[id],
                  let detail = manga.detail
            else { break }
            
            let currentNum = detail.currentPageNum
            let maximumNum = detail.pageNumMaximum
            if currentNum + 1 >= maximumNum { break }
            
            if appState.contentInfo.moreMangaContentsLoading { break }
            appState.contentInfo.moreMangaContentsLoading = true
            
            let detailURL = manga.detailURL
            let pageNum = currentNum + 1
            let pageCount = manga.contents?.count ?? 0
            appCommand = FetchMoreMangaContentsCommand(
                id: id,
                detailURL: detailURL,
                pageNum: pageNum,
                pageCount: pageCount
            )
        case .fetchMoreMangaContentsDone(result: let result):
            appState.contentInfo.moreMangaContentsLoading = false
            
            switch result {
            case .success(let contents):
                appState.cachedList.insertContents(
                    id: contents.0,
                    pageNum: contents.1,
                    contents: contents.2
                )
            case .failure(let error):
                appState.contentInfo.moreMangaContentsLoadFailed = true
                print(error)
            }
            
        // MARK: アカウント活動
        case .addFavorite(let id, let favIndex):
            let token = appState.cachedList.items?[id]?.token ?? ""
            appCommand = AddFavoriteCommand(id: id, token: token, favIndex: favIndex)
        case .deleteFavorite(let id):
            appCommand = DeleteFavoriteCommand(id: id)
            
        case .sendDownloadCommand(let id, let resolution):
            appState.detailInfo.downloadCommandFailed = false
            
            if appState.detailInfo.downloadCommandSending { break }
            appState.detailInfo.downloadCommandSending = true
            
            let archiveURL = appState.cachedList.items?[id]?.detail?.archiveURL ?? ""
            appCommand = SendDownloadCommand(id: id, archiveURL: archiveURL, resolution: resolution)
        case .sendDownloadCommandDone(let result):
            appState.detailInfo.downloadCommandSending = false
            
            switch result {
            case .success(let resp):
                if resp == Defaults.Response.hathClientNotFound ||
                    resp == Defaults.Response.hathClientNotOnline
                {
                    appState.detailInfo.downloadCommandFailed = true
                }
                appState.detailInfo.downloadCommandResponse = resp
            case .failure(let error):
                appState.detailInfo.downloadCommandFailed = true
                print(error)
            }
            
        case .rate(let id, let rating):
            guard let apiuidString = appState.settings.user?.apiuid,
                  let apikey = appState.settings.user?.apikey,
                  let token = appState.cachedList.items?[id]?.token,
                  let apiuid = Int(apiuidString),
                  let id = Int(id)
            else { break }
            
            appCommand = RateCommand(
                apiuid: apiuid,
                apikey: apikey,
                gid: id,
                token: token,
                rating: rating
            )
            
        case .comment(let id, let content):
            let detailURL = appState.cachedList.items?[id]?.detailURL ?? ""
            appCommand = CommentCommand(id: id, content: content, detailURL: detailURL)
        case .editComment(let id, let commentID, let content):
            let detailURL = appState.cachedList.items?[id]?.detailURL ?? ""
            
            appCommand = EditCommentCommand(
                id: id,
                commentID: commentID,
                content: content,
                detailURL: detailURL
            )
        case .voteComment(let id, let commentID, let vote):
            guard let apiuidString = appState.settings.user?.apiuid,
                  let apikey = appState.settings.user?.apikey,
                  let token = appState.cachedList.items?[id]?.token,
                  let commentID = Int(commentID),
                  let apiuid = Int(apiuidString),
                  let id = Int(id)
            else { break }
            
            appCommand = VoteCommentCommand(
                apiuid: apiuid,
                apikey: apikey,
                gid: id,
                token: token,
                commentID: commentID,
                commentVote: vote
            )
        }
        
        return (appState, appCommand)
    }
}
