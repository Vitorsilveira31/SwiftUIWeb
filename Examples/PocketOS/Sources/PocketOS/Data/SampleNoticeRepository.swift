// Sample notifications for the lock screen.
struct SampleNoticeRepository: NoticeRepository {
    func notices() -> [Notice] {
        [
            Notice(id: "nico", symbol: "message.fill", title: "Nico", body: "Can you push the build to the spare phone tonight? I want to see the lock screen.", time: "now", destination: .thread("nico")),
            Notice(id: "reader", symbol: "book.fill", title: "Reader", body: "New this morning: The clock is the loudest thing on your phone.", time: "12m", destination: .article("loud-clock")),
            Notice(id: "studio", symbol: "message.fill", title: "Studio Crew", body: "Ana: The lowercase g in the serif still looks heavy to me.", time: "1h", destination: .thread("studio")),
            Notice(id: "update", symbol: "gearshape.fill", title: "Pocket OS", body: "Pocket OS 1.0 is ready. It will install tonight while the phone charges.", time: "3h", destination: .app(.settings)),
        ]
    }
}
