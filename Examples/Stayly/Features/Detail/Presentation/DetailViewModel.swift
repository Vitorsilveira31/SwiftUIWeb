import SwiftUIWeb

/// A stay's page: its detail once loaded, the photo on show, and the reservation for the search the reader came from.
@MainActor @Observable
final class DetailViewModel {
  let stay: Stay
  /// The dates and guests the booking is for.
  let query: StaySearch
  private(set) var detail: StayDetail?
  private(set) var state: LoadState = .loading
  private(set) var photoIndex = 0
  private(set) var reservation: StayReservation?
  private(set) var reserveFailed = false
  private(set) var isReserving = false
  private let loader: any LoadStayDetailUseCase
  private let reserver: any ReserveStayUseCase
  private let session: StaySession

  init(stay: Stay, query: StaySearch, loadDetail: any LoadStayDetailUseCase, reserve: any ReserveStayUseCase, session: StaySession) {
    self.stay = stay
    self.query = query
    loader = loadDetail
    reserver = reserve
    self.session = session
  }

  /// The price for the nights of the booking; nil when it overflows an Int.
  var total: Int? { StayTerms.total(perNight: stay.pricePerNight, nights: query.nights) }

  func load() async {
    state = .loading
    do {
      detail = try await loader.execute(stayID: stay.id)
      photoIndex = 0
      state = .loaded
    } catch {
      state = .failed(FailureText.unreachable)
    }
  }

  func select(photo index: Int) {
    guard let photos = detail?.photos, photos.indices.contains(index) else { return }
    photoIndex = index
  }

  /// Books the stay once: the record goes to the API and the reservation to this session's trips.
  func reserve() async {
    guard reservation == nil, !isReserving else { return }
    isReserving = true
    reserveFailed = false
    defer { isReserving = false }
    do {
      let booked = try await reserver.execute(stay: stay, checkIn: query.checkIn, checkOut: query.checkOut, guests: query.guests)
      reservation = booked
      session.record(booked)
    } catch {
      reserveFailed = true
    }
  }
}
