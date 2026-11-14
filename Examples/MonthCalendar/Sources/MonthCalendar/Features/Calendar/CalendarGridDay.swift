import Foundation

// One cell of the month grid. Neighbouring-month days are part of the grid but are dimmed, so the grid always has the
// same six rows.
struct CalendarGridDay: Identifiable, Hashable, Sendable {
    let date: Date
    let isInMonth: Bool
    var id: Date { date }
}
