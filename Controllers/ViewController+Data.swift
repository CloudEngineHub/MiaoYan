import Cocoa

// MARK: - Search Parameters
private struct SearchParameters: Sendable {
    let filter: String
    let originalFilter: String
    let projects: [Project]?
    let type: SidebarItemType?
    let sidebarName: String?
}

private struct UpdateContext {
    let isSearch: Bool
    let searchParams: SearchParameters
    let operation: BlockOperation
    let completion: () -> Void
}

// MARK: - Data Management
extension ViewController {

    // MARK: - Search and Filtering
    func updateTable(search: Bool = false, searchText: String? = nil, sidebarItem: SidebarItem? = nil, projects: [Project]? = nil, completion: @escaping @MainActor @Sendable () -> Void = {}) {
        let searchParams = prepareSearchParameters(searchText: searchText, sidebarItem: sidebarItem, projects: projects)
        let timestamp = Date().toMillis()

        self.search.timestamp = timestamp
        searchQueue.cancelAllOperations()

        let operation = createSearchOperation(
            searchParams: searchParams,
            isSearch: search,
            completion: completion
        )

        searchQueue.addOperation(operation)
    }

    private func prepareSearchParameters(searchText: String?, sidebarItem: SidebarItem?, projects: [Project]?) -> SearchParameters {
        var finalSidebarItem = sidebarItem
        var finalProjects = projects
        var sidebarName: String?

        if searchText == nil {
            finalProjects = storageOutlineView.getSidebarProjects()
            finalSidebarItem = getSidebarItem()
            sidebarName = getSidebarItem()?.getName()
        }

        let filter = searchText ?? self.search.stringValue
        let originalFilter = filter
        let lowercaseFilter = originalFilter.lowercased()

        var type = finalSidebarItem?.type

        // Global search if sidebar not checked
        if type == nil, finalProjects == nil || (finalProjects!.count < 2 && finalProjects!.first!.isRoot) {
            type = .All
        }

        return SearchParameters(
            filter: lowercaseFilter,
            originalFilter: originalFilter,
            projects: finalProjects,
            type: type,
            sidebarName: sidebarName
        )
    }

    private func createSearchOperation(searchParams: SearchParameters, isSearch: Bool, completion: @escaping @MainActor @Sendable () -> Void) -> BlockOperation {
        let operation = BlockOperation()
        operation.addExecutionBlock { [weak self] in
            guard let self = self else {
                Task { @MainActor in
                    completion()
                }
                return
            }

            Task { @MainActor [weak self] in
                guard let self else {
                    completion()
                    return
                }

                guard !operation.isCancelled else {
                    completion()
                    return
                }

                self.executeSearchOperation(
                    searchParams: searchParams,
                    isSearch: isSearch,
                    operation: operation,
                    completion: completion
                )
            }
        }
        return operation
    }

    private func executeSearchOperation(searchParams: SearchParameters, isSearch: Bool, operation: BlockOperation, completion: @escaping () -> Void) {
        if let projects = searchParams.projects {
            for project in projects {
                preLoadNoteTitles(in: project)
            }
        }

        let notes = filterNotes(
            searchParams: searchParams,
            isSearch: isSearch,
            operation: operation,
            completion: completion
        )

        guard !operation.isCancelled else {
            completion()
            return
        }

        let orderedNotesList = storage.sortNotes(
            noteList: notes,
            filter: searchParams.filter,
            project: searchParams.projects?.first,
            operation: operation
        )

        updateTableViewWithResults(
            notes: notes,
            orderedNotesList: orderedNotesList,
            context: UpdateContext(
                isSearch: isSearch,
                searchParams: searchParams,
                operation: operation,
                completion: completion
            )
        )
    }

    private func filterNotes(searchParams: SearchParameters, isSearch: Bool, operation: BlockOperation, completion: @escaping () -> Void) -> [Note] {
        let terms = searchParams.filter.split(separator: " ")
        let source = storage.noteList
        var notes = [Note]()
        let maxResults = isSearch ? 100 : Int.max

        for note in source {
            if operation.isCancelled {
                completion()
                return []
            }

            if isFit(
                note: note,
                filter: searchParams.filter,
                terms: terms,
                projects: searchParams.projects,
                type: searchParams.type,
                sidebarName: searchParams.sidebarName
            ) {
                notes.append(note)

                if isSearch && notes.count >= maxResults {
                    break
                }
            }
        }

        return notes
    }

    private func updateTableViewWithResults(notes: [Note], orderedNotesList: [Note], context: UpdateContext) {
        // Check if results have changed
        if filteredNoteList == notes, orderedNotesList == notesTableView.noteList {
            context.completion()
            return
        }

        filteredNoteList = notes
        notesTableView.noteList = orderedNotesList

        guard !context.operation.isCancelled else {
            context.completion()
            return
        }

        if notesTableView.noteList.isEmpty {
            handleEmptyResults(completion: context.completion)
        } else {
            handleNonEmptyResults(isSearch: context.isSearch, searchParams: context.searchParams, completion: context.completion)
        }
    }

    private func handleEmptyResults(completion: @escaping () -> Void) {
        DispatchQueue.main.async {
            if !UserDefaultsManagement.isSingleMode {
                self.editArea.clear()
            }
            self.notesTableView.reloadData()
            self.refreshMiaoYanNum()
            completion()
        }
    }

    private func handleNonEmptyResults(isSearch: Bool, searchParams: SearchParameters, completion: @escaping () -> Void) {
        _ = notesTableView.noteList[0]

        DispatchQueue.main.async {
            // Save currently selected row for restoration after table reload
            let previousSelectedRow = self.notesTableView.selectedRow

            self.notesTableView.reloadData()

            if isSearch {
                self.handleSearchResults(searchParams: searchParams)
            }

            self.restoreSelectionIfNeeded(previousSelectedRow: previousSelectedRow)
            // First-run fallback: auto-select first note only during initial app launch
            // Prevents unwanted auto-selection during normal sidebar/list navigation
            if !isSearch,
                !UserDefaultsManagement.isSingleMode,
                self.storageOutlineView.isLaunch,
                self.notesTableView.selectedRow == -1,
                !self.notesTableView.noteList.isEmpty
            {
                self.selectNullTableRow(timer: true)
            }
            completion()
        }
    }

    private func handleSearchResults(searchParams: SearchParameters) {
        let hasSelectedNote = notesTableView.getSelectedNote() != nil

        if !notesTableView.noteList.isEmpty {
            if !searchParams.filter.isEmpty {
                selectNullTableRow(timer: true)
            } else if !UserDefaultsManagement.isSingleMode, !hasSelectedNote {
                editArea.clear()
            }
        } else if !UserDefaultsManagement.isSingleMode, !hasSelectedNote {
            editArea.clear()
        }

        refreshMiaoYanNum()
    }

    private func restoreSelectionIfNeeded(previousSelectedRow: Int) {
        if previousSelectedRow != -1,
            notesTableView.noteList.indices.contains(previousSelectedRow)
        {
            notesTableView.selectRow(previousSelectedRow)
        }
    }

    private func preLoadNoteTitles(in project: Project) {
        if UserDefaultsManagement.sort == .title || project.sortBy == .title {
            _ = storage.noteList.filter {
                $0.project == project
            }
        }
    }

    private func isMatched(note: Note, terms: [Substring]) -> Bool {
        for term in terms {
            if note.name.range(of: term, options: .caseInsensitive, range: nil, locale: nil) != nil {
                continue
            }

            if note.content.string.range(of: term, options: .caseInsensitive, range: nil, locale: nil) != nil {
                continue
            }

            return false
        }

        return true
    }

    public func isFit(note: Note, filter: String = "", terms: [Substring]? = nil, shouldLoadMain: Bool = false, projects: [Project]? = nil, type: SidebarItemType? = nil, sidebarName: String? = nil) -> Bool {
        var filter = filter
        var terms = terms
        var projects = projects

        if shouldLoadMain {
            projects = storageOutlineView.getSidebarProjects()

            filter = search.stringValue
            terms = search.stringValue.split(separator: " ")
        }

        return !note.name.isEmpty
            && (filter.isEmpty || isMatched(note: note, terms: terms!))
            && (type == .All && note.project.showInCommon
                || (type != .All && projects!.contains(note.project)
                    || (note.project.parent != nil && projects!.contains(note.project.parent!)))
                || type == .Trash)
            && (type == .Trash && note.isTrash()
                || type != .Trash && !note.isTrash())
    }

    func cleanSearchAndRestoreSelection() {
        UserDataService.instance.searchTrigger = false

        updateTable(search: false) {
            DispatchQueue.main.async {
                if let currentNote = EditTextView.note,
                    let index = self.notesTableView.noteList.firstIndex(of: currentNote)
                {
                    self.notesTableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                    self.notesTableView.scrollRowToVisible(index)
                    // Ensure title bar is visible when we have a selected note (unless in PPT mode)
                    if !UserDefaultsManagement.magicPPT {
                        self.titleBarView.isHidden = false
                    }
                    self.emptyEditAreaView.isHidden = true
                }
            }
        }
    }

    // MARK: - Data Sorting and Arrangement
    func reSortByDirection() {
        guard let vc = ViewController.shared() else { return }
        ascendingCheckItem.state = UserDefaultsManagement.sortDirection ? .off : .on
        descendingCheckItem.state = UserDefaultsManagement.sortDirection ? .on : .off

        // Sort all notes
        storage.noteList = storage.sortNotes(noteList: storage.noteList, filter: vc.search.stringValue)

        // Sort notes in the current project
        if let filtered = vc.filteredNoteList {
            vc.notesTableView.noteList = storage.sortNotes(noteList: filtered, filter: vc.search.stringValue)
        } else {
            vc.notesTableView.noteList = storage.noteList
        }

        // Remember current selection to avoid unwanted auto-selection after sort
        let currentSelectedRow = vc.notesTableView.selectedRow

        vc.updateTable()
        // Fix post-sort selection: only auto-select first row if nothing was previously selected
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            let selectedRow = vc.notesTableView.selectedRowIndexes.min()
            if selectedRow == nil && currentSelectedRow == -1 {
                vc.notesTableView.selectRowIndexes([0], byExtendingSelection: true)
            }
        }
    }

    public func reSort(note: Note) {
        if !updateViews.contains(note) {
            updateViews.append(note)
        }

        rowUpdaterTimer.invalidate()
        rowUpdaterTimer = Timer.scheduledTimer(timeInterval: 1.2, target: self, selector: #selector(updateTableViews), userInfo: nil, repeats: false)
    }

    public func sortAndMove(note: Note) {
        guard let notes = filteredNoteList else { return }
        guard let srcIndex = notesTableView.noteList.firstIndex(of: note) else { return }

        let resorted = storage.sortNotes(noteList: notes, filter: search.stringValue)
        guard let dstIndex = resorted.firstIndex(of: note) else { return }

        if srcIndex != dstIndex {
            notesTableView.moveRow(at: srcIndex, to: dstIndex)
            notesTableView.noteList = resorted
            filteredNoteList = resorted
        }
    }

    func moveNoteToTop(note index: Int) {
        let isPinned = notesTableView.noteList[index].isPinned
        let position = isPinned ? 0 : notesTableView.countVisiblePinned()
        let note = notesTableView.noteList.remove(at: index)

        notesTableView.noteList.insert(note, at: position)

        notesTableView.reloadRow(note: note)
        notesTableView.moveRow(at: index, to: position)
        notesTableView.scrollRowToVisible(0)
    }

    @objc private func updateTableViews() {
        notesTableView.beginUpdates()
        for note in updateViews {
            notesTableView.reloadRow(note: note)

            if search.stringValue.isEmpty {
                if UserDefaultsManagement.sort == .modificationDate, UserDefaultsManagement.sortDirection == true {
                    if let index = notesTableView.noteList.firstIndex(of: note) {
                        moveNoteToTop(note: index)
                    }
                } else {
                    sortAndMove(note: note)
                }
            }
        }

        updateViews.removeAll()
        notesTableView.endUpdates()
    }

    // MARK: - Selection Management
    @objc func selectNullTableRow(timer: Bool = false) {
        if timer {
            selectRowTimer.invalidate()
            selectRowTimer = Timer.scheduledTimer(timeInterval: TimeInterval(0.2), target: self, selector: #selector(selectRowInstant), userInfo: nil, repeats: false)
            return
        }

        selectRowInstant()
    }

    @objc private func selectRowInstant() {
        // Only auto-select first row when no row is currently selected
        guard notesTableView.selectedRow == -1 else {
            return
        }

        notesTableView.selectRowIndexes([0], byExtendingSelection: false)
        notesTableView.scrollRowToVisible(0)

        if !notesTableView.noteList.isEmpty {
            let note = notesTableView.noteList[0]
            // Avoid filling during note creation to prevent content flashing
            if !UserDataService.instance.shouldBlockEditAreaUpdate() {
                editArea.fill(note: note, options: .forced)
            }
        }
    }

    // MARK: - Data State Management
    func refreshMiaoYanNum() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            let messageText = I18n.str("%d MiaoYan")

            let count: Int
            if let sidebarItem = self.getSidebarItem() {
                if sidebarItem.type == .All {
                    count = self.storage.noteList.filter { !$0.isTrash() }.count
                } else {
                    count = self.notesTableView.noteList.count
                }
            } else {
                count = self.notesTableView.noteList.count
            }

            self.miaoYanText.stringValue = String(format: messageText, count)
        }
    }

    public func blockFSUpdates() {
        timer.invalidate()
        timer = Timer.scheduledTimer(timeInterval: 0.2, target: self, selector: #selector(enableFSUpdates), userInfo: nil, repeats: false)

        UserDataService.instance.fsUpdatesDisabled = true
    }

    @objc func enableFSUpdates() {
        UserDataService.instance.fsUpdatesDisabled = false
    }

    // MARK: - CloudKit Data Sync
    #if CLOUDKIT
        func registerKeyValueObserver() {
            let keyStore = NSUbiquitousKeyValueStore()

            NotificationCenter.default.addObserver(self, selector: #selector(ViewController.ubiquitousKeyValueStoreDidChange), name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: keyStore)

            keyStore.synchronize()
        }

        @objc func ubiquitousKeyValueStoreDidChange(notification: NSNotification) {
            if let keys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] {
                for key in keys where key == "com.tw93.miaoyan.pins.shared" {
                    let changedNotes = storage.restoreCloudPins()

                    if let notes = changedNotes.added {
                        for note in notes {
                            if let i = notesTableView.getIndex(note) {
                                moveNoteToTop(note: i)
                            }
                        }
                    }

                    if let notes = changedNotes.removed {
                        for note in notes {
                            if let i = notesTableView.getIndex(note) {
                                notesTableView.reloadData(forRowIndexes: [i], columnIndexes: [0])
                            }
                        }
                    }
                }
            }
        }
    #endif

    // MARK: - Utility Methods
    public func contains(tag name: String, in tags: [String]) -> Bool {
        var found = false
        for tag in tags {
            if name == tag || name.starts(with: tag + "/") {
                found = true
                break
            }
        }
        return found
    }

    // MARK: - Sidebar Accessors
    func getSidebarProject() -> Project? {
        if storageOutlineView.selectedRow < 0 {
            return nil
        }

        let sidebarItem = storageOutlineView.item(atRow: storageOutlineView.selectedRow) as? SidebarItem

        if let project = sidebarItem?.project {
            return project
        }

        return nil
    }

    func getSidebarType() -> SidebarItemType? {
        let sidebarItem = storageOutlineView.item(atRow: storageOutlineView.selectedRow) as? SidebarItem

        if let type = sidebarItem?.type {
            return type
        }
        return nil
    }

    func getSidebarItem() -> SidebarItem? {
        if let sidebarItem = storageOutlineView.item(atRow: storageOutlineView.selectedRow) as? SidebarItem {
            return sidebarItem
        }

        return nil
    }

    // MARK: - Search and Input Management
    func focusSearchInput(firstResponder: NSResponder? = nil) {
        DispatchQueue.main.async {
            let index = self.notesTableView.selectedRow > -1 ? self.notesTableView.selectedRow : 0
            self.notesTableView.window?.makeFirstResponder(self.notesTableView)
            self.notesTableView.selectRowIndexes([index], byExtendingSelection: true)
            self.notesTableView.scrollRowToVisible(index)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.search.becomeFirstResponder()
        }
    }

    func cleanSearchAndEditArea() {
        search.stringValue = ""
        search.becomeFirstResponder()

        // Keep the current selection when single mode is enabled
        if !UserDefaultsManagement.isSingleMode {
            notesTableView.selectRowIndexes(IndexSet(), byExtendingSelection: false)
            editArea.clear()
        }
    }
}
