/// The prose of the studies, as fixture text. Each study has a wide and, where it matters, a narrow version.
enum WrapCopy {
    static let pullQuote = "Leave the empty patch alone; it is doing its work."
    static let articleQuote = "Letters kept the question open a little longer."

    static let drag = WrapText(wide: [
        "A stone skipping across shallow water leaves a small disturbance behind it. The current opens around a fallen branch, slows, and carries on as if nothing had been in the way. Writing can work like that. A sentence meets an obstacle and bends, and the reader hardly notices the detour.",
        "Take one of the circles and drop it into the middle of this page. The lines above and below it part to let it pass. Lift it again and they close behind, without a seam. Nothing has been deleted; the text has simply found another route through the same ideas.",
        "Good typesetting has always been a kind of hospitality. It leaves room for the eye to rest, for a thought to wander, for a neighbour to arrive. Even a page of plain paragraphs has quiet corners. Here the corners are made by you, and they can move whenever you like.",
        "Shapes behave differently from words. A circle is generous and asks for a clean edge all the way round. A rectangle is stubborn and keeps its corners. A polygon can point, and the text slides past the point like a small boat on a calm sea. Each kind of obstacle asks for a different kind of attention.",
        "We tend to picture reading as a straight line from the top left corner to the bottom right. Our eyes do not work that way. They jump, pause, return to a word they half remember, and skip ahead to see where a sentence is going. The text that follows the shapes is responding to that restlessness.",
    ], narrow: [
        "A stone moves through shallow water, and the current opens around it, then closes again. Take the circles for a walk. The words make room line by line, and the paragraph stays whole.",
        "Try the small disc near the top first. Then move the large one into the middle of a sentence and watch the gap appear.",
    ])

    static let orbs = WrapText(wide: [
        "By mid-morning the square was full of small journeys. A bicycle circled the fountain at a steady pace. Someone carried a bundle of flowers through a gap that had not been there a moment before. Pigeons settled, lifted, and settled again, as if following a plan nobody had written down.",
        "From an upstairs window these movements would look like a slow system of stars. Each person follows a private errand. Together they draw a pattern no one intended. When two paths meet there is a pause, a half turn, a small exchange of momentum, and then both continue along their own lines.",
        "We sat at a table near the door and watched the afternoon move through itself. Nothing repeated exactly, yet everything seemed to belong. The bodies in the square never stop; they only change direction. Even the space between them had a rhythm, and for a while we could hear it.",
        "Every few seconds one of them bumps another and both swerve. The text beside them does the same, rearranging its lines so that each collision is absorbed rather than ignored. Watch long enough and the paragraph seems to breathe along with the crowd.",
    ], narrow: [
        "The square fills with people. A bicycle circles the fountain; flowers pass through a gap that was not there a moment ago.",
        "Every journey follows a private errand. Together they draw a pattern no one planned. Two paths meet, turn, and begin again.",
    ])

    static let dancer = WrapText(wide: [
        "Before the music begins there is a moment of complete attention. She lifts her chin, finds the floor with the ball of one foot, and lets her arms settle. The room seems to lean toward her. Even the light has stopped to listen, and the audience holds its breath with her.",
        "The first movement is barely a movement. A shoulder turns. A hand describes a curve that the eye wants to finish for it. Then the knees soften and the whole figure opens, as though a breath could be seen from the far side of the room. Nothing happens alone: the wrist remembers the elbow, and the hip answers the foot.",
        "What stays with us is not any single pose but the passage between poses. A small hesitation before the turn. An arm that arrives a fraction later than expected. The empty air she leaves behind, still holding the outline of someone who has just moved on.",
        "The figure is built from separate pieces: a head, a bodice, a skirt that swings a beat behind the body, and limbs that meet at shared joints. Each piece is kept out of the text. When she bends, the paragraph bends with her.",
    ], narrow: [
        "Before the music begins, she lifts her chin and finds the floor with one foot. Even the light has stopped to listen.",
        "A shoulder turns. A hand describes a curve. The wrist remembers the elbow; the hip answers the foot.",
        "What stays is the passage between poses.",
    ])

    static let ball = WrapText(wide: [
        "The river was the first thing we heard in the morning: water moving over stone. Before the street had opened its shutters we went down with our coffee and stood for a while without finding anything that needed saying.",
        "A city is full of small agreements. A tree leans over a footpath and the people beneath it make room without thinking. A table appears outside a cafe and the conversation bends around it. Nothing has to vanish for something new to arrive.",
        "By noon a red ball had escaped from a child's hands and rolled across the square. A man lifted his bag out of its path. Two friends stepped apart, laughing, and came back together. For a moment the crowd was one living paragraph, opening a path for a single bright, improbable word.",
        "On the walk home the streets seemed wider, as though paying attention had made a little more room in the world. The ball kept rolling somewhere behind us, and the words kept making room for it.",
    ], narrow: [
        "The river was the first thing we heard in the morning: water moving over stone.",
        "A red ball rolled across the square. Two friends stepped apart, laughing, and came back together.",
        "The streets seemed wider on the walk home.",
    ])

    static let polygon = WrapText(wide: [
        "The map showed a road that ended at the sea. We followed it anyway. There were orchards on either side and low hills beyond them, and every bend revealed a little more sky. It was a journey that asked nothing except that we keep looking ahead.",
        "Near the coast the road narrowed to a path. Someone had painted an arrow on a stone. It pointed toward a gap in the grass where the wind had laid everything flat. We could hear the water before we could see it, and the sound seemed to rise from under the hill.",
        "An edge tells you where one place stops and another begins. The best edges are invitations, though: the margin of a page, the line of a shore, the threshold of a door left ajar. They give a shape to what we know and a direction to what we have not yet found.",
        "The triangle drifts across the column with one diagonal edge always facing the text. Where the edge is straight the words follow it exactly; where it meets a point they fold around it.",
    ], narrow: [
        "The map showed a road that ended at the sea. We followed it anyway.",
        "The best edges are invitations: the margin of a page, the line of a shore, a door left open.",
        "We came home by a different path.",
    ])

    static let editorialLeft = WrapText(wide: [
        "wilight settles on the garden before anyone notices. The visitors have gone, but the birds have not yet settled for the night. Every leaf holds a slightly different green, and the paths keep the last of the warmth.",
        "I used to think a garden was a collection of things. Now I think it is mostly a collection of spaces: the pause between two branches, the warm patch beside a wall, the bench that invites a person to stop measuring distance.",
    ])

    static let editorialRight = WrapText(wide: [
        "Across the path, lavender keeps the day's heat. The bees have left, but their work remains. Beyond it lies an open patch of earth where nothing grows yet.",
        "That empty patch is my favourite part. There is something generous about leaving room for what comes next. The gardener says planting is only half the work; the rest is knowing when to step back.",
    ])

    static let article = WrapText(wide: [
        "y grandmother and I wrote to each other for eleven years before either of us owned a telephone. The letters came on thin blue paper, folded twice, and they always arrived a day later than the postmark promised. I kept them in a shoebox under the bed, and when the box was full I started another.",
        "What I remember is not so much what the letters said as how long they took. A question asked in March was answered in April, by which time the question had changed, and so had the person asking it. The delay was part of the conversation. It made room for second thoughts, and for the kind of sentence you only write when nobody is waiting for it.",
        "Now answers arrive before a question has finished forming. That is a gift, mostly. But some evenings I take out the shoebox and read one of the old letters slowly, the way it was written, and let it take as long as it needs.",
    ])
}
