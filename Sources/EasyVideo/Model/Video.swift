//
//  Video.swift
//  StashApp
//
//  Created by Evan Deaubl on 8/6/24.
//

import Foundation
import CoreMedia

final public class Video: Identifiable, Sendable {
    public let id: String
    let url: URL
    let title: String?
    let duration: Int?
    let startTime: CMTimeValue
    let yearOfRelease: Int?
    let imageName: String?
    let synopsis: String?
    let contentRating: String?
    let genres: [Genre]
    
    public init(id: String, url: URL, title: String? = nil, duration: Int? = nil, startTime: Int64 = 0, yearOfRelease: Int? = nil, imageName: String? = nil, synopsis: String? = nil, contentRating: String? = nil, genres: [Genre] = []) {
        self.id = id
        self.url = url
        self.title = title
        self.duration = duration
        self.startTime = startTime
        self.yearOfRelease = yearOfRelease
        self.imageName = imageName
        self.synopsis = synopsis
        self.contentRating = contentRating
        self.genres = genres
    }
}

final public class Genre: Sendable {
    let name: String
    
    public init(name: String) {
        self.name = name
    }
}

public extension Video {
    var formattedDuration: String {
        Duration.seconds(duration ?? 0)
            .formatted(.time(pattern: .minuteSecond(padMinuteToLength: 2)))
    }
    
    var formattedYearOfRelease: String? {
        yearOfRelease?
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
        String(localized: LocalizedStringResource(stringLiteral: self.synopsis ?? ""))
    }
    
    var localizedContentRating: String {
        String(localized: LocalizedStringResource(stringLiteral: self.contentRating ?? ""))
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
}
