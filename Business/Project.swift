import Foundation

public class Project: Equatable {
    var url: URL
    var isTrash: Bool
    var isCloudDrive: Bool = false
    var isRoot: Bool
    var parent: Project?
    var isDefault: Bool

    public var label: String
    public var isExternal: Bool = false

    // Use default values at declaration; loadSettings() will override if needed
    public var sortBy: SortBy = .none
    public var sortDirection: SortDirection = .asc

    public var sortBySettings: SortBy = .none
    public var sortDirectionSettings: SortDirection = .desc

    public var showInCommon: Bool
    public var showInSidebar: Bool = true

    init(url: URL,
         label: String? = nil,
         isTrash: Bool = false,
         isRoot: Bool = false,
         parent: Project? = nil,
         isDefault: Bool = false,
         isExternal: Bool = false)
    {
        self.url = url.resolvingSymlinksInPath()
        self.isTrash = isTrash
        self.isRoot = isRoot
        self.parent = parent
        self.isDefault = isDefault
        self.isExternal = isExternal

        showInCommon = !isTrash

        // Initialize label first
        self.label = label ?? url.lastPathComponent

        // Load localized name if available
        var localizedName: AnyObject?
        try? (url as NSURL).getResourceValue(&localizedName, forKey: URLResourceKey.localizedNameKey)
        if let name = localizedName as? String, !name.isEmpty {
            self.label = name
        }

        isCloudDrive = isCloudDriveFolder(url: url)
        loadSettings() // Override defaults from cloud/local settings if available
    }

    func fileExist(fileName: String, ext: String) -> Bool {
        let fileURL = url.appendingPathComponent(fileName + "." + ext)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    public static func == (lhs: Project, rhs: Project) -> Bool {
        lhs.url == rhs.url
    }

    public func loadLabel(_ label: String? = nil) {
        self.label = label ?? url.lastPathComponent

        // Override with localized name if available
        var localizedName: AnyObject?
        try? (url as NSURL).getResourceValue(&localizedName, forKey: URLResourceKey.localizedNameKey)
        if let name = localizedName as? String, !name.isEmpty {
            self.label = name
        }
    }

    private func isCloudDriveFolder(url: URL) -> Bool {
        if let iCloudDocumentsURL = FileManager.default
            .url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents")
            .resolvingSymlinksInPath()
        {
            if FileManager.default.fileExists(atPath: iCloudDocumentsURL.path, isDirectory: nil),
               url.path.contains(iCloudDocumentsURL.path)
            {
                return true
            }
        }
        return false
    }

    public func getParent() -> Project {
        if isRoot { return self }
        if let parent = parent { return parent.getParent() }
        return self
    }

    public func saveSettings() {
        let data: [String: Any] = [
            "sortBy": sortBySettings.rawValue,
            "sortDirection": sortDirectionSettings.rawValue,
            "showInCommon": showInCommon,
            "showInSidebar": showInSidebar,
        ]

        if let relativePath = getRelativePath() {
            let keyStore = NSUbiquitousKeyValueStore()
            let key = relativePath.isEmpty ? "root-directory" : relativePath
            keyStore.set(data, forKey: key)
            keyStore.synchronize()
            return
        }

        UserDefaults.standard.set(data, forKey: url.path)
    }

    public func loadSettings() {
        if let relativePath = getRelativePath() {
            let keyStore = NSUbiquitousKeyValueStore()
            let key = relativePath.isEmpty ? "root-directory" : relativePath

            if let settings = keyStore.dictionary(forKey: key) {
                if let common = settings["showInCommon"] as? Bool {
                    showInCommon = common
                }

                if let sidebar = settings["showInSidebar"] as? Bool {
                    showInSidebar = sidebar
                }

                if let sortString = settings["sortBy"] as? String,
                   let sort = SortBy(rawValue: sortString)
                {
                    if sort != .none {
                        sortBy = sort
                        sortBySettings = sort

                        if let directionString = settings["sortDirection"] as? String,
                           let direction = SortDirection(rawValue: directionString)
                        {
                            sortDirection = direction
                            sortDirectionSettings = direction
                        }
                    }
                }
            }
            return
        }

        if let settings = UserDefaults.standard.object(forKey: url.path) as? NSObject {
            if let common = settings.value(forKey: "showInCommon") as? Bool {
                showInCommon = common
            }

            if let sidebar = settings.value(forKey: "showInSidebar") as? Bool {
                showInSidebar = sidebar
            }

            if let sortString = settings.value(forKey: "sortBy") as? String,
               let sort = SortBy(rawValue: sortString)
            {
                if sort != .none {
                    sortBy = sort
                    sortBySettings = sort

                    if let directionString = settings.value(forKey: "sortDirection") as? String,
                       let direction = SortDirection(rawValue: directionString)
                    {
                        sortDirection = direction
                        sortDirectionSettings = direction
                    }
                }
            }
            return
        }
    }

    public func getRelativePath() -> String? {
        if let iCloudRoot = FileManager.default
            .url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents")
            .resolvingSymlinksInPath()
        {
            return url.path.replacingOccurrences(of: iCloudRoot.path, with: "")
        }
        return nil
    }

    public func createDirectory() {
        do {
            try FileManager.default.createDirectory(
                at: url.appendingPathComponent("i"),
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            Task { @MainActor in
                AppDelegate.trackError(error, context: "Project.createDirectory")
            }
        }
    }

    public func remove() {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Task { @MainActor in
                AppDelegate.trackError(error, context: "Project.remove")
            }
        }
    }

    public func create() {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        } catch {
            Task { @MainActor in
                AppDelegate.trackError(error, context: "Project.create")
            }
        }
    }

    public func getShortSign() -> String {
        String(getParent().url.path.md5.prefix(4))
    }
}

extension Project: @unchecked Sendable {}
