import SwiftUI

/// One card of the deck. Its place comes from the deck index: -1 is parked where it was thrown, 0 the top (the only
/// card a finger moves), 1 the next, peeking out under it, and 2 hidden behind that.
struct DeckCard: View {
    let viewModel: SwipeDeckViewModel
    let profile: Profile
    let layout: DeckLayout
    /// The top card writes how far its drag has gone; the card under it reads it to grow.
    @Binding var dragProgress: CGFloat

    /// The live drag offset of the top card. It stays here until a release makes a decision.
    @State private var drag = CGSize.zero

    private var position: Int { profile.n - viewModel.state.index }
    private var photo: Int { viewModel.photo(for: profile.n) }
    private var isTop: Bool { position == 0 }
    private var lastDecision: Decision? { viewModel.lastDecision }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 18) }

    private var offset: CGSize {
        switch position {
        case 0:
            return drag
        case -1:
            // A thrown card rests off the stage in the direction it left.
            switch lastDecision {
            case .nope?: return CGSize(width: -layout.offX, height: viewModel.state.flungY)
            case .like?: return CGSize(width: layout.offX, height: viewModel.state.flungY)
            case .superLike?: return CGSize(width: 0, height: -layout.offY)
            case nil: return .zero
            }
        case 1:
            return CGSize(width: 0, height: 14 * (1 - dragProgress))
        default:
            return CGSize(width: 0, height: 14)
        }
    }

    /// The finger tilts the top card; a thrown card leaves at 20 degrees.
    private var tilt: Double {
        switch position {
        case 0:
            return Double(drag.width) * 0.06
        case -1:
            switch lastDecision {
            case .nope?: return -20
            case .like?: return 20
            default: return 0
            }
        default:
            return 0
        }
    }

    private var scale: CGFloat {
        if position <= 0 { return 1 }
        return position == 1 ? 0.94 + 0.06 * dragProgress : 0.94
    }

    // MARK: Stamps

    /// The stamps fade in with the drag. A drag that is mostly up shows only SUPER LIKE; otherwise the sideways
    /// stamp follows the finger.
    private var up: CGFloat { -drag.height }
    private var superDominates: Bool { up > abs(drag.width) }

    private func amount(_ distance: CGFloat) -> Double {
        Double(min(1, max(0, distance / (layout.cardWidth * 0.25))))
    }

    private var likeAmount: Double {
        switch position {
        case 0: return superDominates ? 0 : amount(drag.width)
        case -1: return lastDecision == .like ? 1 : 0
        default: return 0
        }
    }

    private var nopeAmount: Double {
        switch position {
        case 0: return superDominates ? 0 : amount(-drag.width)
        case -1: return lastDecision == .nope ? 1 : 0
        default: return 0
        }
    }

    private var superAmount: Double {
        switch position {
        case 0: return superDominates ? amount(up) : 0
        case -1: return lastDecision == .superLike ? 1 : 0
        default: return 0
        }
    }

    // MARK: Gestures

    /// Only the top card has this gesture. A short press is a tap (it pages the photos); a longer one moves the card.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                drag = value.translation
                dragProgress = layout.progress(for: value.translation)
            }
            .onEnded { value in
                release(value)
            }
    }

    /// A release throws the card when the drag or its flick is decisive; otherwise the card springs back.
    private func release(_ value: DragGesture.Value) {
        let verdict = Decision.verdict(
            x: value.translation.width,
            y: value.translation.height,
            flickX: value.predictedEndTranslation.width - value.translation.width,
            flickY: value.predictedEndTranslation.height - value.translation.height,
            throwAt: layout.throwAt)
        if let verdict {
            viewModel.send(.throwCard(verdict, releasedY: value.translation.height))
        }
        withAnimation(DeckMotion.spring) {
            drag = .zero
            dragProgress = 0
        }
    }

    // MARK: Body

    var body: some View {
        ZStack(alignment: .top) {
            Portrait(profile: profile, variant: photo, emblemSize: 170)
                .accessibilityLabel(Strings.Card.photoOf(profile.name))
            // A dark scrim keeps the white text readable over any portrait.
            LinearGradient(stops: [
                .init(color: .clear, location: 0.4),
                .init(color: .black.opacity(0.55), location: 0.7),
                .init(color: .black.opacity(0.9), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 0) {
                PhotoPips(count: Profile.photoCount, current: photo,
                          identifier: isTop ? "photo-pips" : "pips-\(profile.id)")
                HStack(spacing: 0) {
                    PhotoZone(identifier: isTop ? "photo-left" : "left-\(profile.id)",
                              label: Strings.Deck.previousPhoto) {
                        viewModel.send(.changePhoto(by: -1))
                    }
                    PhotoZone(identifier: isTop ? "photo-right" : "right-\(profile.id)",
                              label: Strings.Deck.nextPhoto) {
                        viewModel.send(.changePhoto(by: 1))
                    }
                }
                .frame(maxHeight: .infinity)
                CardInfo(profile: profile, isTop: isTop)
            }
        }
        .environment(\.colorScheme, .dark)
        .frame(width: layout.cardWidth, height: layout.cardHeight)
        .clipShape(shape)
        // The shadow sits behind the clipped card, so it is not cut away.
        .background {
            shape.fill(Color.gray).shadow(color: .black.opacity(0.18), radius: 14, y: 10)
        }
        .overlay(alignment: .topLeading) {
            Stamp(label: Strings.Verdict.like, color: .green, tilt: -16, amount: likeAmount,
                  identifier: isTop ? "stamp-like" : "like-\(profile.id)", isSuper: false)
                .padding(EdgeInsets(top: 48, leading: 22, bottom: 0, trailing: 0))
        }
        .overlay(alignment: .topTrailing) {
            Stamp(label: Strings.Verdict.nope, color: .red, tilt: 16, amount: nopeAmount,
                  identifier: isTop ? "stamp-nope" : "nope-\(profile.id)", isSuper: false)
                .padding(EdgeInsets(top: 48, leading: 0, bottom: 0, trailing: 22))
        }
        .overlay(alignment: .top) {
            Stamp(label: Strings.Verdict.superLike, color: .blue, tilt: -8, amount: superAmount,
                  identifier: isTop ? "stamp-super" : "super-\(profile.id)", isSuper: true)
                .padding(.top, 150)
        }
        .contentShape(shape)
        .gesture(dragGesture, including: isTop ? .all : .none)
        .scaleEffect(scale)
        .rotationEffect(.degrees(tilt))
        .offset(offset)
        .opacity(position >= 2 ? 0 : 1)
        .allowsHitTesting(isTop)
        .accessibilityLabel(Strings.Card.summary(profile.name, profile.age))
        .accessibilityIdentifier(isTop ? "card-top" : "card-\(profile.id)")
    }
}
