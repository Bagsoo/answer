import UIKit
import Social
import MobileCoreServices
import Photos

class ShareViewController: SLComposeServiceViewController {

    let suiteName = "group.com.answer.app"
    
    override func isContentValid() -> Bool {
        return true
    }

    override func didSelectPost() {
        let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem
        let attachments = extensionItem?.attachments ?? []
        
        var payload: [String: Any] = [:]
        payload["type"] = "mixed"
        payload["receivedAt"] = Int(Date().timeIntervalSince1970 * 1000)
        
        var files: [[String: Any]] = []
        var text: String? = ""
        
        // Subject property for URL sharing (e.g. website title)
        if let attrText = extensionItem?.attributedContentText?.string, !attrText.isEmpty {
            payload["subject"] = attrText
        }
        
        let group = DispatchGroup()
        
        for provider in attachments {
            if provider.hasItemConformingToTypeIdentifier(kUTTypePlainText as String) {
                group.enter()
                provider.loadItem(forTypeIdentifier: kUTTypePlainText as String, options: nil) { (data, error) in
                    if let content = data as? String {
                        text = content
                    }
                    group.leave()
                }
            } else if provider.hasItemConformingToTypeIdentifier(kUTTypeURL as String) {
                group.enter()
                provider.loadItem(forTypeIdentifier: kUTTypeURL as String, options: nil) { (data, error) in
                    if let url = data as? URL {
                        text = url.absoluteString
                    }
                    group.leave()
                }
            } else if provider.hasItemConformingToTypeIdentifier(kUTTypeImage as String) {
                group.enter()
                provider.loadItem(forTypeIdentifier: kUTTypeImage as String, options: nil) { (data, error) in
                    if let url = data as? URL {
                        if let copiedPath = self.copyToContainer(url: url) {
                            let info = self.getFileInfo(from: URL(fileURLWithPath: copiedPath))
                            files.append(["path": copiedPath, "name": info.name, "mimeType": info.mimeType, "size": info.size])
                        }
                    } else if let image = data as? UIImage {
                        if let copiedPath = self.saveImageToContainer(image: image) {
                            let info = self.getFileInfo(from: URL(fileURLWithPath: copiedPath))
                            files.append(["path": copiedPath, "name": info.name, "mimeType": "image/jpeg", "size": info.size])
                        }
                    }
                    group.leave()
                }
            } else if provider.hasItemConformingToTypeIdentifier(kUTTypeMovie as String) {
                group.enter()
                provider.loadItem(forTypeIdentifier: kUTTypeMovie as String, options: nil) { (data, error) in
                    if let url = data as? URL {
                        if let copiedPath = self.copyToContainer(url: url) {
                            let info = self.getFileInfo(from: URL(fileURLWithPath: copiedPath))
                            files.append(["path": copiedPath, "name": info.name, "mimeType": info.mimeType, "size": info.size])
                        }
                    }
                    group.leave()
                }
            } else if provider.hasItemConformingToTypeIdentifier(kUTTypeData as String) {
                group.enter()
                provider.loadItem(forTypeIdentifier: kUTTypeData as String, options: nil) { (data, error) in
                    if let url = data as? URL {
                        if let copiedPath = self.copyToContainer(url: url) {
                            let info = self.getFileInfo(from: URL(fileURLWithPath: copiedPath))
                            files.append(["path": copiedPath, "name": info.name, "mimeType": info.mimeType, "size": info.size])
                        }
                    }
                    group.leave()
                }
            }
        }
        
        group.notify(queue: .main) {
            payload["text"] = text
            payload["files"] = files
            if let subject = payload["subject"] as? String, subject.isEmpty == false {
                // subject already saved
            } else {
                payload["subject"] = self.contentText // the text user typed in compose view
            }
            payload["sourceApp"] = "ShareExtension"
            
            self.savePayload(payload)
            self.redirectToMainApp()
            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }
    
    private func getFileInfo(from url: URL) -> (name: String, mimeType: String, size: Int) {
        let name = url.lastPathComponent
        var size = 0
        if let resources = try? url.resourceValues(forKeys: [.fileSizeKey]), let fileSize = resources.fileSize {
            size = fileSize
        } else {
            // attempt to check file size by attributes
            if let attr = try? FileManager.default.attributesOfItem(atPath: url.path), let fileSize = attr[FileAttributeKey.size] as? UInt64 {
                size = Int(fileSize)
            }
        }
        
        var mimeType = "application/octet-stream"
        if let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, url.pathExtension as CFString, nil)?.takeRetainedValue() {
            if let mimetype = UTTypeCopyPreferredTagWithClass(uti, kUTTagClassMIMEType)?.takeRetainedValue() {
                mimeType = mimetype as String
            }
        }
        
        // basic fallback
        if mimeType == "application/octet-stream" {
            let ext = url.pathExtension.lowercased()
            if ["jpg", "jpeg", "png", "gif", "heic"].contains(ext) { mimeType = "image/\(ext == "jpg" ? "jpeg" : ext)" }
            else if ["mp4", "mov", "avi"].contains(ext) { mimeType = "video/\(ext)" }
            else if ["mp3", "wav", "m4a"].contains(ext) { mimeType = "audio/\(ext)" }
        }
        
        return (name, mimeType, size)
    }

    private func copyToContainer(url: URL) -> String? {
        let containerUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName)
        guard let destUrl = containerUrl?.appendingPathComponent(url.lastPathComponent) else { return nil }
        
        try? FileManager.default.removeItem(at: destUrl)
        do {
            try FileManager.default.copyItem(at: url, to: destUrl)
            return destUrl.path
        } catch {
            return nil
        }
    }
    
    private func saveImageToContainer(image: UIImage) -> String? {
        let containerUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName)
        let fileName = "shared_image_\(Date().timeIntervalSince1970).jpg"
        guard let destUrl = containerUrl?.appendingPathComponent(fileName) else { return nil }
        
        if let data = image.jpegData(compressionQuality: 0.8) {
            do {
                try data.write(to: destUrl)
                return destUrl.path
            } catch {
                return nil
            }
        }
        return nil
    }

    private func savePayload(_ payload: [String: Any]) {
        if let userDefaults = UserDefaults(suiteName: suiteName) {
            userDefaults.set(payload, forKey: "incoming_share_payload")
            userDefaults.synchronize()
        }
    }
    
    private func redirectToMainApp() {
        let url = URL(string: "messenger-share://")!
        var responder: UIResponder? = self
        while responder != nil {
            if let application = responder as? UIApplication {
                application.perform(#selector(openURL(_:)), with: url)
                break
            }
            responder = responder?.next
        }
    }
    
    @objc func openURL(_ url: URL) {
        // This is a selector for the application to open the URL
    }
}
