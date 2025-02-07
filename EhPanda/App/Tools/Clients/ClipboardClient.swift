//
//  ClipboardClient.swift
//  EhPanda
//
//  Created by 荒木辰造 on R 4/01/19.
//

import SwiftUI
import ComposableArchitecture
import UniformTypeIdentifiers

struct ClipboardClient {
    let url: () -> URL?
    let changeCount: () -> Int
    let saveText: (String) -> Void
    let saveImage: (UIImage, Bool) -> Void
}

extension ClipboardClient {
    static let live: Self = .init(
        url: {
            if UIPasteboard.general.hasURLs {
                return UIPasteboard.general.url
            } else {
                return URL(string: UIPasteboard.general.string ?? "")
            }
        },
        changeCount: {
            UIPasteboard.general.changeCount
        },
        saveText: { text in
            UIPasteboard.general.string = text
        },
        saveImage: { (image, isAnimated) in
            if isAnimated {
                DispatchQueue.global(qos: .utility).async {
                    if let data = image.kf.data(format: .GIF) {
                        UIPasteboard.general.setData(data, forPasteboardType: UTType.gif.identifier)
                    }
                }
            } else {
                UIPasteboard.general.image = image
            }
        }
    )
}

// MARK: API
enum ClipboardClientKey: DependencyKey {
    static let liveValue = ClipboardClient.live
    static let previewValue = ClipboardClient.noop
    static let testValue = ClipboardClient.unimplemented
}

extension DependencyValues {
    var clipboardClient: ClipboardClient {
        get { self[ClipboardClientKey.self] }
        set { self[ClipboardClientKey.self] = newValue }
    }
}

// MARK: Test
extension ClipboardClient {
    static let noop: Self = .init(
        url: { nil },
        changeCount: { 0 },
        saveText: { _ in },
        saveImage: { _, _ in }
    )

    static func placeholder<Result>() -> Result { fatalError() }

    static let unimplemented: Self = .init(
        url: IssueReporting.unimplemented(placeholder: placeholder()),
        changeCount: IssueReporting.unimplemented(placeholder: placeholder()),
        saveText: IssueReporting.unimplemented(placeholder: placeholder()),
        saveImage: IssueReporting.unimplemented(placeholder: placeholder())
    )
}
