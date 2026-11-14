// Sample articles, written in code so nothing is fetched. The first one is the lead story.
struct SampleArticleRepository: ArticleRepository {
    func articles() -> [Article] {
        [
            Article(
                id: "loud-clock", section: "Design", minutes: 4, author: "Nico Vale", posted: "Today",
                title: "The clock is the loudest thing on your phone",
                deck: "You look at it more than anything else. It should be the one place the screen is allowed to shout.",
                pull: "One loud thing, then quiet.",
                body: [
                    "Most phones set the time in the same neutral text they use for a settings row. It reads fine and says nothing. Because we check the clock so often, that quiet choice wastes the most valuable pixels on the screen.",
                    "Pocket OS sets the clock in a heavy rounded face, large enough to read across a room. The date beneath it is small and plain. The loud part is one word long, and everything around it gets to be calm.",
                    "We tried the opposite for a week: a calmer clock and a busier home screen. Nobody could say what time it was without looking twice.",
                ]
            ),
            Article(
                id: "grayscale", section: "Principles", minutes: 5, author: "Ana Reyes", posted: "Yesterday",
                title: "A grey operating system",
                deck: "Colour belongs to what you put on the phone, not to the phone itself.",
                pull: "The system is the frame. Your life is the picture.",
                body: [
                    "Count the colours on a typical home screen and you get a wall of small shouts, each tile designed to win the same square inch of attention. Nothing on it is more important than anything else.",
                    "Pocket OS draws its own chrome in greys. The status bar, the settings rows, the message list and the tiles it ships with all sit between near-black and near-white. When colour appears, it came from you: a photo, or a friend’s message with a heart in it.",
                    "The system keeps one warm colour for itself and uses it for a single meaning: this needs you. An unread dot, or the send button when there is something to send. Then it leaves.",
                ]
            ),
            Article(
                id: "serif-titles", section: "Type", minutes: 6, author: "Theo Park", posted: "Yesterday",
                title: "Why the titles have serifs",
                deck: "A serif in the title and a sans in the text make two voices. Three voices need a clear job for each.",
                pull: "A title should be recognisable at a glance.",
                body: [
                    "Pocket OS speaks in three voices. A heavy rounded face is the loudest: the clock, the marks on app tiles, the Reader masthead. A serif, in semibold and bold, carries titles, names and buttons. The system sans carries everything you read.",
                    "The serif has to stay pleasant at small sizes. Titles start at seventeen points, and below that the serif is kept for names only, so a line of body text never has to compete with it.",
                    "The rule is easy to say and hard to keep: a serif never sets a paragraph. If a paragraph wants to be a title, it is probably too important to be a title and should just be text.",
                ]
            ),
            Article(
                id: "nine-days", section: "Field notes", minutes: 7, author: "Ana Reyes", posted: "Monday",
                title: "Nine days on a bench phone",
                deck: "A bring-up diary: what rebooted, what worked, and what the speaker said when it finally played.",
                pull: "The first sound was a sine sweep. Everyone in the room stopped talking.",
                body: [
                    "The test phone has a cracked corner and the best-documented charging port in the building. Last week it ran a build for nine days without anyone touching it, the longest quiet stretch the bench has had.",
                    "The bring-up is written as a ladder of rungs. The first is a kernel that boots and stays up. Each later rung is something a person can watch: a screen we own, a status light, a flash driven by a script instead of a cable. The audio rung came last.",
                    "Most of what went wrong was not on the phone. A hub negotiated the wrong role depending on the host it sat on. A build machine’s clock drifted enough to confuse a signature. Nine days is not a product, but it is a good start.",
                ]
            ),
            Article(
                id: "assistant", section: "Software", minutes: 3, author: "Theo Park", posted: "Sunday",
                title: "An assistant that lives in Messages",
                deck: "Not a separate app and not a floating orb. A thread, pinned to the top, that answers.",
                pull: "It knows what you are reading, because you tell it.",
                body: [
                    "The assistant is a conversation in Messages. That is a small decision with large consequences: it has a place, a history and a face like everyone else you talk to, and asking it something costs what a text to a friend costs.",
                    "It can be interrupted. Stop halts an answer mid-sentence, and the words already written stay where they are. Leave the thread while it writes and the reply carries on in the background.",
                    "What it knows is deliberately narrow. It knows what is on this phone, and it knows an article only when you hand it over from Reader.",
                ]
            ),
        ]
    }
}
