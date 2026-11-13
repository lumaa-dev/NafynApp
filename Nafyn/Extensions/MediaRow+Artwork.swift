// Made by Lumaa

import Foundation
import Safyn

extension MediaRow {
	/// The largest cover the server offers, for Now Playing and lock-screen artwork.
	var highResCoverURL: URL? {
		self.setCoverSize(UInt16(CoverArtSize.large.rawValue))
	}

	/// An uploaded cover (`hasCustomCover`) always wins over the archive's: the web app's `coverSrc` rule. A track
	/// uploaded without any cover of the archive used to show as a grey square everywhere.
	func setCoverSize(_ size: UInt16) -> URL? {
		if self.hasUploadedCover, let uploaded = CoverArtLoader.shared.uploadedCoverURL(mediaId: self.id) {
			return uploaded
		}
		return self.coverArt?.coverArtURL(size: size)
	}

	/// The track's cover at the size its list rows use.
	var listCoverURL: URL? {
		if self.hasUploadedCover, let uploaded = CoverArtLoader.shared.uploadedCoverURL(mediaId: self.id) {
			return uploaded
		}
		return self.coverArt.flatMap { URL(string: $0) }
	}
}

extension AlbumRow {
	/// One of the album's tracks has an uploaded cover (`coverMediaId`): it wins over the archive's.
	func coverURL(size: UInt16?) -> URL? {
		if let mediaId = self.coverMediaId, let uploaded = CoverArtLoader.shared.uploadedCoverURL(mediaId: mediaId) {
			return uploaded
		}
		guard let coverArt = self.coverArt else { return nil }
		if let size, coverArt.contains("/art/") { return coverArt.coverArtURL(size: size) }
		return URL(string: coverArt)
	}
}

extension String {
	/// A server `coverArt` path (`/api/v1/art/<type>/<id>/<size>`) at another size (250 / 500 / 1000).
	nonisolated func coverArtURL(size: UInt16) -> URL? {
		URL(string: self.replacing(/\d+$/, with: "\(size)"))
	}
}
