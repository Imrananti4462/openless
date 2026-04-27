import AppKit

@MainActor
enum ApplicationMenu {
    static func install() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "OpenLess")
        appMenu.addItem(NSMenuItem(title: "Hide OpenLess", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h"))
        appMenu.items.last?.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit OpenLess", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        editItem.submenu = editMenu()
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")

        menu.addItem(menuItem("Undo", action: Selector(("undo:")), key: "z"))
        let redo = menuItem("Redo", action: Selector(("redo:")), key: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(redo)
        menu.addItem(.separator())

        menu.addItem(menuItem("Cut", action: #selector(NSText.cut(_:)), key: "x"))
        menu.addItem(menuItem("Copy", action: #selector(NSText.copy(_:)), key: "c"))
        menu.addItem(menuItem("Paste", action: #selector(NSText.paste(_:)), key: "v"))
        menu.addItem(menuItem("Delete", action: #selector(NSText.delete(_:)), key: ""))
        menu.addItem(.separator())
        menu.addItem(menuItem("Select All", action: #selector(NSText.selectAll(_:)), key: "a"))

        return menu
    }

    private static func menuItem(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = nil
        return item
    }
}
