//
//  Video.swift
//  StashApp
//
//  Created by Evan Deaubl on 8/6/24.
//

import Foundation
import CoreMedia

public class Video: Identifiable {
    public let id: String
    let url: URL
    let title: String?
    let duration: Int?
    let startTime: CMTimeValue = 0
    let yearOfRelease = 2023
    let imageName = "foo"
    let synopsis = "foo"
    let contentRating = "foo"
    let genres: [Genre] = [Genre()]
    
    public init(id: String, url: URL, title: String? = nil, duration: Int? = nil) {
        self.id = id
        self.url = url
        self.title = title
        self.duration = duration
    }
}

public class Genre {
    let name = "foo"
}

public extension Video {
    var formattedDuration: String {
        Duration.seconds(duration ?? 0)
            .formatted(.time(pattern: .minuteSecond(padMinuteToLength: 2)))
    }
    
    var formattedYearOfRelease: String {
        yearOfRelease
            .formatted(.number.grouping(.never))
    }
    
    var landscapeImageName: String {
        "\(imageName)_landscape"
    }
    
    var portraitImageName: String {
        "\(imageName)_portrait"
    }
    
    var localizedName: String {
        String(localized: LocalizedStringResource(stringLiteral: self.title ?? ""))
    }
    
    var localizedSynopsis: String {
        String(localized: LocalizedStringResource(stringLiteral: self.synopsis))
    }
    
    var localizedContentRating: String {
        String(localized: LocalizedStringResource(stringLiteral: self.contentRating))
    }
    
    /// A url that resolves to specific local or remote media.
    var resolvedURL: URL {
        if url.isFileURL {
            guard let fileURL = Bundle.main
                .url(forResource: url.host(), withExtension: nil) else {
                fatalError("Attempted to load a nonexistent video: \(String(describing: url.host()))")
            }
            return fileURL
        } else {
            return url
        }
    }
    
    /// A Boolean value that indicates whether the video is hosted in a remote location.
    var hasRemoteMedia: Bool {
        !url.isFileURL
    }
    
    var imageData: Data {
        PlatformImage(named: landscapeImageName)?.imageData ?? Data()
    }
    
    /*func toggleUpNext(in context: ModelContext) {
        if let upNextItem {
            context.delete(upNextItem)
            self.upNextItem = nil
        } else {
            let item = UpNextItem(video: self)
            context.insert(item)
            self.upNextItem = item
        }
    }*/
}
