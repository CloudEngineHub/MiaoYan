import Carbon
import Cocoa

@MainActor
class NotesTableView: NSTableView {
    @MainActor
    private final class Adapter: NSObject, @preconcurrency NSTableViewDataSource, NSTableViewDelegate {
        unowned let owner: NotesTableView

        init(owner: NotesTableView) {
            self.owner = owner
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            owner.makeRowView(for: row)
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            owner.noteList.count
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            owner.heightForRow(row)
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            owner.handleSelectionChange(notification)
        }

        func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
            owner.objectValue(forRow: row)
        }

        func tableView(_ tableView: NSTableView, writeRowsWith rowIndexes: IndexSet, to pboard: NSPasteboard) -> Bool {
            owner.writeRows(rowIndexes: rowIndexes, to: pboard)
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            owner.viewForRow(row)
        }
    }

    private lazy var adapter = Adapter(owner: self)
    var noteList = [Note]()
    var defaultCell = NoteCellView()
    var pinnedCell = NoteCellView()
    var storage = Storage.sharedInstance()

    public var loadingQueue = OperationQueue()
    public var fillTimestamp: Int64?

    override func draw(_ dirtyRect: NSRect) {
        dataSource = adapter
        delegate = adapter
        backgroundColor = Theme.backgroundColor
        super.draw(dirtyRect)
    }

    override func keyUp(with event: NSEvent) {
        guard let vc = window?.contentViewController as? ViewController else {
            super.keyUp(with: event)
            return
        }

        if EditTextView.note != nil, event.keyCode == kVK_Tab, !event.modifierFlags.contains(.control), !UserDefaultsManagement.preview {
            vc.focusEditArea()
            vc.editArea.updateTextContainerInset()
        }

        if event.keyCode == kVK_LeftArrow, !UserDefaultsManagement.magicPPT {
            if let fr = window?.firstResponder, fr.isKind(of: NSTextView.self) {
                super.keyUp(with: event)
                return
            }

            vc.storageOutlineView.window?.makeFirstResponder(vc.storageOutlineView)
            let index = vc.storageOutlineView.selectedRow
            vc.storageOutlineView.selectRowIndexes([index], byExtendingSelection: false)
            deselectNotes()
        }

        if event.keyCode == kVK_RightArrow, !UserDefaultsManagement.magicPPT {
            if let fr = window?.firstResponder, fr.isKind(of: NSTextView.self) {
                super.keyUp(with: event)
                return
            }

            if selectedRow == -1 && !noteList.isEmpty {
                selectRowIndexes([0], byExtendingSelection: false)
            }

            if EditTextView.note != nil {
                vc.focusEditArea()
                vc.editArea.updateTextContainerInset()
            }
        }

        if event.keyCode == kVK_Escape {
            if let fr = window?.firstResponder, fr === self {
                vc.storageOutlineView.window?.makeFirstResponder(vc.storageOutlineView)
                let index = vc.storageOutlineView.selectedRow
                vc.storageOutlineView.selectRowIndexes([index], byExtendingSelection: false)
                deselectNotes()
            }
        }

        super.keyUp(with: event)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        true
    }

    func scrollRowToVisible(row: Int, animated: Bool) {
        if animated {
            guard let clipView = superview as? NSClipView,
                let scrollView = clipView.superview as? NSScrollView
            else {
                assertionFailure("Unexpected NSTableView view hiearchy")
                return
            }

            let rowRect = rect(ofRow: row)
            var scrollOrigin = rowRect.origin

            if clipView.frame.height - scrollOrigin.y < rowRect.height {
                scrollOrigin.y -= 8.0
                if scrollView.responds(to: #selector(NSScrollView.flashScrollers)) {
                    scrollView.flashScrollers()
                }
                clipView.animator().setBoundsOrigin(scrollOrigin)
            } else {
                scrollRowToVisible(row)
            }
        } else {
            scrollRowToVisible(row)
        }
    }

    override func mouseDown(with event: NSEvent) {
        UserDataService.instance.searchTrigger = false
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let vc = window?.contentViewController as? ViewController else { return }

        if vc.titleLabel.hasFocus() || vc.editArea.hasFocus() || vc.search.hasFocus() {
            vc.notesTableView.window?.makeFirstResponder(vc.notesTableView)
        }

        UserDataService.instance.searchTrigger = false

        let point = convert(event.locationInWindow, from: nil)
        let i = row(at: point)

        if noteList.indices.contains(i) {
            DispatchQueue.main.async {
                let selectedRows = self.selectedRowIndexes
                if !selectedRows.contains(i) {
                    self.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
                    self.scrollRowToVisible(i)
                    return
                }
            }
            super.rightMouseDown(with: event)
        }
    }

    private func makeRowView(for row: Int) -> NSTableRowView? {
        NoteRowView()
    }

    private func heightForRow(_ row: Int) -> CGFloat {
        if row < noteList.count {
            let note = noteList[row]
            note.dealContent()
        }
        return CGFloat(52)
    }

    private func handleSelectionChange(_ notification: Notification) {
        let timestamp = Date().toMillis()
        fillTimestamp = timestamp

        let vc = window?.contentViewController as! ViewController

        if let pendingChange = UserDataService.instance.pendingTitleChange {
            let title = pendingChange.title
            let note = pendingChange.note
            if !title.isEmpty && note.getFileName() != title {
                vc.saveTitle(title, to: note)
            }
            UserDataService.instance.pendingTitleChange = nil
        }

        if vc.editAreaScroll.isFindBarVisible {
            let menu = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            menu.tag = NSTextFinder.Action.hideFindInterface.rawValue
            vc.editArea.performTextFinderAction(menu)
        }

        if UserDataService.instance.isNotesTableEscape {
            UserDataService.instance.isNotesTableEscape = false

            if vc.storageOutlineView.selectedRow != -1 {
                vc.storageOutlineView.deselectAll(nil)
            }

            vc.editArea.clear()
            return
        }

        if noteList.indices.contains(selectedRow) {
            let note = noteList[selectedRow]

            if let currentNote = EditTextView.note, currentNote != note, !UserDefaultsManagement.preview {
                vc.editArea.saveTextStorageContent(to: currentNote)
                currentNote.save()
            }

            saveScrollPosition()

            loadingQueue.cancelAllOperations()
            let operation = BlockOperation()
            operation.addExecutionBlock { [weak self] in
                DispatchQueue.main.async {
                    guard !operation.isCancelled, self?.fillTimestamp == timestamp else {
                        return
                    }
                    // Avoid filling during note creation to prevent content flashing
                    if UserDataService.instance.shouldBlockEditAreaUpdate() {
                        return
                    }
                    vc.editArea.fill(note: note, options: .silent)
                }
            }
            loadingQueue.addOperation(operation)
        } else {
            vc.editArea.clear()
        }
    }

    private func objectValue(forRow row: Int) -> Any? {
        if noteList.indices.contains(row) {
            return noteList[row]
        }
        return nil
    }

    private func writeRows(rowIndexes: IndexSet, to pboard: NSPasteboard) -> Bool {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: rowIndexes, requiringSecureCoding: false) {
            let type = NSPasteboard.PasteboardType(rawValue: "notesTable")
            pboard.declareTypes([type], owner: self)
            pboard.setData(data, forType: type)
        }

        return true
    }

    private func selectedRowSafe() -> Int {
        if Thread.isMainThread { return selectedRow }
        var value = -1
        DispatchQueue.main.sync { value = self.selectedRow }
        return value
    }

    private func selectedRowIndexesSafe() -> IndexSet {
        if Thread.isMainThread { return selectedRowIndexes }
        var value = IndexSet()
        DispatchQueue.main.sync { value = self.selectedRowIndexes }
        return value
    }

    func getNoteFromSelectedRow() -> Note? {
        var note: Note?
        let selected = selectedRowSafe()

        if selected < 0 {
            return nil
        }

        if noteList.indices.contains(selected) {
            note = noteList[selected]
        }

        return note
    }

    func getSelectedNote() -> Note? {
        var note: Note?
        let row = selectedRowSafe()
        if noteList.indices.contains(row) {
            note = noteList[row]
        }
        return note
    }

    func getSelectedNotes() -> [Note]? {
        var notes = [Note]()

        let rows = selectedRowIndexesSafe()
        for row in rows where noteList.indices.contains(row) {
            notes.append(noteList[row])
        }

        if notes.isEmpty {
            return nil
        }

        return notes
    }

    public func deselectNotes() {
        deselectAll(nil)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if [kVK_ANSI_8, kVK_ANSI_J].contains(Int(event.keyCode)), event.modifierFlags.contains(.command) {
            return true
        }

        if event.modifierFlags.contains(.control), event.keyCode == kVK_Tab {
            return true
        }

        if event.keyCode == kVK_ANSI_M, event.modifierFlags.contains(.command), event.modifierFlags.contains(.shift) {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    private func viewForRow(_ row: Int) -> NSView? {
        guard noteList.indices.contains(row) else {
            return nil
        }

        let note = noteList[row]
        if note.isPinned {
            pinnedCell = makeCell(note: note)
            pinnedCell.pin.frame.size.width = 23
            return pinnedCell
        }

        defaultCell = makeCell(note: note)
        defaultCell.pin.frame.size.width = 0
        return defaultCell
    }

    func makeCell(note: Note) -> NoteCellView {
        let cell = makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "NoteCellView"), owner: self) as! NoteCellView

        cell.configure(note: note)
        cell.attachHeaders(note: note)

        return cell
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        if clickedRow > -1, selectedRow < 0 {
            selectRowIndexes([clickedRow], byExtendingSelection: false)
        }

        if selectedRow < 0 {
            return
        }

        guard let vc = window?.contentViewController as? ViewController else {
            return
        }
        vc.loadMoveMenu()
    }

    func getIndex(_ note: Note) -> Int? {
        if let index = noteList.firstIndex(where: { $0 === note }) {
            return index
        }
        return nil
    }

    func selectNext() {
        UserDataService.instance.searchTrigger = false

        selectRow(selectedRow + 1)
    }

    func selectPrev() {
        UserDataService.instance.searchTrigger = false

        selectRow(selectedRow - 1)
    }

    func selectRow(_ i: Int) {
        if noteList.indices.contains(i) {
            DispatchQueue.main.async {
                self.selectRowIndexes([i], byExtendingSelection: false)
                self.scrollRowToVisible(i)
            }
        }
    }

    func setSelected(note: Note) {
        if let i = getIndex(note) {
            selectRow(i)
            scrollRowToVisible(i)
        }
    }

    func removeByNotes(notes: [Note]) {
        for note in notes {
            if let i = noteList.firstIndex(where: { $0 === note }) {
                let indexSet = IndexSet(integer: i)
                noteList.remove(at: i)
                removeRows(at: indexSet, withAnimation: .slideDown)
            }
        }
    }

    @objc public func unDelete(_ urls: [URL: URL]) {
        for (src, dst) in urls {
            do {
                if let note = storage.getBy(url: src) {
                    storage.removeBy(note: note)
                }

                try FileManager.default.moveItem(at: src, to: dst)
            } catch {
                AppDelegate.trackError(error, context: "NotesTableView.reloadRow")
            }
        }
    }

    public func countVisiblePinned() -> Int {
        var i = 0
        for note in noteList where note.isPinned {
            i += 1
        }
        return i
    }

    public func insertNew(note: Note) {
        guard let vc = window?.contentViewController as? ViewController else {
            return
        }

        let at = countVisiblePinned()
        noteList.insert(note, at: at)
        vc.filteredNoteList?.insert(note, at: at)

        beginUpdates()
        insertRows(at: IndexSet(integer: at), withAnimation: .effectFade)
        reloadData(forRowIndexes: IndexSet(integer: at), columnIndexes: [0])
        endUpdates()
    }

    override func keyDown(with event: NSEvent) {
        if UserDefaultsManagement.magicPPT {
            return
        }
        let vc = window?.contentViewController as? ViewController
        if event.modifierFlags.contains(.control),
            !event.modifierFlags.contains(.option), event.modifierFlags.contains(.shift), event.keyCode == kVK_ANSI_P
        {
            vc?.exportPdf(self)
            return
        }

        if event.modifierFlags.contains(.control), !event.modifierFlags.contains(.option), event.modifierFlags.contains(.shift), event.keyCode == kVK_ANSI_I {
            vc?.exportImage(self)
            return
        }

        if event.modifierFlags.contains(.option), event.modifierFlags.contains(.control), event.modifierFlags.contains(.shift), event.keyCode == kVK_ANSI_P {
            vc?.exportMiaoYanPPT(self)
            return
        }

        if let vc = window?.contentViewController as? ViewController {
            if !vc.keyDown(with: event) {
                super.keyDown(with: event)
            }
        } else {
            super.keyDown(with: event)
        }
    }

    public func reloadRow(note: Note) {
        let storedTitle = note.title

        note.invalidateCache()
        if note.title.isEmpty && !storedTitle.isEmpty {
            note.title = storedTitle
        }

        guard let row = noteList.firstIndex(where: { $0 === note }) else {
            reloadData()
            return
        }

        reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: 0))
    }

    // MARK: - Scroll Position Memory
    func saveScrollPosition() {
        guard let clipView = superview as? NSClipView else { return }
        let scrollPosition = clipView.bounds.origin.y
        UserDefaultsManagement.notesTableScrollPosition = scrollPosition
    }

    func restoreScrollPosition() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                let clipView = self.superview as? NSClipView
            else { return }
            let savedPosition = UserDefaultsManagement.notesTableScrollPosition
            if savedPosition > 0 {
                let newOrigin = NSPoint(x: clipView.bounds.origin.x, y: savedPosition)
                clipView.setBoundsOrigin(newOrigin)
            }
        }
    }
}
