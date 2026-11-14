/// Sample deck. Eight people, the same on every run.
struct SampleProfileRepository: ProfileRepository {
    func profiles() -> [Profile] {
        [
            Profile(n: 0, name: "Nora", age: 27, job: "Product designer at a small studio", miles: 3,
                    bio: "Sunday mornings are for the farmers market and a very slow crossword. Ask me about my fern collection.",
                    likesYou: true, interests: ["Design", "Ferns", "Tennis"]),
            Profile(n: 1, name: "Leo", age: 30, job: "Line cook", miles: 1,
                    bio: "I can debone a chicken and I will judge your playlist. Currently fermenting a hot sauce nobody asked for.",
                    likesYou: false, interests: ["Cooking", "Vinyl", "Cycling"]),
            Profile(n: 2, name: "Iris", age: 25, job: "Pediatric nurse", miles: 5,
                    bio: "Night shifts and early mornings. Good with dogs, bad at sitting still. Recommend me a podcast.",
                    likesYou: true, interests: ["Dogs", "Karaoke", "Yoga"]),
            Profile(n: 3, name: "Kai", age: 29, job: "Climbing instructor", miles: 8,
                    bio: "I spend most weekdays hanging off walls for a living. Weekends are long drives with questionable playlists.",
                    likesYou: false, interests: ["Climbing", "Road trips", "Camping"]),
            Profile(n: 4, name: "Ines", age: 31, job: "Architect", miles: 2,
                    bio: "I notice doorframes so you don't have to. Museum dates, bookstore detours and walks with no destination.",
                    likesYou: true, interests: ["Museums", "Books", "Wine"]),
            Profile(n: 5, name: "Dev", age: 28, job: "Software engineer", miles: 4,
                    bio: "Ship apps by day, board game nights by night. I will let you win at Catan. Once.",
                    likesYou: true, interests: ["Board games", "Running", "Ramen"]),
            Profile(n: 6, name: "Mina", age: 26, job: "Marine biologist", miles: 12,
                    bio: "Ask me about octopuses. I have slides. Beach cleanups count as a first date.",
                    likesYou: false, interests: ["Diving", "Surfing", "Photography"]),
            Profile(n: 7, name: "Theo", age: 32, job: "Jazz pianist", miles: 6,
                    bio: "I play standards at a downtown bar on Thursdays. Come for the music, stay for the bad puns.",
                    likesYou: false, interests: ["Jazz", "Coffee", "Film"]),
        ]
    }
}
