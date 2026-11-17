# October retro

Attendees: me, Priya, Sam, Lee from support

Support queue. Lee walked through the ticket trends for the last four weeks. Volume is down eleven percent overall, mostly because the login loop on older Android phones was fixed in the September patch. The two biggest remaining categories are people who cannot find where their exported photos went, and people confused by storage limits on the free plan. Lee wants a short help article for each before the holidays, and asked whether the export screen could say where files are saved. Nobody owns that yet; we agreed to revisit it at planning rather than pick it up now.

Metrics. Weekly active users grew about four percent, in line with the last two months. Day-one retention is flat. Sam pointed out that the share sheet is the most common way new people arrive, and that the landing page those links open has not changed since spring. Priya noted that conversion to the paid plan dipped slightly in the first week of October and recovered after the pricing page copy was reverted, so the experiment there is closed and the old copy stays.

Hiring. We have two final-round candidates for the mobile role. Sam and I will do the system design interviews next Tuesday and Wednesday. Priya is out on Thursday, so the debrief moves to Friday morning. We still want a designer for two days a week; Lee knows a contractor who did the support center refresh and will send an introduction.

Infrastructure. The image resizing workers ran out of memory twice during the Sunday peak. Priya bumped the instance size as a stopgap, which roughly doubles that line on the bill. The real fix is streaming the resize instead of loading whole files, which overlaps with any upload work. We wrote that down as an input for whoever looks at upload speed later, and did not assign it.

Design review process. Reviews have been sliding because the Thursday slot collides with the all-hands every other week. We are moving reviews to Tuesday afternoons, thirty minutes, with the doc shared a day ahead. Sam will update the calendar invite. Small changes can skip review if two people sign off in the channel.

App store. The October release passed review in one day. The screenshots are out of date and still show the old icon. Lee offered to redo them with the marketing template, and we said yes, low priority, any time before the next major release.

Billing. Priya gave a longer update on the payments migration. Webhooks are moved, and she is now double-writing invoices to both providers for a week to compare totals. The cutover is planned for the first week of November if the totals match. She asked everyone to avoid touching anything in the subscriptions code until then.

Testing. Our end-to-end suite takes twenty-two minutes and is flaky on the photo picker tests. We agreed to quarantine the two worst tests and open issues for them, and to look at running the suite in parallel shards. Sam will try sharding on a branch; it is not urgent.

Security. The yearly penetration test is booked for the second half of November. The vendor wants a staging environment with seeded accounts, a list of the public endpoints, and a contact who can answer questions during their working hours in Europe. Priya will prepare the environment because it touches billing. We also rotated the push notification keys after the vendor's reminder, and nothing broke.

Roadmap discussion. We spent a while on what the next quarter should look like. Sam argued for more time on reliability before new features, pointing at the resize outages and the flaky tests. Lee asked for small fixes that cut support tickets. We agreed the next planning meeting will start from a list of the top ten support issues and the reliability work, and that each of us brings one proposal written down beforehand instead of pitching in the room.

Community. Three people from the beta forum offered to translate the app into Portuguese, Polish and Vietnamese. We are happy to accept and will set up the translation tool account next month. Lee will reply on the forum with a thank-you and a rough timeline.

Misc. The office move is on November 18. Bring a box. The team lunch is on the Friday after the release.

Owner updates at the end:

- Onboarding redesign shipped to everyone on Oct 14. It's done; the permissions prompt change cut drop-off at that step by a third.

- Shared albums: invite links and the album feed work; I'm on notifications for new photos next.

- The home screen widget: I'm pausing that idea until next year. Parking it on purpose.
