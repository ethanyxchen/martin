import Foundation
import SwiftUI
import Testing
@testable import Martin

struct NotesPageTests {
    @Test func stampReadsLikeAChatList() throws {
        let calendar = Calendar.current
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 15)))
        func ago(_ days: Int) -> Date { calendar.date(byAdding: .day, value: -days, to: now)! }
        #expect(ago(0).stamp(at: now) == ago(0).formatted(date: .omitted, time: .shortened))
        #expect(ago(1).stamp(at: now) == "Yesterday")
        #expect(ago(3).stamp(at: now) == ago(3).formatted(.dateTime.weekday(.wide)))
        #expect(ago(7).stamp(at: now) == ago(7).formatted(date: .numeric, time: .omitted))
    }

    @Test func settingsStaysInTheNavigationBarWhenEveryPageIsHidden() {
        #expect(HomePage.shown(hiding: Set(HomePage.allCases), on: .settings) == [.settings])
        #expect(HomePage.shown(hiding: [.upcoming], on: .notes) == [.notes, .projects, .settings])
    }

    @Test func aHiddenPageStaysInTheBarWhileItIsOpen() {
        #expect(HomePage.shown(hiding: [.upcoming], on: .upcoming) == HomePage.allCases)
    }
}

@MainActor
struct QuickNoteTests {
    @Test func commandNStartsAQuickNote() {
        #expect(QuickNoteButton.shortcut == KeyboardShortcut("n", modifiers: .command))
    }
}

@MainActor
struct ActionShortcutTests {
    @Test func onlyTheMenuBarCarriesTheArchiveSecretAndDeleteShortcuts() {
        #expect(ActionPlacement.menu.archive(enabled: true) == KeyboardShortcut("a", modifiers: [.command, .control]))
        #expect(ActionPlacement.menu.secret(enabled: true) == KeyboardShortcut("s", modifiers: [.command, .control]))
        #expect(ActionPlacement.menu.delete(enabled: true) == KeyboardShortcut(.delete, modifiers: [.command, .option]))
        #expect(ActionPlacement.contextMenu.archive(enabled: true) == nil)
        #expect(ActionPlacement.row.delete(enabled: true) == nil)
        #expect(ActionPlacement.contextMenu.secret(enabled: true) == nil)
    }

    @Test func aMenuWithNothingToActOnLeavesTheShortcutsToTheOther() {
        #expect(ActionPlacement.menu.archive(enabled: false) == nil)
        #expect(ActionPlacement.menu.delete(enabled: false) == nil)
        #expect(ActionPlacement.menu.secret(enabled: false) == nil)
    }
}

struct RowsTests {
    private struct Item: Identifiable { let id: Int }

    @Test func theDividerHidesBesideALitRow() {
        typealias List = Rows<Item, EmptyView>
        #expect(List.divides(2, below: 1, lit: [nil, nil]))
        #expect(List.divides(3, below: 2, lit: [1, nil]))
        #expect(!List.divides(2, below: 1, lit: [nil, 1]))
        #expect(!List.divides(2, below: 1, lit: [nil, 2]))
        #expect(!List.divides(2, below: 1, lit: [1, nil]))
    }
}
