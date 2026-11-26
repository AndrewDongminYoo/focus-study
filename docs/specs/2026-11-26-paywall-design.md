# Paywall and trial offer design

Date: 2026-11-26.
Status: approved on 2026-11-26, implemented under issue #247.
Source: [issue #246](https://github.com/AndrewDongminYoo/focus-study/issues/246), under the paid build parent #244.
Authority: the [paid unlock decision](2026-11-24-paid-unlock-decision.md) (decisions 3 to 7 and "Behavior at the edges") and the [paid access design](2026-11-24-paid-access-design.md), which this document amends in [Amendment of the paid access design](#amendment-of-the-paid-access-design).
Look: the tokens of the [screen redesign](2026-11-23-screen-redesign-design.md) and the sheet layout of the [weekly review](2026-11-25-weekly-review-design.md) form A; there is no Figma frame.
This document changes no code.
The implementation is issue #247, and it starts after this design is approved.

Items marked "(writing session's call)" were not discussed with the user. They are defaults that the approval of this document can change.

## Intent

The student meets this screen at one moment: the student tapped the start action to focus now, and the app has no paid access for the student.
So the screen answers that action, not a tour of features.
It is a trial offer, not a sales pitch.

When the student closes it, one thought is enough: "I can try it, and if it does not fit, I just do not buy it."
A student who does not start the trial still leaves knowing that the everyday app and website blocking stays free.

The best first moment of the trial is the focus session that the student was about to start, so a trial started from the start action continues into that session.

## Goals

- The student sees that nothing is charged automatically before the student sees the price.
- The student sees, before the trial starts, the trial length, the features that need a purchase after it, and the price of the lifetime unlock (Guideline 3.1.1). None of them is in a small footnote.
- A trial or a purchase confirmed from the start action continues into the session that the student tapped.
- Closing the screen changes nothing: the everyday layer and its settings stay as they are.

## Non-goals

- A tour of the paid features, previews of the 순공 calendar or the weekly review, or screenshots.
- A subscription, a discount, a countdown or any other price pressure.
- A paywall for earlier users. A person whose first download is a build before the first paid build never sees this screen (decision 6).

## Anti-goals

The screen fails, also when it works, if:

- the student reads it as "I wanted to study and the app asks me to pay first";
- the student finds the price before finding that nothing is charged automatically;
- the screen suggests that closing it removes or changes the everyday blocking;
- a timer starts that the student did not expect, such as after a purchase approved later, or after a trial started from the calendar.

## Access and the start are separate

**Unlocked access and permission to start the session tapped earlier are two different things.**
A confirmed trial or purchase opens access. Only the flow that the start action opened, and only a success confirmed inside that flow, also continues the start.

## Contract

Proposed on 2026-11-26:

1. **Entries.**
   - **Start entry**: the start action on the idle screen with access `locked`. This is the only entry that holds a start request.
     It includes every path that the start action opens the paywall from, such as the access recovery tap and the recheck in `performStart()` (writing session's call).
   - **Other entries**: the locked card of the 순공 calendar ("구매하기"), and any later entry that is not the start action. They hold no start request.
2. **Layout, from top to bottom.** A card layout like the weekly review form A, in which the reassurance band is the darkest element.
   1. The close control "나중에" at the top right.
   2. The colon mark.
   3. The title "집중 타이머를 3일 동안 무료로 써보세요".
   4. Only for the start entry: "무료 체험을 시작하면, 하려던 N분 집중이 이어져요.", where N is the student's focus length. The other entries show no such line.
   5. The reassurance band, the most prominent element after the title: a navy band (`FocusNavy` fill, `FocusCream` text, accent check marks) with two lines:
      - "체험이 끝나도 자동으로 결제되지 않아요."
      - "구매하지 않아도 평소 앱·웹사이트 제한은 계속 쓸 수 있어요."
   6. A card: the label "3일이 지나면 구매가 필요해요", the list "집중 타이머와 휴식", "순공 캘린더", "주간 회고와 공유 이미지", then a row "평생권 구매" with the store price, and "구독이 아니에요. 한 번 사면 계속 써요."
   7. At the bottom: the primary button "3일 무료로 써보기", the secondary button `평생권 {price} 구매하기`, and a small "구매 복원".
3. **After the trial was used** (the trial ended or a trial purchase exists):
   - The title is "3일 체험이 끝났어요".
   - Only for the start entry: "평생권을 구매하면, 하려던 N분 집중이 이어져요." (writing session's call for the wording, by the same rule).
   - The band holds "구매하지 않아도 평소 앱·웹사이트 제한은 계속 쓸 수 있어요." and "지금까지의 기록은 기기에 그대로 있어요." (writing session's call, from "Behavior at the edges" of the decision).
   - The card label is "평생권으로 다시 쓸 수 있어요", with the same list and price rows.
   - The trial button is absent, and `평생권 {price} 구매하기` is the primary button.
4. **Price.**
   - The price is the store's `displayPrice` for the unlock, never a constant in code. "₩14,000" in this document's discussion was an example.
   - While the price is not on the screen, the price rows show that it is loading, "3일 무료로 써보기" and the purchase button are disabled, and a retry loads the price again.
   - "나중에" and "구매 복원" stay enabled.
5. **Start entry: continuing the start.**
   - The start entry holds the start request that the tap made.
   - When a trial start or a purchase succeeds inside this sheet and access then reads `granted`, the sheet closes and the app runs the existing start path once for that request, with every check that the start path already has (Screen Time access, selection, focus length, a session already running).
   - The request is dropped, and no session starts, when:
     - the student closes the sheet with "나중에" or a swipe;
     - the student cancels the purchase;
     - the purchase is pending (Ask to Buy) or fails;
     - access is opened by a restore ("구매 복원");
     - access is opened by anything outside this sheet's own trial or purchase, such as a transaction from `Transaction.updates`.
   - **A pending purchase that is approved later opens access only.** The timer does not start; the student taps the start action again.
6. **Restore.** A restore opens access and closes the sheet; it never continues a start. The student taps the start action again.
7. **Other entries.** A trial or purchase from the 순공 calendar's locked card returns to the calendar with the same month, the same selected day and the same scroll position, now showing the unlocked calendar. There is no start line and no timer.
   Every other end of that paywall ("나중에", a swipe, a cancel, a failure, a pending purchase, a restore) also returns to the same calendar, locked or unlocked as access then reads (writing session's call: the student came from the calendar and stays there).
8. **Closing.** "나중에" and a swipe close the sheet and change nothing else: no start, and no change to the everyday layer or its settings.

## Look

- Sheet at the large detent, `FocusCanvas` background, `FocusCard` cards, as the weekly review form A.
- Light: the band is `FocusNavy` with `FocusCream` text and accent check marks; the primary button is `AccentColor` `#AE5519` with white text; small accent text uses `AccentText` `#985019`.
- Dark: the canvas is navy, so the band is a darker navy with an accent border (writing session's call, the same answer as the weekly review note card); the primary button is `AccentColor` `#F4A64A` with `FocusNavy` text.
- Every text uses a text style and scales. At an accessibility text size the sheet scrolls, and the buttons stay at the bottom of the content, reachable by scrolling.
- Captures for approval: light, dark and the largest accessibility text size, for the start entry before the trial, the calendar entry before the trial, and the state after the trial; and one capture of the price loading state.

## Tests

The one test that must exist: start action → purchase pending → close with "나중에" → the purchase is approved later → access reads `granted` and no session starts.

Also (writing session's call):

- start entry, trial confirmed → one session starts with the student's length;
- start entry, purchase confirmed → one session starts;
- start entry, "나중에", swipe, cancel or failure → no session;
- start entry, restore → access opens and no session starts;
- calendar entry, trial confirmed → the calendar shows the same month and day, unlocked, and no session starts;
- the price not loaded → trial and purchase disabled, "나중에" and restore enabled;
- the start line shows only for the start entry.

## Amendment of the paid access design

Contract item 5 replaces the paid access design's rule that no session starts by itself after a purchase; its [amendment of 2026-11-26](2026-11-24-paid-access-design.md#amendment-of-2026-11-26) names the two sections it changes.

## Left to the builder

- How the screen model holds the start request and how the sheet reports a confirmed trial or purchase, inside the existing `PaidAccessStore` and `FocusModel` boundaries.
- How the calendar keeps its month, selected day and scroll position while the paywall shows, given that the idle screen presents one `.sheet(item:)`.
- The copy of the messages for a failed purchase, a pending purchase and a restore with nothing to restore, by the `user-facing-copy` rules; the current temporary sheet's behavior for these cases stays.
- Accessibility identifiers: keep `paywall`, `paywallClose`, `paywallTrial`, `paywallPurchase`, `paywallRestore`, `paywallMessage` and `paywallPriceRetry`, which the current sheet sets; new ones are the builder's.
- Whether the colon mark is the app's existing `ColonMark` view.

## Builder decisions of issue #247

- The start request: `FocusModel` keeps a `PaywallRequest` that the start action, the access recovery tap and the recheck in `performStart()` create. The sheet marks it confirmed after its own trial or purchase returns `confirmed` while access reads `granted`, and the sheet's close (`dismissPaywall()`) then runs `requestStart()` once, so the start keeps every check of the start path.
- The report: `PaidAccessStore.startTrial()` and `purchaseUnlock()` return a `PaidActionResult`. The result is `confirmed` only when the action's own verified transaction opens access; a transaction that does not, such as a trial that already ended, returns `notGranted`, also when another transaction opened access meanwhile. While the sheet's own action runs, access that opens does not close the sheet by itself, so the confirmation always comes before the close. Access that opens in any other way, such as an approval from `Transaction.updates` or a restore, closes the sheet without a confirmation.
- Contract item 5 is read literally: a pending purchase, a cancel or a failure drops the start request at that moment, and the start line goes away. A trial or purchase that succeeds later in the same sheet opens access and starts nothing.
- Leaving the foreground drops the start request of an open paywall, as it cancels a reserved start; the sheet stays open, and a trial or purchase confirmed after the return opens access and starts nothing.
- The calendar entry: the paywall shows as a sheet over the 순공 calendar sheet, so the month, the selected day and the scroll position stay as they are. That paywall holds no start request and never reaches the model.
- The sheet keeps its form, before or after the trial, only while its own trial, purchase or restore runs and while it closes after one, so a confirmed trial does not change the text during the close. At all other times the form follows the facts that the store confirms, also when they arrive after the sheet opened.
- Every result of the sheet carries the id of the start request that the sheet opened for, so a result that arrives after that sheet closed never reaches a later request. "나중에" drops the start request before the sheet closes, and a swipe cannot close the sheet while its own action runs, so a result that arrives during the close starts nothing.
- The colon mark is the existing `ColonMark` on a navy tile, as on the review explanation, because its cream ring does not show on the light canvas.
- The messages for a failed purchase, a failed trial start, a pending purchase and a restore with nothing to restore keep the copy of the temporary sheet.
- New accessibility identifiers: `paywallTitle`, `paywallStartLine`, `paywallPrice` and `paywallPriceLoading`.
