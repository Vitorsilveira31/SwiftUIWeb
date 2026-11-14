import Foundation
import Testing
@testable import Stayly

struct StayDaysTests {
  @Test func aDayRoundTripsThroughItsDate() {
    #expect(StayDays.number(StayDays.date(day: 11_017)) == 11_017)
    #expect(StayDays.number(StayDays.date(day: 0)) == 0)
  }

  @Test func theCivilDateOfADayIsItsYearMonthAndDay() {
    let epoch = StayDays.civil(StayDays.date(day: 0))
    #expect(epoch.year == 1970 && epoch.month == 1 && epoch.day == 1)
    // 2000 is a leap year: day 11 017 is March the first, after the 29th of February.
    let leap = StayDays.civil(StayDays.date(day: 11_017))
    #expect(leap.year == 2000 && leap.month == 3 && leap.day == 1)
    let lastOfLeapFebruary = StayDays.civil(StayDays.date(day: 11_016))
    #expect(lastOfLeapFebruary.month == 2 && lastOfLeapFebruary.day == 29)
  }

  @Test func nightsAreTheDaysBetweenTheDates() {
    #expect(StayDays.nights(from: StayDays.date(day: 10), to: StayDays.date(day: 13)) == 3)
  }

  @Test func aStayIsAtLeastOneNight() {
    #expect(StayDays.nights(from: StayDays.date(day: 10), to: StayDays.date(day: 10)) == 1)
    #expect(StayDays.nights(from: StayDays.date(day: 12), to: StayDays.date(day: 10)) == 1)
  }

  @Test func aTimeZoneOffsetDoesNotMoveADateToAnotherDay() {
    let midnight = 10 * 86_400.0
    #expect(StayDays.number(Date(timeIntervalSince1970: midnight + 3 * 3_600)) == 10)
    #expect(StayDays.number(Date(timeIntervalSince1970: midnight - 3 * 3_600)) == 10)
    #expect(StayDays.nights(from: Date(timeIntervalSince1970: midnight - 3_600), to: StayDays.date(day: 12)) == 2)
  }

  @Test func ratingsAndDaysReadAsTheyAreShown() {
    #expect(StayFormat.rating(45) == "4.5")
    #expect(StayFormat.rating(30) == "3.0")
    #expect(StayFormat.day(StayDays.date(day: 11_017)) == "Mar 1")
    #expect(StayFormat.price(120) == "$120")
  }

  @Test func copyPluralizesNightsAndGuests() {
    #expect(StayCopy.nights(1) == "1 night")
    #expect(StayCopy.nights(3) == "3 nights")
    #expect(StayCopy.guests(1) == "1 guest")
    #expect(StayCopy.totalFor(240, nights: 2) == "$240 total for 2 nights")
  }
}
