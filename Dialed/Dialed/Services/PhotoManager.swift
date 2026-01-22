//
//  PhotoManager.swift
//  Dialed
//
//  Manages workout photo storage and retrieval
//

import Foundation
import UIKit
import SwiftUI

class PhotoManager {
    static let shared = PhotoManager()

    private let fileManager = FileManager.default
    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private init() {}

    // MARK: - Save Photo

    /// Save UIImage to documents directory with compression
    func savePhoto(_ image: UIImage, compressionQuality: CGFloat = 0.7) -> String? {
        // Generate unique filename
        let filename = "workout_photo_\(UUID().uuidString).jpg"
        let fileURL = documentsDirectory.appendingPathComponent(filename)

        // Compress image
        guard let imageData = image.jpegData(compressionQuality: compressionQuality) else {
            print("Failed to compress image")
            return nil
        }

        // Write to file
        do {
            try imageData.write(to: fileURL)
            print("Photo saved: \(filename)")
            return filename
        } catch {
            print("Error saving photo: \(error)")
            return nil
        }
    }

    // MARK: - Load Photo

    /// Load UIImage from documents directory
    func loadPhoto(filename: String) -> UIImage? {
        let fileURL = documentsDirectory.appendingPathComponent(filename)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            print("Photo file not found: \(filename)")
            return nil
        }

        guard let imageData = try? Data(contentsOf: fileURL),
              let image = UIImage(data: imageData) else {
            print("Failed to load photo: \(filename)")
            return nil
        }

        return image
    }

    // MARK: - Delete Photo

    /// Delete photo file from documents directory
    func deletePhoto(filename: String) -> Bool {
        let fileURL = documentsDirectory.appendingPathComponent(filename)

        do {
            try fileManager.removeItem(at: fileURL)
            print("Photo deleted: \(filename)")
            return true
        } catch {
            print("Error deleting photo: \(error)")
            return false
        }
    }

    // MARK: - Get All Photos

    /// Get list of all workout photo filenames
    func getAllPhotoFilenames() -> [String] {
        do {
            let files = try fileManager.contentsOfDirectory(atPath: documentsDirectory.path)
            return files.filter { $0.hasPrefix("workout_photo_") && $0.hasSuffix(".jpg") }
        } catch {
            print("Error listing photos: \(error)")
            return []
        }
    }

    // MARK: - Storage Info

    /// Get total size of all photos in bytes
    func getTotalPhotoStorageSize() -> Int64 {
        let filenames = getAllPhotoFilenames()
        var totalSize: Int64 = 0

        for filename in filenames {
            let fileURL = documentsDirectory.appendingPathComponent(filename)
            if let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
               let fileSize = attributes[.size] as? Int64 {
                totalSize += fileSize
            }
        }

        return totalSize
    }

    /// Format bytes to readable string (e.g., "2.5 MB")
    func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
