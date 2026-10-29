// Logic check for the app's pure model code: ledger dates, money text, tool-argument JSON,
// API decoding and the Activity filter. Built with plain swiftc on Linux by scripts/build-ledger.sh
// (SwiftUI isn't available there, so only Foundation-only files are compiled in). Not part of the app.
import Foundation

func check(_ condition: Bool, _ what: String) {
    guard condition else { fatalError("LOGIC CHECK FAILED: \(what)") }
}

// posted_at is local wall-clock time with no zone, and must round-trip exactly.
let stamp = "2026-10-11T09:15:00"
guard let date = LedgerDate.parse(stamp) else { fatalError("LOGIC CHECK FAILED: parse \(stamp)") }
check(LedgerDate.stamp(date) == stamp, "stamp round trip gave \(LedgerDate.stamp(date))")
check(LedgerDate.day(date) == "2026-10-11", "day")
check(LedgerDate.parse("2026-10-11") != nil, "date-only parse")
check(TransactionPeriod.allTime.range().from == nil, "all time is unbounded")

// Cents are exact; the sign comes from the direction.
check(Money.text(1999).contains("19.99"), "1999 cents")
check(Money.signed(1250, currency: "USD", direction: .expense).hasPrefix("−"), "expense sign")
check(Money.signed(1250, currency: "USD", direction: .transferIn).hasPrefix("+"), "transfer in sign")

// Typed amounts parse in the phone's number format (the check runs in en_US).
check(Money.parseAmount("12.5") == 12.5, "plain amount")
check(Money.parseAmount("1,234.50") == 1234.5, "grouped amount")
check(Money.parseAmount("") == nil && Money.parseAmount("abc") == nil, "not an amount")

// The Log Spending form becomes one upsert item; blanks and nil arguments are left out.
var draft = NewTransaction()
draft.amount = 12.5
draft.account = "Cash"
draft.merchant = " Corner store "
draft.category = "Food"
draft.date = date
check(draft.cents == 1250 && draft.isValid, "draft cents and validity")
draft.amount = 0.1 + 0.2
check(draft.cents == 30, "float noise rounds to the cent")
draft.amount = 12.5
let body = try JSONEncoder().encode(JSONValue.fields(["source": "ledger-ios", "items": [draft.item], "limit": 200, "skipped": nil]))
guard let object = try JSONSerialization.jsonObject(with: body) as? [String: Any],
      let item = (object["items"] as? [[String: Any]])?.first else { fatalError("LOGIC CHECK FAILED: body shape") }
check(object["skipped"] == nil && object["limit"] as? Int == 200, "nil arguments dropped")
check(item["posted_at"] as? String == stamp, "posted_at")
check(item["amount_cents"] as? Int == 1250 && item["direction"] as? String == "expense", "amount and direction")
check(item["merchant"] as? String == "Corner store" && item["note"] == nil && item["counter_account"] == nil, "trimmed and omitted fields")

// API answers decode with snake_case keys and raw-value directions.
let decoder = JSONDecoder()
decoder.keyDecodingStrategy = .convertFromSnakeCase
let rows = #"{"ok":true,"result":[{"id":1,"posted_at":"2026-10-11T09:15:00","account":"Cash","direction":"transfer_out","amount_cents":500,"currency":"USD","base_amount":5,"category":null,"merchant":null,"source":"web","reviewed":true}]}"#
let transactions = try decoder.decode(Envelope<[LedgerTransaction]>.self, from: Data(rows.utf8)).result ?? []
check(transactions.first?.direction == .transferOut && transactions.first?.amountCents == 500, "transaction decode")
let refused = #"{"ok":false,"error":"no receipt 9"}"#
check(try decoder.decode(Envelope<[LedgerTransaction]>.self, from: Data(refused.utf8)).error == "no receipt 9", "error envelope")
let worth = #"{"ok":true,"result":{"assets_cents":0,"liabilities_cents":2,"net_cents":-2,"unverified_count":0,"groups":[{"key":"cards","label":"Cards","total_cents":-2,"accounts":[{"id":3,"name":"Card","currency":"USD","transactions":4,"kind_resolved":"credit","is_liability":true,"verified":true,"latest_balance":{"as_of_date":"2026-10-01","cents":2},"drift_cents":0,"current_cents":2,"signed_cents":-2}]}]}}"#
let netWorth = try decoder.decode(Envelope<NetWorth>.self, from: Data(worth.utf8)).result
check(netWorth?.accounts.first?.latestBalance?.asOfDate == "2026-10-01", "net worth decode")

// A search is filtered on the phone, since search_transactions has no filters.
var filter = TransactionFilter()
filter.direction = .expense
check(!filter.matches(transactions[0]), "direction filter")
filter.direction = nil
filter.account = "Cash"
check(filter.matches(transactions[0]), "account filter")

// MARK: Category lists: the window, the rows and the paging behind "tap a category"

func month(_ label: String) -> CategoryPeriod {
    guard let period = CategoryPeriod(month: label) else { fatalError("LOGIC CHECK FAILED: month \(label)") }
    return period
}

// A month is [first day, first day of the next), by label, with no clock or time zone in it.
check(month("2026-10").from == "2026-10-01" && month("2026-10").to == "2026-11-01", "october window")
check(month("2026-12").to == "2027-01-01", "december rolls the year")
check(month("2026-01").from == "2026-01-01" && month("2028-02").to == "2028-03-01", "january and leap february")
for bad in ["2026-13", "2026-00", "2026-1", "26-10", "2026-10-01", "October", ""] {
    check(CategoryPeriod(month: bad) == nil, "\(bad) is not a month label")
}
check(CategoryPeriod(containing: "2026-10-31T23:59:59")?.month == "2026-10", "month of a stamp")
check(CategoryPeriod(containing: "2026-11-01")?.month == "2026-11", "month of a day")

// The phone's time zone decides which month "now" is, so check the same instant in three zones:
// 04:30 UTC on 1 Nov is still 31 Oct in Chicago, already 1 Nov in Kolkata and Auckland.
func calendar(_ zone: String) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    guard let timeZone = TimeZone(identifier: zone) else { fatalError("LOGIC CHECK FAILED: zone \(zone)") }
    calendar.timeZone = timeZone
    return calendar
}
func instant(_ text: String) -> Date {
    guard let date = try? Date(text, strategy: .iso8601) else { fatalError("LOGIC CHECK FAILED: instant \(text)") }
    return date
}
let chicago = calendar("America/Chicago"), kolkata = calendar("Asia/Kolkata"), auckland = calendar("Pacific/Auckland")
let monthEnd = instant("2026-11-01T04:30:00Z")
check(CategoryPeriod(containing: monthEnd, calendar: chicago).month == "2026-10", "chicago is still october")
check(CategoryPeriod(containing: monthEnd, calendar: kolkata).month == "2026-11", "kolkata is in november")
check(CategoryPeriod(containing: monthEnd, calendar: auckland).month == "2026-11", "auckland is in november")
let newYear = instant("2027-01-01T03:00:00Z")
check(CategoryPeriod(containing: newYear, calendar: chicago).month == "2026-12", "chicago new year's eve")
check(CategoryPeriod(containing: newYear, calendar: kolkata).month == "2027-01", "kolkata new year")
check(LedgerDate.day(monthEnd, timeZone: chicago.timeZone) == "2026-10-31", "day in chicago")
check(LedgerDate.day(monthEnd, timeZone: kolkata.timeZone) == "2026-11-01", "day in kolkata")
check(month("2026-10").isCurrent(now: monthEnd, calendar: chicago) && !month("2026-10").isCurrent(now: monthEnd, calendar: kolkata), "isCurrent follows the zone")
check(month("2026-10").title(locale: Locale(identifier: "en_US")) == "October 2026", "month title: \(month("2026-10").title(locale: Locale(identifier: "en_US")))")

// Activity's periods are windows of the same shape.
check(TransactionPeriod.thisMonth.range(now: monthEnd, calendar: chicago) == ("2026-10-01", "2026-11-01"), "this month in chicago")
check(TransactionPeriod.thisMonth.range(now: monthEnd, calendar: kolkata) == ("2026-11-01", "2026-12-01"), "this month in kolkata")
check(TransactionPeriod.lastMonth.range(now: instant("2027-01-15T12:00:00Z"), calendar: chicago) == ("2026-12-01", "2027-01-01"), "last month across the year")
check(TransactionPeriod.last90Days.range(now: monthEnd, calendar: chicago).from == "2026-08-02", "90 days back")
check(TransactionPeriod.month(month("2026-08")).range() == ("2026-08-01", "2026-09-01"), "a named month")
check(TransactionPeriod.forMonth(month("2026-10"), now: monthEnd, calendar: chicago) == .thisMonth, "current month reads as this month")
check(TransactionPeriod.forMonth(month("2026-10"), now: monthEnd, calendar: kolkata) == .lastMonth, "previous month reads as last month")
check(TransactionPeriod.forMonth(month("2026-08"), now: monthEnd, calendar: chicago) == .month(month("2026-08")), "older month stays named")

// Rows are in a month exactly when the server's text comparison says so, at both ends.
func row(_ id: Int, _ postedAt: String, category: String? = "Groceries", direction: String = "expense",
         cents: Int = 1000, base: Double? = nil, currency: String = "USD", account: String = "Cash") -> LedgerTransaction {
    let categoryJSON = category.map { "\"\($0)\"" } ?? "null"
    let baseJSON = base.map { "\($0)" } ?? "null"
    let json = #"{"id":\#(id),"posted_at":"\#(postedAt)","account":"\#(account)","direction":"\#(direction)","amount_cents":\#(cents),"currency":"\#(currency)","base_amount":\#(baseJSON),"category":\#(categoryJSON),"merchant":null,"source":"web","reviewed":true}"#
    guard let value = try? decoder.decode(LedgerTransaction.self, from: Data(json.utf8)) else { fatalError("LOGIC CHECK FAILED: row \(json)") }
    return value
}
let scope = CategoryScope(name: "Groceries", period: month("2026-10"))
// On a phone in Kolkata it is already November, so October reads as "Last month" in the menu;
// August is a named month. Either way the window is the scope's own, not the clock's.
let kolkataFilter = scope.activityFilter(now: monthEnd, calendar: kolkata)
check(kolkataFilter.category == "Groceries" && kolkataFilter.direction == .expense && kolkataFilter.period == .lastMonth, "scope filter")
check(kolkataFilter.period.range(now: monthEnd, calendar: kolkata) == ("2026-10-01", "2026-11-01"), "last month is the scope's month")
let named = CategoryScope(name: "Groceries", period: month("2026-08")).activityFilter(now: monthEnd, calendar: kolkata)
check(named.period == .month(month("2026-08")) && named.period.range() == ("2026-08-01", "2026-09-01"), "older month is a named window")
// Membership is tested against the named-month window, which doesn't depend on today's date.
var inMonth = TransactionFilter()
inMonth.category = "Groceries"
inMonth.direction = .expense
inMonth.period = .month(month("2026-10"))
check(inMonth.matches(row(1, "2026-10-01T00:00:00")), "first second is in")
check(inMonth.matches(row(2, "2026-10-31T23:59:59")), "last second is in")
check(!inMonth.matches(row(3, "2026-09-30T23:59:59")), "previous month is out")
check(!inMonth.matches(row(4, "2026-11-01T00:00:00")), "next month is out")
check(!inMonth.matches(row(5, "2026-10-15T12:00:00", category: "Food")), "other category is out")
check(!inMonth.matches(row(6, "2026-10-15T12:00:00", direction: "income")), "income is not spending")
check(scope.activityFilter(now: monthEnd, calendar: chicago).period == .thisMonth, "current month filter is this month")

// "(uncategorized)" is rows with no category; "Total" is every expense.
var none = CategoryScope(name: CategoryScope.uncategorized, period: month("2026-10")).activityFilter(now: monthEnd, calendar: kolkata)
check(none.category == "(uncategorized)", "uncategorized scope filter")
none.period = .month(month("2026-10"))
check(none.matches(row(7, "2026-10-15T12:00:00", category: nil)) && !none.matches(row(8, "2026-10-15T12:00:00")), "uncategorized rows")
let everything = CategoryScope(name: CategoryScope.total, period: month("2026-10"))
check(everything.category == nil && everything.title == "All spending", "total has no category")
var allSpending = everything.activityFilter(now: monthEnd, calendar: kolkata)
allSpending.period = .month(month("2026-10"))
check(allSpending.category == nil && allSpending.matches(row(9, "2026-10-15T12:00:00", category: "Food")), "total matches any category")

// A list's total adds up USD amounts, as category_breakdown does: base_amount, not the row's own currency.
let listed = TransactionList(rows: [
    row(10, "2026-10-02T10:00:00", cents: 1999, base: 19.99),
    row(11, "2026-10-03T10:00:00", cents: 30, base: 0.1 + 0.2),
    row(12, "2026-10-04T10:00:00", cents: 41000, base: 5.0, currency: "INR"),
    row(13, "2026-10-05T10:00:00", cents: 700, base: nil),
], isTruncated: false)
check(listed.totalCents == 1999 + 30 + 500 + 700, "list total was \(listed.totalCents)")

// The donut slice a tap lands on, counted in cents from the first slice.
let slices = [CategoryTotal(category: "A", count: 1, totalCents: 500), CategoryTotal(category: "B", count: 1, totalCents: 300),
              CategoryTotal(category: "C", count: 1, totalCents: 200)]
check(slices.category(atAngle: 0) == "A" && slices.category(atAngle: 499) == "A", "first slice")
check(slices.category(atAngle: 500) == "B" && slices.category(atAngle: 799) == "B", "second slice")
check(slices.category(atAngle: 800) == "C" && slices.category(atAngle: 999) == "C", "third slice")
check(slices.category(atAngle: 1000) == nil && slices.category(atAngle: -1) == nil, "outside the donut")

// The summary names the month its totals cover, and the lists use it.
let summaryJSON = #"{"from":"2026-10-01","to":"2026-11-01","income_cents":0,"expense_cents":5,"net_cents":-5,"transfers_excluded":0}"#
let summary = try decoder.decode(SpendingSummary.self, from: Data(summaryJSON.utf8))
check(summary.period == month("2026-10"), "summary period")

// Paging: list_transactions answers at most a page, newest first, with no offset. This stands in
// for it and checks nothing is lost, doubled or silently cut, including a tie across a page edge.
func fakeServer(_ all: [LedgerTransaction], pageSize: Int) -> (String?) async throws -> [LedgerTransaction] {
    let sorted = all.sorted { $0.postedAt > $1.postedAt }
    return { upper in Array(sorted.filter { upper == nil || $0.postedAt < upper! }.prefix(pageSize)) }
}
func rows(_ count: Int, tiedAround tie: ClosedRange<Int>? = nil) -> [LedgerTransaction] {
    let zone = TimeZone(identifier: "UTC") ?? .gmt
    let start = instant("2026-10-31T23:59:59Z")
    return (0..<count).map { index in
        let second = tie.map { $0.contains(index) ? $0.lowerBound : index } ?? index
        return row(index + 1, LedgerDate.stamp(start.addingTimeInterval(-Double(second)), timeZone: zone))
    }
}
func ids(_ list: TransactionList) -> [Int] { list.rows.map(\.id) }

let long = try await TransactionPaging.collect(upper: nil, fetch: fakeServer(rows(2500), pageSize: 1000))
check(!long.isTruncated && ids(long) == Array(1...2500), "2500 rows in three pages: got \(long.rows.count)")
let tied = try await TransactionPaging.collect(upper: nil, fetch: fakeServer(rows(1500, tiedAround: 995...1004), pageSize: 1000))
check(!tied.isTruncated && Set(ids(tied)) == Set(1...1500) && ids(tied).count == 1500, "ties across a page edge: got \(tied.rows.count)")
let exact = try await TransactionPaging.collect(upper: nil, fetch: fakeServer(rows(1000), pageSize: 1000))
check(!exact.isTruncated && exact.rows.count == 1000, "exactly one full page is not truncated")
let huge = try await TransactionPaging.collect(upper: nil, fetch: fakeServer(rows(6000), pageSize: 1000))
// Each later page starts with the row the page before ended on (to include rows tied with it), so
// five pages hold 5000 - 4 distinct rows.
check(huge.isTruncated && huge.rows.count == 4996 && Set(ids(huge)).count == 4996, "six thousand rows stop at five pages and say so: \(huge.rows.count)")
// Rows are one second apart from 23:59:59 down; those before 23:40:00 are the last 1300 of 2500.
let bounded = try await TransactionPaging.collect(upper: "2026-10-31T23:40:00", fetch: fakeServer(rows(2500), pageSize: 1000))
check(!bounded.isTruncated && bounded.rows.count == 1300 && bounded.rows.allSatisfy { $0.postedAt < "2026-10-31T23:40:00" },
      "the exclusive upper bound is kept across pages: got \(bounded.rows.count)")

// The widgets' own models decode what the API sends, the way the app's do (snake_case keys).
let widgetDecoder = JSONDecoder()
widgetDecoder.keyDecodingStrategy = .convertFromSnakeCase
let widgetSummary = try widgetDecoder.decode(
    WidgetSummary.self, from: Data(#"{"income_cents": 482000, "expense_cents": 130655, "net_cents": 1}"#.utf8))
check(widgetSummary.expenseCents == 130_655 && widgetSummary.incomeCents == 482_000, "widget summary")
let widgetBudgets = try widgetDecoder.decode([WidgetBudget].self, from: Data(#"""
[{"category": "Food", "period": "monthly", "period_label": "2026-10", "limit_cents": 2500, "spent_cents": 3000,
  "remaining_cents": -500, "pct_used": 120, "status": "over"},
 {"category": "Total", "period": "monthly", "limit_cents": 0, "spent_cents": 100, "remaining_cents": -100,
  "pct_used": null, "status": "ok"}]
"""#.utf8))
check(widgetBudgets[0].isOver && widgetBudgets[0].fraction == 1, "an over budget draws a full bar")
check(widgetBudgets[1].isTotal && widgetBudgets[1].fraction == 0 && widgetBudgets[1].percent == 0, "no limit draws empty")
let widgetRows = try widgetDecoder.decode([WidgetTransaction].self, from: Data(#"""
[{"id": 7, "posted_at": "2026-10-11T09:15:00", "account": "Savings", "direction": "transfer_in", "amount_cents": 500,
  "currency": "USD", "category": null, "merchant": null},
 {"id": 8, "posted_at": "2026-10-11T09:16:00", "account": "Savings", "direction": "expense", "amount_cents": 715,
  "currency": "EUR", "category": "Transport", "merchant": "Lyft"}]
"""#.utf8))
check(widgetRows[0].isTransfer && widgetRows[0].isMoneyIn && widgetRows[0].title == "Savings", "transfer row")
check(widgetRows[1].title == "Lyft" && !widgetRows[1].isMoneyIn, "expense row")
// The symbol's exact form depends on the locale ("$" on the phone, "US$" in this Linux run), so check its place.
let whole = WidgetMoney.text(130_655, whole: true)
check(whole.contains("1,307") && !whole.contains("."), "whole dollars: \(whole)")
let dollars = WidgetMoney.text(715)
check(dollars.first?.isNumber == false && dollars.contains("7.15"), "symbol first: \(dollars)")
let euros = WidgetMoney.text(715, currency: "EUR")
check(euros.first?.isNumber == false && euros.contains("€") && euros.contains("7.15"), "euro symbol first: \(euros)")
check(WidgetSnapshot.sample.limits.first?.isTotal == true, "the overall limit is listed first")
// With no overall limit the widgets lead with the worst category limit instead.
let noTotal = WidgetSnapshot(summary: widgetSummary, budgets: Array(widgetBudgets.prefix(1)), recent: [])
check(noTotal.overall == nil && noTotal.headline?.category == "Food", "no overall limit: headline is the first category")
check(noTotal.headline?.leftText.hasSuffix(" over") == true, "an over limit reads 'over': \(noTotal.headline?.leftText ?? "-")")
check(WidgetSnapshot.sample.headline?.isTotal == true && WidgetSnapshot.sample.headline?.leftText.hasSuffix(" left") == true,
      "an overall limit leads and reads 'left'")

// merchant_logo answers a PNG for a brand and {domain: null} for the rest.
let logoHit = try widgetDecoder.decode(
    MerchantLogo.self, from: Data(#"{"domain": "uber.com", "image_base64": "iVBORw0KGgo=", "mime_type": "image/png"}"#.utf8))
check(logoHit.domain == "uber.com" && logoHit.data?.count == 8, "logo decodes to its PNG bytes")
let logoMiss = try widgetDecoder.decode(MerchantLogo.self, from: Data(#"{"domain": null}"#.utf8))
check(logoMiss.domain == nil && logoMiss.data == nil, "no brand means no logo")

// A transfer's two legs name each other's account only in text; the route reads "from -> to" the same on both.
let accountNames = ["Visa 1234", "Splitwise", "Checking", "Card 1004", "Cash", "Friends"]
func leg(_ json: String) throws -> LedgerTransaction {
    try widgetDecoder.decode(LedgerTransaction.self, from: Data(json.utf8))
}
let alexOut = try leg(#"""
{"id": 2384, "posted_at": "2026-10-14T16:40:00", "account": "Visa 1234", "direction": "transfer_out", "amount_cents": 634,
 "currency": "USD", "merchant": "Dave's Hot Chicken for Alex", "category": "Splitwise"}
"""#)
let alexIn = try leg(#"""
{"id": 2383, "posted_at": "2026-10-14T16:40:00", "account": "Splitwise", "direction": "transfer_in", "amount_cents": 634,
 "currency": "USD", "merchant": "Alex", "category": "Visa 1234"}
"""#)
let cardOut = try leg(#"""
{"id": 2377, "posted_at": "2026-10-12T15:20:00", "account": "Checking", "direction": "transfer_out", "amount_cents": 199,
 "currency": "USD", "merchant": "Card 1004", "category": "Credit card bill"}
"""#)
let cardIn = try leg(#"""
{"id": 2378, "posted_at": "2026-10-12T15:20:00", "account": "Card 1004", "direction": "transfer_in", "amount_cents": 199,
 "currency": "USD", "merchant": "Payment from Checking", "category": "Credit card payment"}
"""#)
let cashIn = try leg(#"""
{"id": 2063, "posted_at": "2026-10-04T14:11:00", "account": "Cash", "direction": "transfer_in", "amount_cents": 2191,
 "currency": "USD", "merchant": "Alex", "category": "Splitwise"}
"""#)
let plainExpense = try leg(#"""
{"id": 1, "posted_at": "2026-10-14T11:37:00", "account": "Visa 1234", "direction": "expense", "amount_cents": 500,
 "currency": "USD", "merchant": "Aarivi", "category": "Subscriptions"}
"""#)
let unknownLeg = try leg(#"""
{"id": 2, "posted_at": "2026-10-14T11:37:00", "account": "Visa 1234", "direction": "transfer_out", "amount_cents": 500,
 "currency": "USD", "merchant": "Someone", "category": "Friends and family"}
"""#)

let outRoute = TransferRoute(alexOut, accountNames: accountNames)
let inRoute = TransferRoute(alexIn, accountNames: accountNames)
check(outRoute?.from == "Visa 1234" && outRoute?.to == "Splitwise" && outRoute?.isOutgoing == true, "alex out leg route")
check(inRoute?.from == "Visa 1234" && inRoute?.to == "Splitwise" && inRoute?.isOutgoing == false, "alex in leg route")
check(TransferRoute(cardOut, accountNames: accountNames)?.to == "Card 1004", "checking pays card: to is card")
let cardInRoute = TransferRoute(cardIn, accountNames: accountNames)
check(cardInRoute?.from == "Checking" && cardInRoute?.to == "Card 1004" && cardInRoute?.counterparty == "Checking",
      "card in leg: from checking, to card")
check(TransferRoute(cashIn, accountNames: accountNames)?.from == "Splitwise", "cash in leg came from splitwise")
check(TransferRoute(plainExpense, accountNames: accountNames) == nil, "an expense has no route")
// A leg whose text names none of the known accounts gets no route (the row then says "Transfer · <account>").
check(TransferRoute(unknownLeg, accountNames: ["Visa 1234", "Splitwise"]) == nil, "no known account in the text: no route")

// Categories read as plain words; accounts and bookkeeping labels aren't categories; each shows once.
check(CategoryName.display("🚖 Transport") == "Transport", "emoji dropped: \(CategoryName.display("🚖 Transport"))")
check(CategoryName.display("Interest & fees") == "Interest & fees", "plain name kept")
check(CategoryName.display(CategoryScope.uncategorized) == "Uncategorized", "no category reads as a word")
check(!CategoryName.isSpendingCategory("Splitwise", accountNames: ["Splitwise", "Cash"]), "an account isn't a category")
check(!CategoryName.isSpendingCategory("Credit card bill", accountNames: []), "bookkeeping isn't a category")
check(CategoryName.isSpendingCategory("Food", accountNames: ["Cash"]), "food is a category")
check(CategoryName.unique(["Groceries", "🛒 Groceries", "Food"]) == ["Groceries", "Food"], "duplicates collapse to the first")

// A Siri / Shortcuts link fills Log Spending in; a bare link fills nothing.
let quickLink = URL(string: "ledger://add?amount=%2412.50&merchant=Starbucks&category=Food&account=visa%201234&type=income&date=2026-10-14")!
let quick = QuickLog.draft(from: quickLink)
check(quick?.cents == 1250 && quick?.merchant == "Starbucks" && quick?.category == "Food", "link amount, merchant, category")
check(quick?.account == "visa 1234" && quick?.direction == .income, "link account and type")
check(quick.map { LedgerDate.day($0.date) } == "2026-10-14", "link date")
check(QuickLog.draft(from: URL(string: "ledger://add")!) == nil, "a bare link fills nothing")
check(QuickLog.draft(from: URL(string: "ledger://home?amount=5")!) == nil, "only the add link fills the form")
check(QuickLog.amount("1,234.50") == 1234.5 && QuickLog.amount("abc") == nil && QuickLog.amount("0") == nil, "amount text")

// Server addresses: bare host:port or full URLs; anything else is no address.
check(ServerConfig.normalized("myserver.tail1234.ts.net:8448")?.absoluteString == "https://myserver.tail1234.ts.net:8448", "bare host gets https")
check(ServerConfig.normalized(" http://192.168.1.5:8098 ")?.port == 8098, "http and a port are kept")
check(ServerConfig.normalized("") == nil && ServerConfig.normalized(nil) == nil && ServerConfig.normalized("ftp://x") == nil, "not an address")

// MARK: Inventory and shopping list

// The inventory tool answers a bare array; a field that doesn't fit the status is null, and a status the
// app doesn't know yet decodes as .unknown instead of failing the whole list.
let inventoryRows = #"""
[
 {"item_key":"milk","unit":"gal","name":"whole milk","tracked":"auto","status":"running_low","last_bought":"2026-10-20","last_qty":1,
  "qty_left":0.2,"used_pct":83,"days_left":2,"lasts_days":12,"days_per_unit":12,"cycles":3,"last_price_cents":349,"last_price":3.49,"cheapest_merchant":"Corner Market"},
 {"item_key":"bread","unit":"each","name":"sandwich bread","tracked":"auto","status":"running_low","last_bought":"2026-10-24","last_qty":2,
  "qty_left":1,"used_pct":50,"days_left":1,"lasts_days":6,"days_per_unit":3,"cycles":5,"last_price_cents":289,"last_price":2.89,"cheapest_merchant":null},
 {"item_key":"eggs","unit":"each","name":"eggs large","tracked":"auto","status":"in_stock","last_bought":"2026-10-25","last_qty":12,
  "qty_left":9,"used_pct":25,"days_left":9,"lasts_days":14,"days_per_unit":1.17,"cycles":4,"last_price_cents":42,"last_price":0.42,"cheapest_merchant":null},
 {"item_key":"rice","unit":"lb","name":"jasmine rice","tracked":"auto","status":"used_up","last_bought":"2026-09-30","last_qty":5,
  "qty_left":0,"used_pct":100,"days_left":0,"lasts_days":30,"days_per_unit":6,"cycles":2,"last_price_cents":199,"last_price":1.99,"cheapest_merchant":"Corner Market"},
 {"item_key":"tea","unit":"each","name":"green tea","tracked":"auto","status":"learning","last_bought":"2026-10-22","last_qty":1,
  "qty_left":null,"used_pct":null,"days_left":null,"lasts_days":null,"days_per_unit":null,"cycles":0,"last_price_cents":null,"last_price":null,"cheapest_merchant":null},
 {"item_key":"lamp","unit":"each","name":"desk lamp","tracked":"off","status":"off","last_bought":"2026-08-02","last_qty":1,
  "qty_left":null,"used_pct":null,"days_left":null,"lasts_days":null,"days_per_unit":null,"cycles":0,"last_price_cents":null,"last_price":null,"cheapest_merchant":null},
 {"item_key":"salt","unit":"each","name":"sea salt","tracked":"auto","status":"once","last_bought":"2026-07-14","last_qty":1,
  "qty_left":null,"used_pct":null,"days_left":null,"lasts_days":null,"days_per_unit":null,"cycles":0,"last_price_cents":null,"last_price":null,"cheapest_merchant":null},
 {"item_key":"jam","unit":"each","name":"berry jam","tracked":"auto","status":"stale","last_bought":"2026-07-14","last_qty":1,
  "qty_left":null,"used_pct":null,"days_left":null,"lasts_days":null,"days_per_unit":null,"cycles":0,"last_price_cents":null,"last_price":null,"cheapest_merchant":null}
]
"""#
let inventory = try decoder.decode([InventoryItem].self, from: Data(inventoryRows.utf8))
let milk = inventory[0]
check(inventory.count == 8, "inventory rows")
check(milk.status == .runningLow && milk.daysLeft == 2 && milk.id == "milk|gal", "running low item: \(milk.status) \(milk.id)")
check(milk.qtyLeft == 0.2 && milk.lastPriceCents == 349 && milk.cheapestMerchant == "Corner Market", "milk numbers and merchant")
check(inventory[4].status == .learning && inventory[4].qtyLeft == nil && inventory[4].daysLeft == nil, "learning item has nulls")
check(inventory[7].status == .unknown, "a status the app doesn't know decodes as unknown")

// Row text: quantity with its unit (a counted item has none), days left, how long a purchase lasts.
check(milk.leftText == "0.2 gal left", "left text: \(milk.leftText ?? "nil")")
check(inventory[2].leftText == "9 left", "counted left text: \(inventory[2].leftText ?? "nil")")
check(inventory[3].leftText == "Used up", "used up left text")
check(milk.daysLeftText == "~2 days left" && inventory[1].daysLeftText == "~1 day left", "days left text")
check(inventory[3].daysLeftText == nil && inventory[4].daysLeftText == nil, "no days left for used up or learning")
check(milk.lastsText == "lasts ~12 days" && inventory[4].lastsText == nil, "lasts text")
check(milk.usedFraction == 0.83 && inventory[3].usedFraction == 1 && inventory[4].usedFraction == 0, "usage bar fraction")

// Sections, in the order the screen shows them; running low leads with what runs out first.
let groups = InventorySection.groups(inventory)
check(groups.map(\.section) == [.runningLow, .inStock, .usedUp, .learning, .notTracked], "section order: \(groups.map(\.section))")
check(groups[0].items.map(\.itemKey) == ["bread", "milk"], "running low sorted by days left")
check(groups[4].items.map(\.itemKey) == ["lamp", "salt", "jam"], "off, once and unknown sit under Not tracked")
check(InventorySection.groups(Array(inventory[2...2])).map(\.section) == [.inStock], "empty sections are left out")

// Track / Don't track: off and once-bought items can be switched on, followed items off; lapsed come back by themselves.
check(inventory[5].canTrack && inventory[6].canTrack && !milk.canTrack, "track is offered for off and once")
check(milk.canStopTracking && inventory[4].canStopTracking && !inventory[5].canStopTracking, "don't track is offered for followed items")

// Quantities read without noise.
check(Quantity.text(1.0, unit: "gal") == "1 gal" && Quantity.text(0.25, unit: "lb") == "0.25 lb", "measured quantity")
check(Quantity.text(3, unit: "each") == "×3" && Quantity.text(2, unit: nil) == "×2", "counted quantity")

let shoppingRows = #"""
{"items":[
 {"id":4,"item_key":"milk","unit":"gal","name":"whole milk","qty":1,"source":"rule","reason":"Running low: about 2 days left",
  "last_price_cents":349,"last_price":3.49,"cheapest_merchant":"Corner Market"},
 {"id":7,"item_key":"eggs","unit":"each","name":"eggs large","qty":12,"source":"ai","reason":"You go through a dozen a week",
  "last_price_cents":42,"last_price":0.42,"cheapest_merchant":null},
 {"id":9,"item_key":null,"unit":null,"name":"Birthday candles","qty":null,"source":"user","reason":null,
  "last_price_cents":null,"last_price":null,"cheapest_merchant":null},
 {"id":10,"item_key":null,"unit":null,"name":"Glue","qty":2,"source":"robot","reason":null,
  "last_price_cents":null,"last_price":null,"cheapest_merchant":null}],
 "total_cents":853,"total":8.53,
 "ai":{"last_run_at":"2026-10-29T14:03:07.123Z","ok":true,"message":null,"pending":false}}
"""#
let shopping = try decoder.decode(ShoppingList.self, from: Data(shoppingRows.utf8))
check(shopping.items.count == 4 && shopping.totalCents == 853, "shopping list decode")
check(shopping.ai.pending == false && shopping.ai.ok == true && shopping.ai.lastRunAt == "2026-10-29T14:03:07.123Z", "ai status decode")
check(shopping.items[0].source == .rule && shopping.items[1].source == .ai && shopping.items[2].source == .user, "sources")
check(shopping.items[3].source == .unknown, "an unknown source decodes as unknown")
check(shopping.items[2].isOwner && !shopping.items[0].isOwner, "only the owner's own rows are removed; the rest are dismissed")
check(shopping.items[0].qtyText == "1 gal" && shopping.items[1].qtyText == "×12" && shopping.items[2].qtyText == nil, "shopping qty text")
// The currency symbol depends on the locale ("US$" in this Linux run), so check what follows it.
check(shopping.items[0].priceHint?.hasSuffix("3.49/gal · cheapest at Corner Market") == true, "price hint: \(shopping.items[0].priceHint ?? "nil")")
check(shopping.items[1].priceHint?.hasSuffix("0.42/each") == true && shopping.items[1].priceHint?.contains("cheapest") == false,
      "price hint without a merchant: \(shopping.items[1].priceHint ?? "nil")")
check(shopping.items[2].priceHint == nil, "no price, no hint")
check(shopping.items[0].displayName == "Whole Milk" && shopping.items[2].displayName == "Birthday candles", "the owner's names stay as typed")
check(shopping.estimatedTotalCents == 853, "estimated total")
check(ShoppingList(items: Array(shopping.items[2...3]), totalCents: 0, ai: shopping.ai).estimatedTotalCents == nil, "nothing priced: no total")

// The footer under the list, from the AI run's status.
guard let ranAt = try? Date("2026-10-29T14:03:07Z", strategy: .iso8601) else { fatalError("LOGIC CHECK FAILED: parse run time") }
let afterRun = ranAt + 2 * 3600 + 60
check(shopping.ai.footer(now: afterRun) == "Updated by Claude 2 h ago", "updated footer: \(shopping.ai.footer(now: afterRun))")
check(shopping.ai.footer(now: ranAt + 30) == "Updated by Claude just now", "just now")
func footer(_ json: String) throws -> String {
    try decoder.decode(ShoppingList.AIStatus.self, from: Data(json.utf8)).footer(now: afterRun)
}
check(try footer(#"{"last_run_at":null,"ok":null,"message":null,"pending":false}"#) == "Rules only", "no key: rules only")
check(try footer(#"{"last_run_at":"2026-10-29T14:03:07.123Z","ok":false,"message":"Claude unavailable","pending":false}"#)
      == "Rules only: Claude unavailable", "a failed run says why")
check(try footer(#"{"last_run_at":"2026-10-29T14:03:07.123Z","ok":false,"message":null,"pending":false}"#) == "Rules only", "a failed run with no message")
check(try footer(#"{"last_run_at":"2026-10-29T14:03:07.123Z","ok":true,"message":null,"pending":true}"#) == "Updating…", "pending wins")
check(try footer(#"{"last_run_at":"2026-10-29T14:03:07Z","ok":true,"message":null,"pending":false}"#) == "Updated by Claude 2 h ago", "no fractional seconds")
check(try footer(#"{"last_run_at":"nonsense","ok":true,"message":null,"pending":false}"#) == "Updated by Claude", "an unreadable time is left out")

// What the add field sends: a trimmed name, a quantity only when given; blanks send nothing.
let newItem = NewShoppingItem(name: "  Paper towels ", qty: 2)
check(newItem.isValid && NewShoppingItem(name: "   ").isValid == false && NewShoppingItem(name: "Soap", qty: 0).isValid == false, "new item validity")
let addBody = try JSONSerialization.jsonObject(with: JSONEncoder().encode(JSONValue.fields(["add": .array([newItem.json, NewShoppingItem(name: "Soap").json])]))) as? [String: Any]
let added = addBody?["add"] as? [[String: Any]]
check(added?.count == 2 && added?[0]["name"] as? String == "Paper towels" && added?[0]["qty"] as? Double == 2, "add body: name and qty")
check(added?[1]["name"] as? String == "Soap" && added?[1]["qty"] == nil, "add body: qty left out")

// set_item_tracking needs an explicit null to go back to automatic; a missing key is refused.
let trackBody = try JSONSerialization.jsonObject(with: JSONEncoder().encode(JSONValue.fields(["tracked": .null, "unit": "gal"]))) as? [String: Any]
check(trackBody?["tracked"] is NSNull && trackBody?["unit"] as? String == "gal", "null is sent as null")

print("LOGIC OK")
