import AppCenter
import AppCenterAnalytics
import Cocoa
import LocalAuthentication
import MASShortcut
import WebKit

class ViewController:
    NSViewController,
    NSTextViewDelegate,
    NSPopoverDelegate,
    NSTextFieldDelegate,
    NSSplitViewDelegate,
    NSOutlineViewDelegate,
    NSOutlineViewDataSource,
    NSMenuItemValidation,
    NSUserNotificationCenterDelegate
{
    public var fsManager: FileSystemEventManager?
    private var projectSettingsViewController: ProjectSettingsViewController?

    let storage = Storage.sharedInstance()
    var filteredNoteList: [Note]?
    var alert: NSAlert?
    var refilled: Bool = false
    var timer = Timer()
    var sidebarTimer = Timer()
    var rowUpdaterTimer = Timer()
    let searchQueue = OperationQueue()
    var isFocusedTitle: Bool = false
    var formatContent: String = ""
    var needRestorePreview: Bool = false

    private var disablePreviewWorkItem: DispatchWorkItem?
    private var isHandlingScrollEvent = false
    private var swipeLeftExecuted = false
    private var swipeRightExecuted = false
    private var scrollDeltaX: CGFloat = 0

    private var updateViews = [Note]()
    public var breakUndoTimer = Timer()

    override var representedObject: Any? {
        didSet {}
    }

    @IBOutlet var emptyEditTitle: NSTextField!
    @IBOutlet var emptyEditAreaImage: NSImageView!
    @IBOutlet var emptyEditAreaView: NSView!
    @IBOutlet var splitView: EditorSplitView!
    @IBOutlet var editArea: EditTextView!
    @IBOutlet var editAreaScroll: EditorScrollView!
    @IBOutlet var search: SearchTextField!

    @IBOutlet var miaoYanText: NSTextField!
    @IBOutlet var notesTableView: NotesTableView!
    @IBOutlet var noteMenu: NSMenu!
    @IBOutlet var storageOutlineView: SidebarProjectView!
    @IBOutlet var sidebarSplitView: NSSplitView!
    @IBOutlet var notesListCustomView: NSView!
    @IBOutlet var outlineHeader: OutlineHeaderView!

    @IBOutlet var titiebarHeight: NSLayoutConstraint!
    @IBOutlet var searchTopConstraint: NSLayoutConstraint!
    @IBOutlet var titleLabel: TitleTextField!
    @IBOutlet var titleTopConstraint: NSLayoutConstraint!

    @IBOutlet var sortByOutlet: NSMenuItem!
    @IBOutlet var titleBarAdditionalView: NSVisualEffectView! {
        didSet {
            let layer = CALayer()
            layer.frame = titleBarAdditionalView.bounds
            layer.backgroundColor = .clear
            titleBarAdditionalView.wantsLayer = true
            titleBarAdditionalView.layer = layer
            if UserDefaultsManagement.buttonShow == "Hover" {
                titleBarAdditionalView.alphaValue = 0
            } else {
                titleBarAdditionalView.alphaValue = 1
            }
        }
    }

    @IBOutlet var addProjectButton: NSButton! {
        didSet {
            let layer = CALayer()
            layer.frame = addProjectButton.bounds
            layer.backgroundColor = .clear
            addProjectButton.wantsLayer = true
            addProjectButton.layer = layer
            if UserDefaultsManagement.buttonShow == "Hover" {
                addProjectButton.alphaValue = 0
            } else {
                addProjectButton.alphaValue = 1
            }
        }
    }

    @IBOutlet var formatButton: NSButton!

    @IBOutlet var previewButton: NSButton! {
        didSet {
            previewButton.state = UserDefaultsManagement.preview ? .on : .off
        }
    }

    @IBOutlet var presentationButton: NSButton! {
        didSet {
            presentationButton.state = UserDefaultsManagement.presentation ? .on : .off
        }
    }

    @IBAction func activeWindow(_ sender: Any) {
        activeShortcut()
    }

    @IBOutlet var descendingCheckItem: NSMenuItem! {
        didSet {
            ascendingCheckItem?.state = UserDefaultsManagement.sortDirection ? .off : .on
            descendingCheckItem?.state = UserDefaultsManagement.sortDirection ? .on : .off
        }
    }

    @IBOutlet var ascendingCheckItem: NSMenuItem! {
        didSet {
            ascendingCheckItem?.state = UserDefaultsManagement.sortDirection ? .off : .on
            descendingCheckItem?.state = UserDefaultsManagement.sortDirection ? .on : .off
        }
    }

    @IBOutlet var titleBarView: TitleBarView! {
        didSet {
            titleBarView.onMouseExitedClosure = { [weak self] in
                if UserDefaultsManagement.buttonShow != "Hover" {
                    return
                }
                DispatchQueue.main.async {
                    NSAnimationContext.runAnimationGroup({ context in
                        context.duration = 0.20
                        self?.titleBarAdditionalView.alphaValue = 0
                    }, completionHandler: nil)
                }
            }
            titleBarView.onMouseEnteredClosure = { [weak self] in
                if UserDefaultsManagement.buttonShow != "Hover" {
                    return
                }
                DispatchQueue.main.async {
                    NSAnimationContext.runAnimationGroup({ context in
                        context.duration = 0.20
                        self?.titleBarAdditionalView.alphaValue = 1
                    }, completionHandler: nil)
                }
            }
        }
    }

    @IBOutlet var projectHeaderView: OutlineHeaderView! {
        didSet {
            projectHeaderView.onMouseExitedClosure = { [weak self] in
                if UserDefaultsManagement.buttonShow != "Hover" {
                    return
                }
                DispatchQueue.main.async {
                    NSAnimationContext.runAnimationGroup({ context in
                        context.duration = 0.20
                        self?.addProjectButton.alphaValue = 0
                    }, completionHandler: nil)
                }
            }
            projectHeaderView.onMouseEnteredClosure = { [weak self] in
                if UserDefaultsManagement.buttonShow != "Hover" {
                    return
                }
                DispatchQueue.main.async {
                    NSAnimationContext.runAnimationGroup({ context in
                        context.duration = 0.20
                        self?.addProjectButton.alphaValue = 1
                    }, completionHandler: nil)
                }
            }
        }
    }

    @IBOutlet var sidebarScrollView: NSScrollView!
    @IBOutlet var notesScrollView: NSScrollView!

    lazy var popover: NSPopover = {
        let popover = NSPopover()
        popover.behavior = .semitransient
        popover.contentViewController = ContentViewController()
        popover.delegate = self
        return popover
    }()

    @IBAction func showInfo(_ sender: Any) {
        popover.appearance = NSAppearance(named: NSAppearance.Name.aqua)!

        let selectedCell = notesTableView.view(atColumn: 0, row: notesTableView.selectedRow, makeIfNecessary: false)

        guard let positioningView = selectedCell else {
            return
        }
        let positioningRect = NSZeroRect

        let preferredEdge = NSRectEdge(rectEdge: .maxXEdge)

        popover.show(relativeTo: positioningRect, of: positioningView, preferredEdge: preferredEdge)

        let popoverWindowX = popover.contentViewController?.view.window?.frame.origin.x ?? 0
        let popoverWindowY = popover.contentViewController?.view.window?.frame.origin.y ?? 0

        popover.contentViewController?.view.window?.setFrameOrigin(
            NSPoint(x: popoverWindowX + 18, y: popoverWindowY)
        )

        popover.contentViewController?.view.window?.makeKey()
    }

    @objc func detachedWindowWillClose(notification: NSNotification) {}

    private var popoverVisible: Bool {
        popover.isShown
    }

    func toggleInfo() {
        if popoverVisible {
            popover.performClose(nil)
        } else {
            showInfo("")
            Analytics.trackEvent("MiaoYan ShowInfo")
        }
    }

    override func viewDidLoad() {
        configureShortcuts()
        configureDelegates()
        configureLayout()
        configureNotesList()
        configureEditor()

        fsManager = FileSystemEventManager(storage: storage, delegate: self)

        fsManager?.start()

        loadMoveMenu()
        loadSortBySetting()
        checkSidebarConstraint()
        checkTitlebarTopConstraint()

        #if CLOUDKIT
            registerKeyValueObserver()
        #endif

        searchQueue.maxConcurrentOperationCount = 1
        notesTableView.loadingQueue.maxConcurrentOperationCount = 1
        notesTableView.loadingQueue.qualityOfService = QualityOfService.userInteractive
    }

    func refreshMiaoYanNum() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            let messageText = NSLocalizedString("%d MiaoYan", comment: "")

            self.miaoYanText.stringValue = String(format: messageText, self.notesTableView.noteList.count)
        }
    }

    // 解决长时间放置导致的 web 容器的性能影响
    override func viewDidDisappear() {
        super.viewWillDisappear()

        if UserDefaultsManagement.preview {
            disablePreviewWorkItem = DispatchWorkItem { [weak self] in
                self?.needRestorePreview = true
                self?.disablePreview()
            }
            // 创建延迟执行的工作项，延迟时间为 30 分钟
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1800), execute: disablePreviewWorkItem!)
        } else {
            needRestorePreview = false
        }
    }

    override func viewWillAppear() {
        super.viewWillAppear()

        if UserDefaultsManagement.preview {
            disablePreviewWorkItem?.cancel()
        }
        if needRestorePreview {
            titleLabel.saveTitle()
            enablePreview()
        }
    }

    override func viewDidAppear() {
        if UserDefaultsManagement.fullScreen {
            view.window?.toggleFullScreen(nil)
        }

        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            if let urls = appDelegate.urls {
                appDelegate.openNotes(urls: urls)
                return
            }

            if let query = appDelegate.searchQuery {
                appDelegate.search(query: query)
                return
            }

            if appDelegate.newName != nil || appDelegate.newContent != nil {
                let name = appDelegate.newName ?? ""
                let content = appDelegate.newContent ?? ""

                appDelegate.create(name: name, content: content)
            }
        }
        handleForAppMode()
    }

    func handleForAppMode() {
        updateDividers()
        refreshMiaoYanNum()

        if UserDefaultsManagement.isSingleMode {
            toastInSingleMode()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.hideSidebar("")
            }
        } else if UserDefaultsManagement.isFirstLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.showSidebar("")
            }
            UserDefaultsManagement.isFirstLaunch = false
        } else {
            ensureInitialProjectSelection()
        }
    }
    
    private func ensureInitialProjectSelection() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard self.sidebarWidth > 0 && self.storageOutlineView.selectedRow == -1 else { return }
            
            // Try to find the project by URL first (more reliable after reordering)
            if let lastProjectURL = UserDataService.instance.lastProject,
               let items = self.storageOutlineView.sidebarItems {
                
                for (index, item) in items.enumerated() {
                    if let sidebarItem = item as? SidebarItem,
                       sidebarItem.project?.url == lastProjectURL {
                        self.storageOutlineView.selectRowIndexes([index], byExtendingSelection: false)
                        return
                    }
                }
            }
            
            // Fallback to index-based selection if URL matching fails
            let lastProjectIndex = UserDefaultsManagement.lastProject
            if let items = self.storageOutlineView.sidebarItems, 
               items.indices.contains(lastProjectIndex) {
                self.storageOutlineView.selectRowIndexes([lastProjectIndex], byExtendingSelection: false)
            } else if let items = self.storageOutlineView.sidebarItems, !items.isEmpty {
                self.storageOutlineView.selectRowIndexes([0], byExtendingSelection: false)
            }
        }
    }

    func toastInSingleMode() {
        toast(message: NSLocalizedString("🙊 In single open mode, Exit with Command+Shift+W ~", comment: ""))
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let vc = ViewController.shared() else {
            return false
        }

        let canUseMenu = !(UserDefaultsManagement.magicPPT || UserDefaultsManagement.presentation)

        if let title = menuItem.menu?.identifier?.rawValue {
            switch title {
            case "miaoyanMenu":
                if menuItem.identifier?.rawValue == "emptyTrashMenu" {
                    menuItem.keyEquivalentModifierMask = [.command, .option, .shift]
                    return canUseMenu
                }
            case "fileMenu":
                if menuItem.identifier?.rawValue == "fileMenu.delete" {
                    menuItem.keyEquivalentModifierMask = [.command]
                }

                if ["fileMenu.new", "fileMenu.searchAndCreate", "fileMenu.open", "fileMenu.import"].contains(menuItem.identifier?.rawValue) {
                    return canUseMenu
                }

                if vc.notesTableView.selectedRow == -1 {
                    return false
                }

            case "folderMenu":
                if ["folderMenu.newFolder", "folderMenu.showInFinder", "folderMenu.renameFolder"].contains(menuItem.identifier?.rawValue) {
                    return canUseMenu
                }

                guard let p = vc.getSidebarProject(), !p.isTrash else {
                    return false
                }
            case "findMenu":
                if ["findMenu.find", "findMenu.findAndReplace", "findMenu.next", "findMenu.prev"].contains(menuItem.identifier?.rawValue), vc.notesTableView.selectedRow > -1 {
                    return canUseMenu
                }

                return vc.editAreaScroll.isFindBarVisible || vc.editArea.hasFocus()
            default:
                break
            }
        }

        return true
    }

    private func configureLayout() {
        // hack for first shack
        emptyEditAreaView.isHidden = true
        titleLabel.isHidden = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.titleLabel.isHidden = false
        }

        updateTitle(newTitle: "")

        DispatchQueue.main.async {
            self.editArea.updateTextContainerInset()
        }

        editArea.textContainerInset.height = 10
        editArea.isEditable = false

        editArea.layoutManager?.defaultAttachmentScaling = .scaleProportionallyDown
        if UserDefaultsManagement.fontName != "LXGW WenKai Screen" {
            editArea.layoutManager?.typesetterBehavior = .behavior_10_2_WithCompatibility
        }
        search.font = UserDefaultsManagement.searchFont

        editArea.defaultParagraphStyle = NSTextStorage.getParagraphStyle()
        editArea.typingAttributes = [
            .font: UserDefaultsManagement.noteFont!,
            .paragraphStyle: NSTextStorage.getParagraphStyle(),
        ]

        titleLabel.font = UserDefaultsManagement.titleFont.titleBold()
        emptyEditTitle.font = UserDefaultsManagement.emptyEditTitleFont

        setTableRowHeight()
        storageOutlineView.sidebarItems = Sidebar().getList()

        storageOutlineView.selectionHighlightStyle = .none

        sidebarSplitView.autosaveName = "SidebarSplitView"
        splitView.autosaveName = "EditorSplitView"
        
        // 设置sidebar outline view的autosave name来保存展开状态
        storageOutlineView.autosaveExpandedItems = true
        storageOutlineView.autosaveName = "SidebarOutlineView"

        notesScrollView.scrollerStyle = .overlay
        sidebarScrollView.scrollerStyle = .overlay
        sidebarScrollView.horizontalScroller = .none
        sidebarScrollView.hasHorizontalScroller = false
        sidebarScrollView.autohidesScrollers = true
        
        // 确保sidebar列宽随父视图调整
        if let column = storageOutlineView.tableColumns.first {
            column.resizingMask = .autoresizingMask
            column.minWidth = 50
            column.maxWidth = 1000
        }
    }

    private func configureNotesList() {
        var lastSidebarItem = UserDefaultsManagement.lastProject
        if UserDefaultsManagement.isSingleMode {
            lastSidebarItem = 0
        }
        
        updateTable {
            // Set sidebar selection after table update to properly trigger selection change
            if let items = self.storageOutlineView.sidebarItems, items.indices.contains(lastSidebarItem) {
                // Use a small delay to ensure table is fully loaded before selection
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    self.storageOutlineView.selectRowIndexes([lastSidebarItem], byExtendingSelection: false)
                }
            }
            
            if UserDefaultsManagement.isSingleMode {
                let singleModeUrl = URL(fileURLWithPath: UserDefaultsManagement.singleModePath)
                if !FileManager.default.directoryExists(atUrl: singleModeUrl), let lastNote = self.storage.getBy(url: singleModeUrl), let i = self.notesTableView.getIndex(lastNote) {
                    self.notesTableView.selectRow(i)
                    self.notesTableView.scrollRowToVisible(row: i, animated: false)
                    self.hideNoteList("")
                }
                self.storageOutlineView.isLaunch = false
            }
        }
    }

    private func configureEditor() {
        editArea.usesFindBar = true
        editArea.isIncrementalSearchingEnabled = true
        editArea.isAutomaticLinkDetectionEnabled = false
        editArea.isAutomaticQuoteSubstitutionEnabled = false
        editArea.isAutomaticDataDetectionEnabled = false
        editArea.isAutomaticTextReplacementEnabled = false
        editArea.isAutomaticDashSubstitutionEnabled = false
        editArea.textStorage?.delegate = editArea.textStorage
        if #available(OSX 10.13, *) {
            editArea?.linkTextAttributes = [
                .foregroundColor: NSColor(named: "highlight")!,
            ]
        }
        editArea.viewDelegate = self
    }

    private func configureShortcuts() {
        let activeShortcut = MASShortcut(keyCode: kVK_ANSI_M, modifierFlags: [.command, .option])

        MASShortcutMonitor.shared().register(activeShortcut, withAction: {
            self.activeShortcut()
        })

        NSEvent.addLocalMonitorForEvents(matching: NSEvent.EventTypeMask.flagsChanged) {
            $0
        }

        NSEvent.addLocalMonitorForEvents(matching: NSEvent.EventTypeMask.keyDown) {
            if self.keyDown(with: $0) {
                return $0
            }
            return nil
        }
    }

    private func configureDelegates() {
        editArea.delegate = self
        search.vcDelegate = self
        search.delegate = search
        sidebarSplitView.delegate = self
        storageOutlineView.viewDelegate = self
    }

    // MARK: - Actions

    @IBAction func searchAndCreate(_ sender: Any) {
        guard let vc = ViewController.shared() else {
            return
        }

        let size = vc.splitView.subviews[0].frame.width

        if size == 0 {
            toggleNoteList(self)
        }

        vc.search.window?.makeFirstResponder(vc.search)
    }

    @IBAction func sortDirectionBy(_ sender: NSMenuItem) {
        let name = sender.identifier!.rawValue
        if name == "Ascending", UserDefaultsManagement.sortDirection {
            UserDefaultsManagement.sortDirection = false
            reSortByDirection()
        }
        if name == "Descending", !UserDefaultsManagement.sortDirection {
            UserDefaultsManagement.sortDirection = true
            reSortByDirection()
        }
    }

    @IBAction func sortBy(_ sender: NSMenuItem) {
        if let id = sender.identifier {
            let key = String(id.rawValue.dropFirst(3))
            guard let sortBy = SortBy(rawValue: key) else { return }

            UserDefaultsManagement.sort = sortBy

            if let submenu = sortByOutlet.submenu {
                for item in submenu.items {
                    item.state = NSControl.StateValue.off
                }
            }

            sender.state = NSControl.StateValue.on

            reSortByDirection()
        }
    }

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

        vc.updateTable()
        // 修复排序后不选中问题
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            let selectedRow = vc.notesTableView.selectedRowIndexes.min()
            if selectedRow == nil {
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

    @objc func moveNote(_ sender: NSMenuItem) {
        let project = sender.representedObject as! Project

        guard let notes = notesTableView.getSelectedNotes() else {
            return
        }

        move(notes: notes, project: project)
    }

    public func move(notes: [Note], project: Project) {
        let selectedRow = notesTableView.selectedRowIndexes.min()
        for note in notes {
            if note.project == project {
                continue
            }

            let destination = project.url.appendingPathComponent(note.name)

            if note.type == .Markdown, note.container == .none {
                let imagesMeta = note.getAllImages()
                for imageMeta in imagesMeta {
                    move(note: note, from: imageMeta.url, imagePath: imageMeta.path, to: project)
                }

                if imagesMeta.count > 0 {
                    note.save()
                }
            }

            _ = note.move(to: destination, project: project)

            if !isFit(note: note, shouldLoadMain: true) {
                notesTableView.removeByNotes(notes: [note])

                if let i = selectedRow, i > -1 {
                    if notesTableView.noteList.count > i {
                        notesTableView.selectRow(i)
                    } else {
                        notesTableView.selectRow(notesTableView.noteList.count - 1)
                    }
                }
            }

            note.invalidateCache()
        }

        editArea.clear()
    }

    private func move(note: Note, from imageURL: URL, imagePath: String, to project: Project, copy: Bool = false) {
        let dstPrefix = NotesTextProcessor.getAttachPrefix(url: imageURL)
        let dest = project.url.appendingPathComponent(dstPrefix)

        if !FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: false, attributes: nil)
        }

        do {
            if copy {
                try FileManager.default.copyItem(at: imageURL, to: dest)
            } else {
                try FileManager.default.moveItem(at: imageURL, to: dest)
            }
        } catch {
            if let fileName = ImagesProcessor.getFileName(from: imageURL, to: dest, ext: imageURL.pathExtension) {
                let dest = dest.appendingPathComponent(fileName)

                if copy {
                    try? FileManager.default.copyItem(at: imageURL, to: dest)
                } else {
                    try? FileManager.default.moveItem(at: imageURL, to: dest)
                }

                let prefix = "]("
                let postfix = ")"

                let find = prefix + imagePath + postfix
                let replace = prefix + dstPrefix + fileName + postfix

                guard find != replace else {
                    return
                }

                while note.content.mutableString.contains(find) {
                    let range = note.content.mutableString.range(of: find)
                    note.content.replaceCharacters(in: range, with: replace)
                }
            }
        }
    }

    func viewDidResize() {
        checkSidebarConstraint()
        checkTitlebarTopConstraint()
        updateDividers()

        if !refilled {
            refilled = true
            DispatchQueue.main.async {
                self.refillEditArea(previewOnly: true)
                self.refilled = false
            }
        }
    }

    func reloadSideBar() {
        guard let outline = storageOutlineView else {
            return
        }

        sidebarTimer.invalidate()
        sidebarTimer = Timer.scheduledTimer(timeInterval: 1.2, target: outline, selector: #selector(outline.reloadSidebar), userInfo: nil, repeats: false)
    }

    func setTableRowHeight() {
        notesTableView.rowHeight = CGFloat(52)
        notesTableView.selectionHighlightStyle = .none
        notesTableView.reloadData()
    }

    func refillEditArea(cursor: Int? = nil, previewOnly: Bool = false, saveTyping: Bool = false, force: Bool = false) {
        DispatchQueue.main.async { [weak self] in
            self?.previewButton.state = UserDefaultsManagement.preview ? .on : .off
            self?.presentationButton.state = UserDefaultsManagement.presentation ? .on : .off
        }

        guard !previewOnly || previewOnly && UserDefaultsManagement.preview else {
            return
        }

        DispatchQueue.main.async {
            var location: Int = 0

            if let unwrappedCursor = cursor {
                location = unwrappedCursor
            } else {
                location = self.editArea.selectedRanges[0].rangeValue.location
            }

            let selected = self.notesTableView.selectedRow
            if selected > -1, self.notesTableView.noteList.indices.contains(selected) {
                if let note = self.notesTableView.getSelectedNote() {
                    self.editArea.fill(note: note, highlight: true, saveTyping: saveTyping, force: force)
                    self.editArea.setSelectedRange(NSRange(location: location, length: 0))
                }
            }
        }
    }

    public func keyDown(with event: NSEvent) -> Bool {
        guard let mw = MainWindowController.shared() else {
            return false
        }

        guard alert == nil else {
            if event.keyCode == kVK_Escape, let unwrapped = alert {
                mw.endSheet(unwrapped.window)
                alert = nil
            }

            return true
        }

        if event.modifierFlags.contains(.command), event.modifierFlags.contains(.option), event.keyCode == kVK_ANSI_P {
            toggleMagicPPT()
            return false
        }

        if event.modifierFlags.contains(.shift), event.modifierFlags.contains(.control), event.keyCode == kVK_ANSI_H {
            exportHtml("")
            return false
        }

        if event.keyCode == kVK_Escape, UserDefaultsManagement.presentation {
            disablePresentation()
        }

        if event.keyCode == kVK_Delete, event.modifierFlags.contains(.command), search.hasFocus() {
            search.stringValue.removeAll()
            configureNotesList()
            refreshMiaoYanNum()
            return false
        }

        if event.keyCode == kVK_Escape, search.hasFocus() {
            search.stringValue.removeAll()
            configureNotesList()
            refreshMiaoYanNum()
            return false
        }

        if event.keyCode == kVK_Escape, titleLabel.hasFocus() {
            focusEditArea()
            return false
        }

        if event.keyCode == kVK_Delete, event.modifierFlags.contains(.command), editArea.hasFocus(), !UserDefaultsManagement.presentation {
            editArea.deleteToBeginningOfLine(nil)
            return false
        }

        if event.keyCode == kVK_Delete, event.modifierFlags.contains(.command), titleLabel.hasFocus(), !UserDefaultsManagement.preview {
            updateTitle(newTitle: "")
            return false
        }

        // 聚焦的时候就不要新建了
        if event.keyCode == kVK_ANSI_D, event.modifierFlags.contains(.command), editArea.hasFocus() {
            return false
        }

        if event.keyCode == kVK_ANSI_Z, event.modifierFlags.contains(.command), titleLabel.hasFocus() {
            let currentNote = notesTableView.getSelectedNote()
            updateTitle(newTitle: currentNote?.getTitleWithoutLabel() ?? NSLocalizedString("Untitled Note", comment: "Untitled Note"))
            return false
        }

        if event.keyCode == kVK_ANSI_Z, event.modifierFlags.contains(.command), editArea.hasFocus(), formatContent != "" {
            if let note = notesTableView.getSelectedNote(), note.content.string == formatContent {
                let cursor = editArea.selectedRanges[0].rangeValue.location
                DispatchQueue.main.async {
                    self.editArea.setSelectedRange(NSRange(location: cursor, length: 0))
                }
                formatContent = ""
            }
        }

        if event.modifierFlags.contains(.command), event.modifierFlags.contains(.option), event.keyCode == kVK_ANSI_I, !UserDefaultsManagement.presentation {
            toggleInfo()
            return false
        }

        if event.modifierFlags.contains(.command), event.modifierFlags.contains(.option), event.keyCode == kVK_ANSI_U {
            copyURL("")
            return false
        }

        if event.keyCode == kVK_ANSI_W, event.modifierFlags.contains(.command), event.modifierFlags.contains(.shift) {
            if UserDefaultsManagement.isSingleMode {
                UserDefaultsManagement.isSingleMode = false
                UserDefaultsManagement.isFirstLaunch = true
                UserDefaultsManagement.singleModePath = ""
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.restart()
                }
            }
            return false
        }

        // Return / Cmd + Return navigation
        if event.keyCode == kVK_Return {
            if let fr = NSApp.mainWindow?.firstResponder, alert == nil {
                // 兼容一下ppt模式的选中
                if UserDefaultsManagement.magicPPT {
                    DispatchQueue.main.async {
                        self.editArea.markdownView!.evaluateJavaScript("Reveal.toggleOverview();", completionHandler: nil)
                    }
                    return false
                }

                if event.modifierFlags.contains(.command) {
                    if fr.isKind(of: NotesTableView.self) {
                        NSApp.mainWindow?.makeFirstResponder(storageOutlineView)
                        return false
                    }
                } else {
                    if fr.isKind(of: SidebarProjectView.self) {
                        notesTableView.selectNext()
                        NSApp.mainWindow?.makeFirstResponder(notesTableView)
                        return false
                    }

                    if let note = EditTextView.note, fr.isKind(of: NotesTableView.self), !(UserDefaultsManagement.preview && !note.isRTF()) {
                        NSApp.mainWindow?.makeFirstResponder(editArea)
                        return false
                    }

                    // 日语环境的输入方式和国内不太一样，兼容一下
                    if titleLabel.hasFocus() {
                        if UserDefaultsManagement.defaultLanguage != 0x02 {
                            focusEditArea()
                        }
                        return false
                    }
                }
            }

            return true
        }

        // Tab / Control + Tab
        if event.keyCode == kVK_Tab {
            if event.modifierFlags.contains(.control) {
                notesTableView.window?.makeFirstResponder(notesTableView)
                return true
            }

            if let fr = NSApp.mainWindow?.firstResponder, fr.isKind(of: NotesTableView.self) {
                NSApp.mainWindow?.makeFirstResponder(notesTableView)
                return false
            }
        }

        // Focus search bar on ESC
        if
            event.characters == ".",
            event.modifierFlags.contains(.command),

            NSApplication.shared.mainWindow == NSApplication.shared.keyWindow
        {
            UserDataService.instance.resetLastSidebar()

            if let view = NSApplication.shared.mainWindow?.firstResponder as? NSTextView, let textField = view.superview?.superview, textField.isKind(of: NameTextField.self) {
                NSApp.mainWindow?.makeFirstResponder(notesTableView)
                return false
            }

            if editAreaScroll.isFindBarVisible {
                cancelTextSearch()
                return false
            }

            // Renaming is in progress
            if titleLabel.isEditable {
                titleLabel.window?.makeFirstResponder(notesTableView)
                return false
            }

            UserDefaultsManagement.lastProject = 0
            UserDefaultsManagement.lastSelectedURL = nil

            notesTableView.scroll(.zero)

            let hasSelectedNotes = notesTableView.selectedRow > -1
            let hasSelectedBarItem = storageOutlineView.selectedRow > -1

            if hasSelectedBarItem, hasSelectedNotes {
                UserDefaultsManagement.lastProject = 0
                UserDataService.instance.isNotesTableEscape = true
                notesTableView.deselectAll(nil)
                NSApp.mainWindow?.makeFirstResponder(search)
                return false
            }

            storageOutlineView.deselectAll(nil)
            cleanSearchAndEditArea()

            return true
        }

        // 文章搜索
        if event.keyCode == kVK_ANSI_F, event.modifierFlags.contains(.shift), event.modifierFlags.contains(.command), !event.modifierFlags.contains(.control), editArea.hasFocus() {
            if notesTableView.getSelectedNote() != nil {
                disablePreview()
                return true
            }
        }

        if event.keyCode == kVK_ANSI_F, event.modifierFlags.contains(.command), !event.modifierFlags.contains(.control) {
            if notesTableView.getSelectedNote() != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.titleLabel.saveTitle()
                }
                return true
            }
        }

        // Pin note shortcut (cmd+shift+p)
        if event.keyCode == kVK_ANSI_P, event.modifierFlags.contains(.shift), event.modifierFlags.contains(.command), !UserDefaultsManagement.presentation {
            pin(notesTableView.selectedRowIndexes)
            return true
        }

        // 展开 sidebar cmd+1
        if event.modifierFlags.contains(.command), event.keyCode == kVK_ANSI_1, !UserDefaultsManagement.presentation {
            toggleSidebar("")
            return false
        }

        // 保存
        if event.modifierFlags.contains(.command), event.keyCode == kVK_ANSI_S {
            titleLabel.saveTitle()
            return false
        }

        if let fr = mw.firstResponder, !fr.isKind(of: EditTextView.self), !fr.isKind(of: NSTextView.self), !event.modifierFlags.contains(.command),
           !event.modifierFlags.contains(.control)
        {
            if let char = event.characters {
                let newSet = CharacterSet(charactersIn: char)
                if newSet.isSubset(of: CharacterSet.alphanumerics) {
                    search.becomeFirstResponder()
                }
            }
        }

        return true
    }

    func cancelTextSearch() {
        let menu = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        menu.tag = NSTextFinder.Action.hideFindInterface.rawValue
        editArea.performTextFinderAction(menu)

        if !UserDefaultsManagement.preview {
            NSApp.mainWindow?.makeFirstResponder(editArea)
        }
    }

    @IBAction func quiteApp(_ sender: Any) {
        if UserDefaultsManagement.isSingleMode {
            UserDefaultsManagement.isSingleMode = false
            UserDefaultsManagement.singleModePath = ""
            UserDefaultsManagement.isFirstLaunch = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApplication.shared.terminate(self)
            }
        } else {
            NSApplication.shared.terminate(self)
        }
    }

    @IBAction func makeNote(_ sender: SearchTextField) {
        guard let vc = ViewController.shared() else { return }
        if let type = vc.getSidebarType(), type == .Trash {
            vc.storageOutlineView.deselectAll(nil)
        }

        let value = sender.stringValue

        if value.count > 0 {
            search.stringValue = String()
            editArea.clear()
            createNote(name: value, content: "")
        } else {
            createNote(content: "")
        }
    }

    @IBAction func fileMenuNewNote(_ sender: Any) {
        guard let vc = ViewController.shared() else { return }
        if UserDefaultsManagement.magicPPT {
            return
        }
        if let type = vc.getSidebarType(), type == .Trash {
            vc.storageOutlineView.deselectAll(nil)
        }
        vc.focusTable()
        vc.createNote(name: "", content: "")
    }

    func restart() {
        let url = URL(fileURLWithPath: Bundle.main.resourcePath!)
        let path = url.deletingLastPathComponent().deletingLastPathComponent().absoluteString
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [path]
        task.launch()
        exit(0)
    }

    @IBAction func singleOpen(_ sender: NSMenuItem) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.canCreateDirectories = false
        panel.begin { result in
            if result == NSApplication.ModalResponse.OK {
                let urls = panel.urls
                UserDefaultsManagement.singleModePath = urls[0].path
                UserDefaultsManagement.isSingleMode = true
                self.restart()
            }
        }
    }

    @IBAction func importNote(_ sender: NSMenuItem) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.canCreateDirectories = false
        panel.begin { result in
            if result == NSApplication.ModalResponse.OK {
                let urls = panel.urls
                let project = self.getSidebarProject() ?? self.storage.getMainProject()

                for url in urls {
                    _ = self.copy(project: project, url: url)
                }
            }
        }
    }

    @IBAction func moveMenu(_ sender: Any) {
        guard let vc = ViewController.shared() else { return }
        if vc.notesTableView.selectedRow >= 0 {
            vc.loadMoveMenu()

            let moveTitle = NSLocalizedString("Move", comment: "Menu")
            let moveMenu = vc.noteMenu.item(withTitle: moveTitle)
            let view = vc.notesTableView.rect(ofRow: vc.notesTableView.selectedRow)
            let x = vc.splitView.subviews[0].frame.width + 5
            let general = moveMenu?.submenu?.item(at: 0)

            moveMenu?.submenu?.popUp(positioning: general, at: NSPoint(x: x, y: view.origin.y + 8), in: vc.notesTableView)
        }
    }

    @IBAction func exportMenu(_ sender: Any) {
        guard let vc = ViewController.shared() else { return }
        if vc.notesTableView.selectedRow >= 0 {
            let exportTitle = NSLocalizedString("Export", comment: "Menu")
            let exportMenu = vc.noteMenu.item(withTitle: exportTitle)
            let view = vc.notesTableView.rect(ofRow: vc.notesTableView.selectedRow)
            let x = vc.splitView.subviews[0].frame.width + 5
            let general = exportMenu?.submenu?.item(at: 0)

            exportMenu?.submenu?.popUp(positioning: general, at: NSPoint(x: x, y: view.origin.y + 8), in: vc.notesTableView)
        }
    }

    @IBAction func fileName(_ sender: NSTextField) {
        guard let note = notesTableView.getNoteFromSelectedRow() else {
            return
        }

        let value = sender.stringValue
        let url = note.url

        let newName = sender.stringValue + "." + note.url.pathExtension
        let isSoftRename = note.url.lastPathComponent.lowercased() == newName.lowercased()

        if note.project.fileExist(fileName: value, ext: note.url.pathExtension), !isSoftRename {
            alert = NSAlert()
            guard let alert = alert else {
                return
            }

            alert.messageText = "Hmm, something goes wrong 🙈"
            alert.informativeText = "Note with name \"\(value)\" already exists in selected storage."
            alert.runModal()

            note.parseURL()
            sender.stringValue = note.getTitleWithoutLabel()
            return
        }

        guard value.count > 0 else {
            sender.stringValue = note.getTitleWithoutLabel()
            return
        }

        sender.isEditable = false

        let newUrl = note.getNewURL(name: value)
        UserDataService.instance.focusOnImport = newUrl

        if note.url.path == newUrl.path {
            return
        }

        note.overwrite(url: newUrl)

        do {
            try FileManager.default.moveItem(at: url, to: newUrl)
            print("File moved from \"\(url.deletingPathExtension().lastPathComponent)\" to \"\(newUrl.deletingPathExtension().lastPathComponent)\"")
        } catch {
            note.overwrite(url: url)
        }
    }

    @IBAction func finderMenu(_ sender: NSMenuItem) {
        if let notes = notesTableView.getSelectedNotes() {
            var urls = [URL]()
            for note in notes {
                urls.append(note.url)
            }
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    }

    @IBAction func makeMenu(_ sender: Any) {
        guard let vc = ViewController.shared() else { return }
        if let type = vc.getSidebarType(), type == .Trash {
            vc.storageOutlineView.deselectAll(nil)
        }

        vc.createNote()
    }

    @IBAction func pinMenu(_ sender: Any) {
        guard let vc = ViewController.shared() else { return }
        vc.pin(vc.notesTableView.selectedRowIndexes)
    }

    @IBAction func renameMenu(_ sender: Any) {
        guard let vc = ViewController.shared() else { return }
        vc.titleLabel.restoreResponder = vc.view.window?.firstResponder
        switchTitleToEditMode()
    }

    @objc func switchTitleToEditMode() {
        guard let vc = ViewController.shared() else {
            return
        }

        vc.titleLabel.editModeOn()
        if let note = EditTextView.note {
            vc.titleLabel.stringValue = note.getShortTitle()
        }
    }

    @IBAction func deleteNote(_ sender: Any) {
        guard let vc = ViewController.shared() else {
            return
        }

        if vc.titleLabel.hasFocus() || vc.editArea.hasFocus() || vc.search.hasFocus() || UserDefaultsManagement.magicPPT || UserDefaultsManagement.presentation || vc.editAreaScroll.isFindBarVisible {
            return
        }

        guard let notes = vc.notesTableView.getSelectedNotes() else {
            return
        }

        if let si = vc.getSidebarItem(), si.isTrash() {
            removeForever()
            return
        }

        let selectedRow = vc.notesTableView.selectedRowIndexes.min()

        UserDataService.instance.searchTrigger = true

        vc.notesTableView.removeByNotes(notes: notes)

        vc.storage.removeNotes(notes: notes) { urls in

            if let appd = NSApplication.shared.delegate as? AppDelegate,
               let md = appd.mainWindowController
            {
                let undoManager = md.notesListUndoManager

                if let ntv = vc.notesTableView {
                    undoManager.registerUndo(withTarget: ntv, selector: #selector(ntv.unDelete), object: urls)
                    undoManager.setActionName(NSLocalizedString("Delete", comment: ""))
                }

                if let i = selectedRow, i > -1 {
                    vc.notesTableView.selectRow(i)
                }

                UserDataService.instance.searchTrigger = false
            }

            if UserDefaultsManagement.preview {
                vc.disablePreview()
            }

            vc.editArea.clear()
            vc.emptyEditAreaView.isHidden = true
        }

        NSApp.mainWindow?.makeFirstResponder(vc.notesTableView)
    }

    // MARK: - Sidebar Layout Manager
    
    func setDividerColor(for splitView: NSSplitView, hidden: Bool) {
        DispatchQueue.main.async {
            let color = hidden ? 
                (NSColor(named: "mainBackground") ?? NSColor.windowBackgroundColor) :
                (NSColor(named: "divider") ?? NSColor.separatorColor)
            splitView.setValue(color, forKey: "dividerColor")
            splitView.needsDisplay = true
        }
    }
    
    private var sidebarWidth: CGFloat {
        guard sidebarSplitView.subviews.count > 0 else { return 0 }
        return sidebarSplitView.subviews[0].frame.width
    }
    
    private var notelistWidth: CGFloat {
        guard splitView.subviews.count > 0 else { return 0 }
        return splitView.subviews[0].frame.width
    }
    
    func updateDividers() {
        guard sidebarSplitView != nil && splitView != nil else { return }
        setDividerColor(for: sidebarSplitView, hidden: sidebarWidth == 0)
        setDividerColor(for: splitView, hidden: notelistWidth == 0)
    }

    @IBAction func toggleNoteList(_ sender: Any) {
        guard splitView != nil else { return }
        
        if notelistWidth == 0 {
            showNoteList(sender)
        } else {
            hideNoteList(sender)
        }
    }

    @IBAction func toggleSidebar(_ sender: Any) {
        guard sidebarSplitView != nil else { return }
        if UserDefaultsManagement.isSingleMode {
            toastInSingleMode()
            return
        }
        if sidebarWidth == 0 {
            showSidebar(sender)
        } else {
            hideSidebar(sender)
        }
    }

    override func wantsScrollEventsForSwipeTracking(on axis: NSEvent.GestureAxis) -> Bool {
        axis == .horizontal
    }

    override func swipe(with event: NSEvent) {
        swipe(deltaX: event.deltaX)
    }

    override func scrollWheel(with event: NSEvent) {
        if !NSEvent.isSwipeTrackingFromScrollEventsEnabled {
            super.scrollWheel(with: event)
            return
        }

        switch event.phase {
        case .began:
            isHandlingScrollEvent = true
            swipeLeftExecuted = false
            swipeRightExecuted = false
            scrollDeltaX = 0
        case .changed:
            guard isHandlingScrollEvent else {
                break
            }

            let directionChanged = scrollDeltaX.sign != event.scrollingDeltaX.sign

            guard !directionChanged else {
                scrollDeltaX = event.scrollingDeltaX
                break
            }

            scrollDeltaX += event.scrollingDeltaX

            // throttle
            guard abs(scrollDeltaX) > 50 else {
                break
            }

            let flippedScrollDelta = scrollDeltaX * -1
            let swipedLeft = flippedScrollDelta > 0

            switch (swipedLeft, swipeLeftExecuted, swipeRightExecuted) {
            case (true, false, _): // swiped left
                swipeLeftExecuted = true
                swipeRightExecuted = false // allow swipe back (right)
            case (false, _, false): // swiped right
                swipeLeftExecuted = false // allow swipe back (left)
                swipeRightExecuted = true
            default:
                super.scrollWheel(with: event)
                return
            }
            swipe(deltaX: flippedScrollDelta)
            return
        case .cancelled,
             .ended,
             .mayBegin:
            isHandlingScrollEvent = false
        default:
            break
        }

        super.scrollWheel(with: event)
    }

    private func swipe(deltaX: CGFloat) {
        guard deltaX != 0 else { return }

        guard let vc = ViewController.shared() else { return }
        let siderbarSize = Int(vc.sidebarSplitView.subviews[0].frame.width)
        let notelistSize = Int(vc.splitView.subviews[0].frame.width)

        let swipedLeft = deltaX > 0

        if swipedLeft {
            if siderbarSize > 0 {
                hideSidebar("")
            } else {
                if notelistSize > 0 {
                    hideNoteList("")
                }
            }

        } else {
            if notelistSize == 0 {
                showNoteList("")
            } else {
                if siderbarSize == 0 {
                    showSidebar("")
                }
            }
        }
    }

    func hideSidebar(_ sender: Any) {
        guard sidebarWidth > 0 else { return }
        UserDefaultsManagement.realSidebarSize = Int(sidebarWidth)
        sidebarSplitView.setPosition(0, ofDividerAt: 0)
        updateDividers()
        editArea.updateTextContainerInset()
    }

    func showSidebar(_ sender: Any) {
        guard UserDefaultsManagement.isSingleMode == false else {
            toastInSingleMode()
            return
        }
        guard sidebarWidth == 0 else { return }
        
        // 使用保存的宽度
        let targetWidth = UserDefaultsManagement.realSidebarSize
        sidebarSplitView.setPosition(CGFloat(targetWidth), ofDividerAt: 0)
        
        // sidebar展开时，联动展开notelist
        if notelistWidth == 0 {
            expandNoteList()
        }
        
        updateDividers()
        editArea.updateTextContainerInset()
    }

    func showNoteList(_ sender: Any) {
        if notelistWidth == 0 {
            // 如果sidebar也是收起的，先展开sidebar再展开notelist
            if sidebarWidth == 0 {
                showSidebar(sender)
            } else {
                expandNoteList()
            }
        }
        editArea.updateTextContainerInset()
    }
    
    private func expandNoteList() {
        let size = UserDefaultsManagement.sidebarSize == 0 ? 280 : UserDefaultsManagement.sidebarSize
        splitView.shouldHideDivider = false
        splitView.setPosition(CGFloat(size), ofDividerAt: 0)
        updateDividers()
    }

    func hideNoteList(_ sender: Any) {
        if notelistWidth > 0 {
            UserDefaultsManagement.sidebarSize = Int(notelistWidth)
            splitView.shouldHideDivider = true
            splitView.setPosition(0, ofDividerAt: 0)
            
            // notelist收起时，联动收起sidebar
            hideSidebar("")
            
            updateDividers()
        }
        editArea.updateTextContainerInset()
    }

    @IBAction func emptyTrash(_ sender: NSMenuItem) {
        guard let vc = ViewController.shared() else {
            return
        }

        if let sidebarItem = vc.getSidebarItem(), sidebarItem.isTrash() {
            let indexSet = IndexSet(integersIn: 0..<vc.notesTableView.noteList.count)
            vc.notesTableView.removeRows(at: indexSet, withAnimation: .effectFade)
        }

        let notes = storage.getAllTrash()
        for note in notes {
            _ = note.removeFile()
        }

        NSSound(named: "Pop")?.play()
    }

    @IBAction func openProjectViewSettings(_ sender: NSMenuItem) {
        guard let vc = ViewController.shared() else {
            return
        }

        if let controller = vc.storyboard?.instantiateController(withIdentifier: "ProjectSettingsViewController")
            as? ProjectSettingsViewController
        {
            projectSettingsViewController = controller

            if let project = vc.getSidebarProject() {
                vc.presentAsSheet(controller)
                controller.load(project: project)
            }
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField, textField == titleLabel else {
            return
        }

        if titleLabel.isEditable == true {
            fileName(titleLabel)
            view.window?.makeFirstResponder(notesTableView)
        } else {
            let currentNote = notesTableView.getSelectedNote()
            updateTitle(newTitle: currentNote?.getTitleWithoutLabel() ?? NSLocalizedString("Untitled Note", comment: "Untitled Note"))
        }
    }

    public func blockFSUpdates() {
        timer.invalidate()
        timer = Timer.scheduledTimer(timeInterval: 0.2, target: self, selector: #selector(enableFSUpdates), userInfo: nil, repeats: false)

        UserDataService.instance.fsUpdatesDisabled = true
    }

    // Changed main edit view
    func textDidChange(_ notification: Notification) {
        guard let note = getCurrentNote() else { return }

        blockFSUpdates()

        if !UserDefaultsManagement.preview, editArea.isEditable {
            editArea.saveImages()
            note.save(attributed: editArea.attributedString())

            // 编辑内容，标题排序的时候有bug，先关掉
            if !updateViews.contains(note), UserDefaultsManagement.sort != .title {
                updateViews.append(note)
            }

            rowUpdaterTimer.invalidate()
            rowUpdaterTimer = Timer.scheduledTimer(timeInterval: 30, target: self, selector: #selector(breakUndo), userInfo: nil, repeats: true)
        }
    }

    @objc func breakUndo() {
        editArea.breakUndoCoalescing()
    }

    public func getCurrentNote() -> Note? {
        EditTextView.note
    }

    private func removeForever() {
        guard let vc = ViewController.shared() else { return }
        guard let notes = vc.notesTableView.getSelectedNotes() else { return }
        guard let window = MainWindowController.shared() else { return }

        vc.alert = NSAlert()
        guard let alert = vc.alert else { return }

        alert.messageText = String(format: NSLocalizedString("Are you sure you want to irretrievably delete %d note(s)?", comment: ""), notes.count)

        alert.informativeText = NSLocalizedString("This action cannot be undone.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Remove note(s)", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        alert.beginSheetModal(for: window) { (returnCode: NSApplication.ModalResponse) in
            if returnCode == NSApplication.ModalResponse.alertFirstButtonReturn {
                let selectedRow = vc.notesTableView.selectedRowIndexes.min()
                vc.editArea.clear()
                vc.storage.removeNotes(notes: notes) { _ in
                    DispatchQueue.main.async {
                        vc.storageOutlineView.reloadSidebar()
                        vc.notesTableView.removeByNotes(notes: notes)
                        if let i = selectedRow, i > -1 {
                            vc.notesTableView.selectRow(i)
                        }
                        if vc.getSidebarItem() == nil {
                            vc.storageOutlineView.selectRowIndexes([0], byExtendingSelection: false)
                            vc.notesTableView.selectRow(0)
                        }
                    }
                }
            } else {
                self.alert = nil
            }
        }
    }

    @objc func enableFSUpdates() {
        UserDataService.instance.fsUpdatesDisabled = false
    }

    @objc private func updateTableViews() {
        notesTableView.beginUpdates()
        for note in updateViews {
            notesTableView.reloadRow(note: note)

            if search.stringValue.count == 0 {
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

    private var selectRowTimer = Timer()

    func updateTable(search: Bool = false, searchText: String? = nil, sidebarItem: SidebarItem? = nil, projects: [Project]? = nil, completion: @escaping () -> Void = {}) {
        var sidebarItem: SidebarItem? = sidebarItem
        var projects: [Project]? = projects
        var sidebarName: String?

        let timestamp = Date().toMillis()

        self.search.timestamp = timestamp
        searchQueue.cancelAllOperations()

        if searchText == nil {
            projects = storageOutlineView.getSidebarProjects()
            sidebarItem = getSidebarItem()
            sidebarName = getSidebarItem()?.getName()
        }

        var filter = searchText ?? self.search.stringValue
        let originalFilter = searchText ?? self.search.stringValue
        filter = originalFilter.lowercased()

        var type = sidebarItem?.type

        // Global search if sidebar not checked
        if type == nil, projects == nil || (projects!.count < 2 && projects!.first!.isRoot) {
            type = .All
        }

        let operation = BlockOperation()
        operation.addExecutionBlock { [weak self] in
            guard let self = self else {
                return
            }

            if let projects = projects {
                for project in projects {
                    self.preLoadNoteTitles(in: project)
                }
            }

            let terms = filter.split(separator: " ")
            let source = self.storage.noteList
            var notes = [Note]()

            for note in source {
                if operation.isCancelled {
                    completion()
                    return
                }

                if self.isFit(note: note, filter: filter, terms: terms, projects: projects, type: type, sidebarName: sidebarName) {
                    notes.append(note)
                }
            }

            let orderedNotesList = self.storage.sortNotes(noteList: notes, filter: filter, project: projects?.first, operation: operation)

            // Check diff
            if self.filteredNoteList == notes, orderedNotesList == self.notesTableView.noteList {
                completion()
                return
            }

            self.filteredNoteList = notes
            self.notesTableView.noteList = orderedNotesList

            if operation.isCancelled {
                completion()
                return
            }

            guard self.notesTableView.noteList.count > 0 else {
                DispatchQueue.main.async {
                    self.editArea.clear()
                    self.notesTableView.reloadData()
                    completion()
                }
                return
            }

            let note = self.notesTableView.noteList[0]

            DispatchQueue.main.async {
                self.notesTableView.reloadData()
                if search {
                    if self.notesTableView.noteList.count > 0 {
                        if filter.count > 0, note.title.lowercased() == self.search.stringValue.lowercased() {
                            self.selectNullTableRow(timer: true)
                        } else {
                            self.editArea.clear()
                        }
                    } else {
                        self.editArea.clear()
                    }
                }
                completion()
            }
        }

        searchQueue.addOperation(operation)
    }

    /*
     Load titles in cases sort by Title
     */
    private func preLoadNoteTitles(in project: Project) {
        if UserDefaultsManagement.sort == .title || project.sortBy == .title {
            _ = storage.noteList.filter {
                $0.project == project
            }
        }
    }

    private func isMatched(note: Note, terms: [Substring]) -> Bool {
        for term in terms {
            if note.name.range(of: term, options: .caseInsensitive, range: nil, locale: nil) != nil || note.content.string.range(of: term, options: .caseInsensitive, range: nil, locale: nil) != nil {
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
            && (filter.isEmpty || isMatched(note: note, terms: terms!)
            ) && (
                type == .All && note.project.showInCommon
                    || (
                        type != .All && projects!.contains(note.project)
                            || (note.project.parent != nil && projects!.contains(note.project.parent!))
                    )
                    || type == .Trash
            ) && (
                type == .Trash && note.isTrash()
                    || type != .Trash && !note.isTrash()
            )
    }

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

    @objc func selectNullTableRow(timer: Bool = false) {
        if timer {
            selectRowTimer.invalidate()
            selectRowTimer = Timer.scheduledTimer(timeInterval: TimeInterval(0.2), target: self, selector: #selector(selectRowInstant), userInfo: nil, repeats: false)
            return
        }

        selectRowInstant()
    }

    @objc private func selectRowInstant() {
        notesTableView.selectRowIndexes([0], byExtendingSelection: false)
        notesTableView.scrollRowToVisible(0)
    }

    func focusEditArea(firstResponder: NSResponder? = nil) {
        guard EditTextView.note != nil else { return }
        var resp: NSResponder = editArea
        if let responder = firstResponder {
            resp = responder
        }

        if notesTableView.selectedRow > -1 {
            DispatchQueue.main.async {
                self.editArea.isEditable = true
                self.emptyEditAreaView.isHidden = true
                self.titleBarView.isHidden = false
                self.editArea.window?.makeFirstResponder(resp)
                self.editArea.restoreCursorPosition()
            }
            return
        }

        editArea.window?.makeFirstResponder(resp)
    }

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

    func focusTable() {
        DispatchQueue.main.async {
            let index = self.notesTableView.selectedRow > -1 ? self.notesTableView.selectedRow : 0
            self.notesTableView.window?.makeFirstResponder(self.notesTableView)
            self.notesTableView.selectRowIndexes([index], byExtendingSelection: true)
            self.notesTableView.scrollRowToVisible(row: index, animated: true)
        }
    }

    func cleanSearchAndEditArea() {
        search.stringValue = ""
        search.becomeFirstResponder()

        notesTableView.selectRowIndexes(IndexSet(), byExtendingSelection: false)
        editArea.clear()
    }

    func activeShortcut() {
        guard let mainWindow = MainWindowController.shared() else {
            return
        }

        if
            NSApplication.shared.isActive,
            !NSApplication.shared.isHidden,
            !mainWindow.isMiniaturized
        {
            NSApplication.shared.hide(nil)
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        mainWindow.makeKeyAndOrderFront(self)
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

    func createNote(name: String = "", content: String = "", type: NoteType? = nil, project: Project? = nil, load: Bool = false) {
        guard let vc = ViewController.shared() else { return }
        let selectedProjects = vc.storageOutlineView.getSidebarProjects()
        var sidebarProject = project ?? selectedProjects?.first
        let text = content

        if sidebarProject == nil {
            let projects = storage.getProjects()
            sidebarProject = projects.first
        }

        guard let project = sidebarProject else {
            return
        }

        let note = Note(name: name, project: project, type: type)
        note.content = NSMutableAttributedString(string: text)
        note.save()

        if let selectedProjects = selectedProjects, !selectedProjects.contains(project) {
            return
        }

        // 防止预览情况下新建preview标没有修改过来
        UserDefaultsManagement.preview = false
        DispatchQueue.main.async { [weak self] in
            self?.previewButton.state = UserDefaultsManagement.preview ? .on : .off
        }

        editArea.markdownView?.removeFromSuperview()
        editArea.markdownView = nil

        guard let editor = editArea else {
            return
        }
        editor.subviews.removeAll(where: { $0.isKind(of: MPreviewView.self) })
        notesTableView.deselectNotes()
        editArea.string = text
        EditTextView.note = note
        search.stringValue.removeAll()
        titleLabel.isEditable = true
        emptyEditAreaView.isHidden = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            vc.titleLabel.editModeOn()
        }

        updateTable {
            DispatchQueue.main.async {
                if let index = self.notesTableView.getIndex(note) {
                    self.notesTableView.selectRowIndexes([index], byExtendingSelection: false)
                    self.notesTableView.scrollRowToVisible(index)
                }
            }
        }

        Analytics.trackEvent("MiaoYan NewNote")
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

    func pin(_ selectedRows: IndexSet) {
        guard !selectedRows.isEmpty, let notes = filteredNoteList, var state = filteredNoteList else {
            return
        }

        var updatedNotes = [(Int, Note)]()
        for row in selectedRows {
            guard let rowView = notesTableView.rowView(atRow: row, makeIfNecessary: false) as? NoteRowView,
                  let cell = rowView.view(atColumn: 0) as? NoteCellView,
                  let note = cell.objectValue as? Note
            else {
                continue
            }

            updatedNotes.append((row, note))
            note.togglePin()
            cell.renderPin()
        }

        let resorted = storage.sortNotes(noteList: notes, filter: search.stringValue)
        let indexes = updatedNotes.compactMap { _, note in
            resorted.firstIndex(where: { $0 === note })
        }
        let newIndexes = IndexSet(indexes)

        notesTableView.beginUpdates()
        let nowPinned = updatedNotes.filter { _, note in
            note.isPinned
        }
        for (row, note) in nowPinned {
            guard let newRow = resorted.firstIndex(where: { $0 === note }) else {
                continue
            }
            notesTableView.moveRow(at: row, to: newRow)
            let toMove = state.remove(at: row)
            state.insert(toMove, at: newRow)
        }

        let nowUnpinned = updatedNotes
            .filter { _, note -> Bool in
                !note.isPinned
            }
            .compactMap { _, note -> (Int, Note)? in
                guard let curRow = state.firstIndex(where: { $0 === note }) else {
                    return nil
                }
                return (curRow, note)
            }
        for (row, note) in nowUnpinned.reversed() {
            guard let newRow = resorted.firstIndex(where: { $0 === note }) else {
                continue
            }
            notesTableView.moveRow(at: row, to: newRow)
            let toMove = state.remove(at: row)
            state.insert(toMove, at: newRow)
        }

        notesTableView.noteList = resorted
        notesTableView.reloadData(forRowIndexes: newIndexes, columnIndexes: [0])
        notesTableView.selectRowIndexes(newIndexes, byExtendingSelection: false)
        notesTableView.endUpdates()
        filteredNoteList = resorted
        Analytics.trackEvent("MiaoYan Pin")
    }

    func isMiaoYanPPT(needToast: Bool = true) -> Bool {
        guard let note = notesTableView.getSelectedNote() else {
            return false
        }

        let content = note.content.string
        if content.contains("---") {
            return true
        }

        if needToast {
            toast(message: NSLocalizedString("😶‍🌫 No delimiter --- identification, Cannot use MiaoYan PPT~", comment: ""))
        }

        return false
    }

    func toggleMagicPPT() {
        titleLabel.saveTitle()
        if !isMiaoYanPPT() {
            return
        }
        if UserDefaultsManagement.magicPPT {
            disableMiaoYanPPT()
        } else {
            enableMiaoYanPPT()
        }
    }

    func enableMiaoYanPPT() {
        guard let vc = ViewController.shared() else { return }

        let preparePresentation = {
            vc.enablePresentation()
            UserDefaultsManagement.magicPPT = true
            DispatchQueue.main.async {
                vc.titiebarHeight.constant = 0.0
                vc.handlePPTAutoTransition()
            }
        }

        if UserDefaultsManagement.presentation {
            disablePresentation()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: preparePresentation)
        } else {
            preparePresentation()
        }

        Analytics.trackEvent("MiaoYan PPT")
    }

    func handlePPTAutoTransition() {
        guard let vc = ViewController.shared() else { return }

        // 获取鼠标位置，自动跳转
        let range = editArea.selectedRange

        // 若 selectedIndex > editArea.string.count()，则使用 string.count() 的值。
        // 若最终计算结果为负，则采 0 值。
        let selectedIndex = max(min(range.location, editArea.string.count) - 1, 0)

        let beforeString = editArea.string[..<selectedIndex]
        let hrCount = beforeString.components(separatedBy: "---").count

        if UserDefaultsManagement.previewLocation == "Editing", hrCount > 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                // PPT场景下的自动跳转
                vc.editArea.markdownView?.slideTo(index: hrCount - 1)
            }
        }

        // 兼容快捷键透传
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            NSApp.mainWindow?.makeFirstResponder(vc.editArea.markdownView)
        }
    }

    func disableMiaoYanPPT() {
        disablePresentation()
        UserDefaultsManagement.magicPPT = false
        DispatchQueue.main.async {
            self.checkTitlebarTopConstraint()
        }
    }

    func getScrollTop() -> CGFloat {
        let contentHeight = editAreaScroll.contentSize.height
        let scrollTop = editAreaScroll.contentView.bounds.origin.y
        let scrollHeight = editAreaScroll.documentView!.bounds.height
        if scrollHeight - contentHeight > 0, scrollTop > 0 {
            return scrollTop / (scrollHeight - contentHeight)
        } else {
            return 0.0
        }
    }

    func enablePreview() {
        isFocusedTitle = titleLabel.hasFocus()
        cancelTextSearch()
        editArea.window?.makeFirstResponder(notesTableView)
        UserDefaultsManagement.preview = true
        refillEditArea()
        titleLabel.isEditable = false
        if UserDefaultsManagement.previewLocation == "Editing", !UserDefaultsManagement.isOnExport {
            let scrollPre = getScrollTop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.editArea.markdownView?.scrollToPosition(pre: scrollPre)
            }
        }
    }

    func disablePreview() {
        UserDefaultsManagement.preview = false
        UserDefaultsManagement.magicPPT = false
        UserDefaultsManagement.presentation = false

        editArea.markdownView?.removeFromSuperview()
        editArea.markdownView = nil

        guard let editor = editArea else {
            return
        }
        editor.subviews.removeAll(where: { $0.isKind(of: MPreviewView.self) })
        refillEditArea()
        DispatchQueue.main.async {
            self.titleLabel.isEditable = true
        }
        if !isFocusedTitle {
            focusEditArea()
        }
    }

    func togglePreview() {
        titleLabel.saveTitle()
        if UserDefaultsManagement.preview {
            disablePreview()
        } else {
            enablePreview()
            Analytics.trackEvent("MiaoYan Preview")
        }
    }

    func enablePresentation() {
        hideNoteList("")
        disablePreview()
        DispatchQueue.main.async {
            UserDefaultsManagement.presentation = true
            self.enablePreview()
        }
        if UserDefaultsManagement.fullScreen {} else {
            view.window?.toggleFullScreen(nil)
        }
        formatButton.isHidden = true
        previewButton.isHidden = true
        if !UserDefaultsManagement.isOnExportPPT {
            toast(message: NSLocalizedString("🙊 Press ESC key to exit~", comment: ""))
        }
    }

    func disablePresentation() {
        previewButton.state = .off
        UserDefaultsManagement.presentation = false
        UserDefaultsManagement.magicPPT = false
        DispatchQueue.main.async {
            self.checkTitlebarTopConstraint()
        }
        if UserDefaultsManagement.fullScreen {
            view.window?.toggleFullScreen(nil)
        }
        disablePreview()
        formatButton.isHidden = false
        previewButton.isHidden = false
        showSidebar("")
    }

    func togglePresentation() {
        titleLabel.saveTitle()
        if UserDefaultsManagement.presentation {
            disablePresentation()
        } else {
            enablePresentation()
            Analytics.trackEvent("MiaoYan Presentation")
        }
    }

    func formatText() {
        if UserDefaultsManagement.preview {
            toast(message: NSLocalizedString("😶‍🌫 Format is only possible after exiting preview mode~", comment: "")
            )
            return
        }
        if let note = notesTableView.getSelectedNote() {
            // 先保存一下标题，防止首次的时候
            titleLabel.saveTitle()
            // 最牛逼格式化的方式
            let formatter = PrettierFormatter(plugins: [MarkdownPlugin()], parser: MarkdownParser())
            formatter.prepare()
            let content = note.content.string
            let cursor = editArea.selectedRanges[0].rangeValue.location
            let top = editAreaScroll.contentView.bounds.origin.y
            let result = formatter.format(content, withCursorAtLocation: cursor)
            switch result {
            case .success(let formatResult):
                // 防止 Prettier 自动加空行
                var newContent = formatResult.formattedString
                if content.last != "\n" {
                    newContent = formatResult.formattedString.removeLastNewLine()
                }
                editArea.insertText(newContent, replacementRange: NSRange(0..<note.content.length))
                editArea.fill(note: note, highlight: true, saveTyping: true, force: false, needScrollToCursor: false)
                editArea.setSelectedRange(NSRange(location: formatResult.cursorOffset, length: 0))
                editAreaScroll.documentView?.scroll(NSPoint(x: 0, y: top))
                formatContent = newContent
                note.save()
                toast(message: NSLocalizedString("🎉 Automatic typesetting succeeded~", comment: ""))
            case .failure(let error):
                print(error)
            }

            Analytics.trackEvent("MiaoYan Format")
        }
    }

    func loadMoveMenu() {
        guard let vc = ViewController.shared(), let note = vc.notesTableView.getSelectedNote() else { return }

        let moveTitle = NSLocalizedString("Move", comment: "Menu")
        if let prevMenu = noteMenu.item(withTitle: moveTitle) {
            noteMenu.removeItem(prevMenu)
        }

        let moveMenuItem = NSMenuItem()
        moveMenuItem.title = NSLocalizedString("Move", comment: "Menu")

        noteMenu.addItem(moveMenuItem)
        let moveMenu = NSMenu()

        if !note.isTrash() {
            let trashMenu = NSMenuItem()
            trashMenu.title = NSLocalizedString("Trash", comment: "Sidebar label")
            trashMenu.action = #selector(vc.deleteNote(_:))
            trashMenu.tag = 555
            moveMenu.addItem(trashMenu)
            moveMenu.addItem(NSMenuItem.separator())
        }

        let projects = storage.getProjects()
        for item in projects {
            if note.project == item || item.isTrash {
                continue
            }

            let menuItem = NSMenuItem()
            menuItem.title = item.label
            menuItem.representedObject = item
            menuItem.action = #selector(vc.moveNote(_:))
            moveMenu.addItem(menuItem)
        }

        let personalSelection = [
            "noteMove.rename",
        ]

        for menu in noteMenu.items {
            if let identifier = menu.identifier?.rawValue,
               personalSelection.contains(identifier)
            {
                menu.isHidden = (vc.notesTableView.selectedRowIndexes.count > 1)
            }
        }

        noteMenu.setSubmenu(moveMenu, for: moveMenuItem)
    }

    func loadSortBySetting() {
        let viewLabel = NSLocalizedString("View", comment: "Menu")
        let sortByLabel = NSLocalizedString("Sort by", comment: "View menu")

        guard
            let menu = NSApp.menu,
            let view = menu.item(withTitle: viewLabel),
            let submenu = view.submenu,
            let sortMenu = submenu.item(withTitle: sortByLabel),
            let sortItems = sortMenu.submenu
        else {
            return
        }

        let sort = UserDefaultsManagement.sort

        for item in sortItems.items {
            if let id = item.identifier, id.rawValue == "SB.\(sort.rawValue)" {
                item.state = NSControl.StateValue.on
            }
        }
    }

    func registerKeyValueObserver() {
        let keyStore = NSUbiquitousKeyValueStore()

        NotificationCenter.default.addObserver(self, selector: #selector(ViewController.ubiquitousKeyValueStoreDidChange), name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: keyStore)

        keyStore.synchronize()
    }

    @objc func ubiquitousKeyValueStoreDidChange(notification: NSNotification) {
        if let keys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] {
            for key in keys {
                if key == "com.tw93.miaoyan.pins.shared" {
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
    }

    func checkSidebarConstraint() {
        if sidebarSplitView.subviews[0].frame.width < 50, !UserDefaultsManagement.isWillFullScreen {
            searchTopConstraint.constant = 25.0
            return
        }
        searchTopConstraint.constant = 11.0
    }

    func checkTitlebarTopConstraint() {
        if splitView.subviews[0].frame.width < 50, !UserDefaultsManagement.isWillFullScreen {
            titiebarHeight.constant = 64.0
            titleTopConstraint.constant = 30.0
            return
        }
        titiebarHeight.constant = 52.0
        titleTopConstraint.constant = 16.0
    }


    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        if splitView == sidebarSplitView && dividerIndex == 0 {
            return 0
        }
        
        if dividerIndex == 0 && UserDefaultsManagement.isSingleMode {
            return 0
        }
        return proposedMinimumPosition
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        if splitView == sidebarSplitView && dividerIndex == 0 {
            return 280
        }
        
        if dividerIndex == 0 && UserDefaultsManagement.isSingleMode {
            return 0
        }
        return proposedMaximumPosition
    }

    @IBAction func duplicate(_ sender: Any) {
        if let notes = notesTableView.getSelectedNotes() {
            for note in notes {
                guard let name = note.getDupeName() else {
                    continue
                }
                let noteDupe = Note(name: name, project: note.project, type: note.type)
                noteDupe.content = NSMutableAttributedString(string: note.content.string)

                // Clone images
                if note.type == .Markdown, note.container == .none {
                    let images = note.getAllImages()
                    for image in images {
                        move(note: noteDupe, from: image.url, imagePath: image.path, to: note.project, copy: true)
                    }
                }

                noteDupe.save()

                storage.add(noteDupe)
                notesTableView.insertNew(note: noteDupe)
            }
        }
    }

    @IBAction func noteCopy(_ sender: Any) {
        guard let fr = view.window?.firstResponder else {
            return
        }

        if fr.isKind(of: EditTextView.self) {
            editArea.copy(sender)
        }

        if fr.isKind(of: NotesTableView.self) {
            saveTextAtClipboard()
        }
    }

    @IBAction func copyURL(_ sender: Any) {
        if let note = notesTableView.getSelectedNote(), let title = note.title.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) {
            let name = "miaoyan://goto/\(title)"
            let pasteboard = NSPasteboard.general
            pasteboard.declareTypes([NSPasteboard.PasteboardType.string], owner: nil)
            pasteboard.setString(name, forType: NSPasteboard.PasteboardType.string)
            toast(message: NSLocalizedString("🎉 URL is successfully copied, Use it anywhere~", comment: ""))
        }
    }

    @IBAction func copyTitle(_ sender: Any) {
        if let note = notesTableView.getSelectedNote() {
            let pasteboard = NSPasteboard.general
            pasteboard.declareTypes([NSPasteboard.PasteboardType.string], owner: nil)
            pasteboard.setString(note.title, forType: NSPasteboard.PasteboardType.string)
        }
    }

    public func updateTitle(newTitle: String) {
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "MiaoYan"

        var titleString = newTitle

        if newTitle.isValidUUID {
            titleString = String()
        }
        titleLabel.stringValue = titleString

        titleLabel.currentEditor()?.selectedRange = NSRange(location: titleString.utf16.count, length: 0)

        MainWindowController.shared()?.title = appName
    }

    // MARK: Share Service

    @IBAction func toggleMagicPPT(_ sender: Any) {
        toggleMagicPPT()
    }

    @IBAction func togglePreview(_ sender: NSButton) {
        togglePreview()
    }

    @IBAction func togglePresentation(_ sender: NSButton) {
        togglePresentation()
    }

    @IBAction func formatText(_ sender: NSButton) {
        formatText()
    }

    func exportFile(type: String) {
        UserDefaultsManagement.isOnExport = true

        if type == "Html" {
            UserDefaultsManagement.isOnExportHtml = true
        }
        toast(message: NSLocalizedString("🙊 Starting export~", comment: ""))

        if UserDefaultsManagement.preview {
            disablePreview()
        }

        enablePreview()
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
            switch type {
            case "Image":
                self.editArea.markdownView?.exportImage()
            case "Html":
                self.editArea.markdownView?.exportHtml()
            case "PDF":
                self.editArea.markdownView?.exportPdf()
            default:
                print("Export no Type")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                UserDefaultsManagement.isOnExport = false
                if type == "Html" {
                    UserDefaultsManagement.isOnExportHtml = false
                }
                self.disablePreview()
            }
        }
        Analytics.trackEvent("MiaoYan Export", withProperties: ["Type": type])
    }

    @IBAction func exportImage(_ sender: Any) {
        exportFile(type: "Image")
    }

    @IBAction func exportHtml(_ sender: Any) {
        exportFile(type: "Html")
    }

    @IBAction func exportPdf(_ sender: Any) {
        exportFile(type: "PDF")
    }

    @IBAction func exportMiaoYanPPT(_ sender: Any) {
        if !isMiaoYanPPT() {
            return
        }
        toast(message: NSLocalizedString("🙊 Starting export~", comment: ""))
        enableMiaoYanPPT()
        UserDefaultsManagement.isOnExport = true
        UserDefaultsManagement.isOnExportPPT = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            self.editArea.markdownView?.exportPdf()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.disableMiaoYanPPT()
            }
        }
        Analytics.trackEvent("MiaoYan Export", withProperties: ["Type": "MiaoYan PPT PDF"])
    }

    public func toastExport(status: Bool) {
        if status {
            toast(message: NSLocalizedString("🎉 Saved to Downloads folder~", comment: ""))
        } else {
            toast(message: NSLocalizedString("😶‍🌫 PDF export failed, please try again~", comment: ""))
        }
        // After the export is completed, restore the original state.
        UserDefaultsManagement.isOnExport = false
        UserDefaultsManagement.isOnExportPPT = false
    }

    public func toastNoTitle() {
        toast(message: NSLocalizedString("😶‍🌫 Please make sure your title exists~", comment: ""))
    }

    public func toastMoreTitle() {
        toast(message: NSLocalizedString("🍭 Found that there are multiple titles of this~", comment: ""))
    }

    public func toastImageSet(name: String) {
        toast(message: String(format: NSLocalizedString("🙊 Please make sure your Mac is installed %@ ~", comment: ""), name))
    }

    public func toastUpload(status: Bool) {
        if status {
            toast(message: NSLocalizedString("🍭 Image upload in progress~", comment: ""))
        } else {
            toast(message: NSLocalizedString("😶‍🌫 Image upload failed, Use local~", comment: ""))
        }
    }

    public func saveTextAtClipboard() {
        if let note = notesTableView.getSelectedNote() {
            let pasteboard = NSPasteboard.general
            pasteboard.declareTypes([NSPasteboard.PasteboardType.string], owner: nil)
            pasteboard.setString(note.content.string, forType: NSPasteboard.PasteboardType.string)
        }
    }

    public func saveHtmlAtClipboard() {
        if let note = notesTableView.getSelectedNote() {
            if let render = renderMarkdownHTML(markdown: note.content.string) {
                let pasteboard = NSPasteboard.general
                pasteboard.declareTypes([NSPasteboard.PasteboardType.rtfd], owner: nil)
                pasteboard.setString(render, forType: NSPasteboard.PasteboardType.rtfd)
            }
        }
    }

    @IBAction func textFinder(_ sender: NSMenuItem) {
        guard let vc = ViewController.shared() else { return }

        if !vc.editAreaScroll.isFindBarVisible, [NSFindPanelAction.next.rawValue, NSFindPanelAction.previous.rawValue].contains(UInt(sender.tag)) {
            if UserDefaultsManagement.preview, vc.notesTableView.selectedRow > -1 {
                vc.disablePreview()
            }

            let menu = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            menu.tag = NSTextFinder.Action.showFindInterface.rawValue
            vc.editArea.performTextFinderAction(menu)
        }

        DispatchQueue.main.async {
            vc.editArea.performTextFinderAction(sender)
        }
    }

    func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
        for item in menu.items {
            if item.title == NSLocalizedString("Copy Link", comment: "") {
                item.action = #selector(NSText.copy(_:))
            }
        }

        return menu
    }

    func splitViewWillResizeSubviews(_ notification: Notification) {
        editArea.updateTextContainerInset()
    }
    
    func splitViewDidResizeSubviews(_ notification: Notification) {
        updateDividers()
    }

    public static func shared() -> ViewController? {
        guard let delegate = NSApplication.shared.delegate as? AppDelegate else {
            return nil
        }

        return delegate.mainWindowController?.window?.contentViewController as? ViewController
    }

    public func copy(project: Project, url: URL) -> URL {
        let fileName = url.lastPathComponent

        do {
            let destination = project.url.appendingPathComponent(fileName)
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        } catch {
            var tempUrl = url

            let ext = tempUrl.pathExtension
            tempUrl.deletePathExtension()

            let name = tempUrl.lastPathComponent
            tempUrl.deleteLastPathComponent()

            let now = DateFormatter().formatForDuplicate(Date())
            let baseUrl = project.url.appendingPathComponent(name + " " + now + "." + ext)

            try? FileManager.default.copyItem(at: url, to: baseUrl)

            return baseUrl
        }
    }

    public func replace(validateString: String, regex: String, content: String) -> String {
        do {
            let RE = try NSRegularExpression(pattern: regex, options: .caseInsensitive)
            let modified = RE.stringByReplacingMatches(in: validateString, options: .reportProgress, range: NSRange(location: 0, length: validateString.count), withTemplate: content)
            return modified
        } catch {
            return validateString
        }
    }
}
