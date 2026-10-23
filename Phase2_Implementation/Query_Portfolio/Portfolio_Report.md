# TRE Query Portfolio - explanations and executed results

This portfolio contains 12 executed business queries, three views, two stored procedures, four transaction examples and one existing-trigger demonstration.
Each query includes its business question, result grain, SQL, explanation and actual output. Long tables preview the first eight rows; complete rows are in Results.json under business_queries.

Run setup and sample data first. In Business_Queries.sql select Q01-Q12 by their BEGIN and END markers. In Transaction_Examples.sql select one example; T01 commits and must use a disposable database copy.

Reference date: **2026-10-19**. Server: **PostgreSQL 18.6 on x86_64-windows, compiled by msvc-19.44.35228, 64-bit**. All source rows are synthetic. Current statuses are read from the stored sample; this is not a historical status reconstruction.

Validation: 12 queries; 17 rejected procedure cases; four positive procedure/view groups; four two-session races; five executed demos; dump/restore passed. The base 2,408 business rows remain unchanged in the reporting database.

| Query | Business topic | Actual rows |
|---|---|---:|
| Q01 | Active listing inventory| 75 |
| Q02 | Property relisting history| 100 |
| Q03 | Upcoming agent schedule| 68 |
| Q04 | Showing party capacity| 300 |
| Q05 | Latest submitted offer per listing| 250 |
| Q06 | Marketed listings without offers| 60 |
| Q07 | Accepted offers awaiting completion| 25 |
| Q08 | Monthly completed-sale trends| 10 |
| Q09 | Listing-agent sales ranking| 100 |
| Q10 | Sale-to-asking ratios by property type| 4 |
| Q11 | Clients with both buyer and seller roles| 165 |
| Q12 | Active listings below their internal segment average| 23 |

## Q01 - Active listing inventory

**Business question:** Which ACTIVE or UNDER_OFFER listings are being marketed, and who are their agents and sellers?

**Result grain:** One listing.

**SQL techniques:** Reusable view; multi-table joins; pre-aggregated STRING_AGG.

**Explanation:** Seller names are aggregated by listing before the property and agent joins. A listing with joint sellers therefore remains one inventory record.

**Executed SQL:** [Business_Queries.sql section Q01](Business_Queries.sql)

```sql
-- Q01: Which listings are currently being marketed and who is responsible?
-- The view pre-aggregates joint sellers, avoiding duplicate listing rows.
SELECT listing_id, property_ref, municipality, property_type,
       asking_price AS asking_price_cad, status, listing_agent, seller_count, seller_names
FROM tre.v_active_listings
ORDER BY municipality, asking_price DESC, listing_id;
```

**Actual outcome:** 75 inventory records: 50 ACTIVE and 25 UNDER_OFFER. The seed has one seller on each of these current listings.

**Result: 75 rows.** First eight rows shown below; this preview is truncated.

| listing_id | property_ref | municipality | property_type | asking_price_cad | status | listing_agent | seller_count | seller_names |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 159 | TRE-P-0159 | Airdrie | TOWNHOUSE | 926750.00 | UNDER_OFFER | Hayden Foster | 1 | Casey Chen |
| 154 | TRE-P-0154 | Airdrie | CONDO | 885500.00 | UNDER_OFFER | Cameron Foster | 1 | Jordan Chen |
| 149 | TRE-P-0149 | Airdrie | DETACHED | 844250.00 | ACTIVE | Hayden Evans | 1 | Casey Martin |
| 144 | TRE-P-0144 | Airdrie | OTHER | 803000.00 | ACTIVE | Cameron Evans | 1 | Jordan Martin |
| 139 | TRE-P-0139 | Airdrie | TOWNHOUSE | 761750.00 | ACTIVE | Hayden Davis | 1 | Casey Nguyen |
| 134 | TRE-P-0134 | Airdrie | CONDO | 720500.00 | ACTIVE | Cameron Davis | 1 | Jordan Nguyen |
| 129 | TRE-P-0129 | Airdrie | DETACHED | 679250.00 | ACTIVE | Hayden Campbell | 1 | Casey Wilson |
| 124 | TRE-P-0124 | Airdrie | OTHER | 638000.00 | ACTIVE | Cameron Campbell | 1 | Jordan Wilson |

**Complete output:** [Results.json business_queries.Q01](Results.json).

**Interpretation limit:** ACTIVE and UNDER_OFFER are both included. These are the stored current statuses, not a reconstructed historical inventory.

## Q02 - Property relisting history

**Business question:** How do listing dates and asking prices compare across repeated listings of the same property?

**Result grain:** One listing belonging to a property with multiple listing instances.

**SQL techniques:** CTE; COUNT OVER; ROW_NUMBER; LAG; NULLIF.

**Explanation:** The window calculations happen before the multiple-listing filter. Chronological order uses listed_on and listing_id as a stable tie-breaker.

**Executed SQL:** [Business_Queries.sql section Q02](Business_Queries.sql)

```sql
-- Q02: How did a property's asking price change between listing instances?
WITH history AS (
    SELECT l.*, count(*) OVER (PARTITION BY property_id) AS listing_instances,
           row_number() OVER (PARTITION BY property_id ORDER BY listed_on,listing_id) AS listing_number,
           lag(asking_price) OVER (PARTITION BY property_id ORDER BY listed_on,listing_id) AS previous_asking_price
    FROM tre.listing l
)
SELECT p.property_ref, h.listing_id, h.listing_number, h.status, h.listed_on, h.closed_on,
       h.asking_price, h.previous_asking_price,
       round(100.0*(h.asking_price-h.previous_asking_price)/nullif(h.previous_asking_price,0),2) AS asking_change_pct
FROM history h JOIN tre.property p USING(property_id)
WHERE h.listing_instances > 1
ORDER BY h.property_id, h.listed_on, h.listing_id;
```

**Actual outcome:** 100 listing-history rows describe 50 properties. The later 50 rows all show a 0.00% asking-price change in this fixed seed.

**Result: 100 rows.** First eight rows shown below; this preview is truncated.

| property_ref | listing_id | listing_number | status | listed_on | closed_on | asking_price | previous_asking_price | asking_change_pct |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TRE-P-0001 | 201 | 1 | EXPIRED | 2025-06-01 | 2025-06-22 | 283250.00 | NULL | NULL |
| TRE-P-0001 | 1 | 2 | SOLD | 2026-01-01 | 2026-01-21 | 283250.00 | 283250.00 | 0.00 |
| TRE-P-0002 | 202 | 1 | EXPIRED | 2025-06-03 | 2025-06-24 | 291500.00 | NULL | NULL |
| TRE-P-0002 | 2 | 2 | SOLD | 2026-01-03 | 2026-01-23 | 291500.00 | 291500.00 | 0.00 |
| TRE-P-0003 | 203 | 1 | EXPIRED | 2025-06-05 | 2025-06-26 | 299750.00 | NULL | NULL |
| TRE-P-0003 | 3 | 2 | SOLD | 2026-01-05 | 2026-01-25 | 299750.00 | 299750.00 | 0.00 |
| TRE-P-0004 | 204 | 1 | EXPIRED | 2025-06-07 | 2025-06-28 | 308000.00 | NULL | NULL |
| TRE-P-0004 | 4 | 2 | SOLD | 2026-01-07 | 2026-01-27 | 308000.00 | 308000.00 | 0.00 |

**Complete output:** [Results.json business_queries.Q02](Results.json).

**Interpretation limit:** This compares different listing instances; the schema does not store every price edit within one listing. The deterministic sample reuses the same asking price for these relistings, so its change percentages are zero.

## Q03 - Upcoming agent schedule

**Business question:** Which scheduled sessions need agent coverage during October 20-29, 2026?

**Result grain:** One scheduled showing.

**SQL techniques:** View; joins; half-open date filter; named-timezone conversion.

**Explanation:** The start boundary is inclusive and the October 30 boundary is exclusive. Both filter boundaries and displayed timestamps explicitly use America/Edmonton.

**Executed SQL:** [Business_Queries.sql section Q03](Business_Queries.sql)

```sql
-- Q03: Which scheduled sessions require agent coverage on October 20-29?
-- Named-zone boundaries and display do not depend on the connection's timezone.
SELECT c.showing_id, c.listing_id, a.agent_id,
       a.first_name || ' ' || a.last_name AS showing_agent, p.property_ref,
       c.starts_at AT TIME ZONE 'America/Edmonton' AS starts_at_calgary,
       c.ends_at AT TIME ZONE 'America/Edmonton' AS ends_at_calgary,
       c.active_parties, c.active_visitors, c.bookable_party_slots
FROM tre.v_showing_capacity c JOIN tre.agent a USING(agent_id)
JOIN tre.property p USING(property_id)
WHERE c.status='SCHEDULED'
  AND c.starts_at >= timestamp '2026-10-20 00:00' AT TIME ZONE 'America/Edmonton'
  AND c.starts_at < timestamp '2026-10-30 00:00' AT TIME ZONE 'America/Edmonton'
ORDER BY c.starts_at, a.agent_id, c.showing_id;
```

**Actual outcome:** 68 scheduled sessions are returned. Their active-party and visitor counts are zero in this seed.

**Result: 68 rows.** First eight rows shown below; this preview is truncated.

| showing_id | listing_id | agent_id | showing_agent | property_ref | starts_at_calgary | ends_at_calgary | active_parties | active_visitors | bookable_party_slots |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 101 | 101 | 1 | Quinn Adams | TRE-P-0101 | 2026-10-21 09:00:00 | 2026-10-21 09:30:00 | 0 | 0 | 3 |
| 111 | 111 | 11 | Quinn Baker | TRE-P-0111 | 2026-10-21 09:00:00 | 2026-10-21 09:30:00 | 0 | 0 | 3 |
| 121 | 121 | 21 | Quinn Campbell | TRE-P-0121 | 2026-10-21 09:00:00 | 2026-10-21 09:30:00 | 0 | 0 | 3 |
| 131 | 131 | 31 | Quinn Davis | TRE-P-0131 | 2026-10-21 09:00:00 | 2026-10-21 09:30:00 | 0 | 0 | 3 |
| 141 | 141 | 41 | Quinn Evans | TRE-P-0141 | 2026-10-21 09:00:00 | 2026-10-21 09:30:00 | 0 | 0 | 3 |
| 151 | 151 | 51 | Quinn Foster | TRE-P-0151 | 2026-10-21 09:00:00 | 2026-10-21 09:30:00 | 0 | 0 | 3 |
| 161 | 161 | 61 | Quinn Green | TRE-P-0161 | 2026-10-21 09:00:00 | 2026-10-21 09:30:00 | 0 | 0 | 3 |
| 171 | 171 | 71 | Quinn Hall | TRE-P-0171 | 2026-10-21 09:00:00 | 2026-10-21 09:30:00 | 0 | 0 | 3 |

**Complete output:** [Results.json business_queries.Q03](Results.json).

**Interpretation limit:** All 68 upcoming scheduled sessions have zero bookings in this seed because booking rows were generated for earlier showings. Q04 separately displays the populated historical sessions.

## Q04 - Showing party capacity

**Business question:** How many active parties and visitors does every showing contain, including sessions with no bookings?

**Result grain:** One showing.

**SQL techniques:** View; LEFT JOIN; conditional aggregates with FILTER; COALESCE.

**Explanation:** PENDING and CONFIRMED count toward the three-party limit. Party sizes are summed separately as visitors. Only SCHEDULED sessions have bookable slots; completed and cancelled sessions have zero.

**Executed SQL:** [Business_Queries.sql section Q04](Business_Queries.sql)

```sql
-- Q04: How many parties/visitors are attached to each showing?
-- Capacity is THREE PARTIES, not three visitors. Historical rows do not consume it.
SELECT showing_id, listing_id, status, booking_history_rows,
       active_parties, active_visitors, bookable_party_slots, party_utilization_pct
FROM tre.v_showing_capacity
ORDER BY showing_id;
```

**Actual outcome:** 300 showing rows reconcile to 189 active booking records and 376 visitors. No session exceeds three active parties.

**Result: 300 rows.** First eight rows shown below; this preview is truncated.

| showing_id | listing_id | status | booking_history_rows | active_parties | active_visitors | bookable_party_slots | party_utilization_pct |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 1 | COMPLETED | 6 | 3 | 6 | 0 | 100.00 |
| 2 | 2 | COMPLETED | 6 | 3 | 6 | 0 | 100.00 |
| 3 | 3 | COMPLETED | 6 | 3 | 6 | 0 | 100.00 |
| 4 | 4 | COMPLETED | 6 | 2 | 4 | 0 | 66.67 |
| 5 | 5 | COMPLETED | 6 | 2 | 5 | 0 | 66.67 |
| 6 | 6 | COMPLETED | 6 | 3 | 6 | 0 | 100.00 |
| 7 | 7 | COMPLETED | 6 | 3 | 6 | 0 | 100.00 |
| 8 | 8 | COMPLETED | 6 | 2 | 5 | 0 | 66.67 |

**Complete output:** [Results.json business_queries.Q04](Results.json).

**Interpretation limit:** Utilization describes active booking records, not verified attendance. A party can contain up to three visitors, so three parties can represent nine visitors.

## Q05 - Latest submitted offer per listing

**Business question:** What is the latest offer submission for each listing, including listings that never received one?

**Result grain:** One listing.

**SQL techniques:** CTE; ROW_NUMBER; LEFT JOIN; deterministic tie-breaker.

**Explanation:** Offer rows are ranked within each listing. Restricting rn=1 in the LEFT JOIN preserves the 75 listings without any offer.

**Executed SQL:** [Business_Queries.sql section Q05](Business_Queries.sql)

```sql
-- Q05: What is each listing's latest submitted offer, if any?
-- Latest submission is distinct from accepted/winning offer; IDs break timestamp ties.
WITH ranked AS (
    SELECT o.*, row_number() OVER (
        PARTITION BY listing_id ORDER BY submitted_at DESC,offer_id DESC) AS rn
    FROM tre.offer o
)
SELECT l.listing_id, l.status AS listing_status, o.offer_id,
       o.status AS latest_offer_status, o.offer_amount,
       o.submitted_at AT TIME ZONE 'America/Edmonton' AS submitted_at_calgary,
       a.first_name || ' ' || a.last_name AS submitting_agent
FROM tre.listing l LEFT JOIN ranked o ON o.listing_id=l.listing_id AND o.rn=1
LEFT JOIN tre.agent a ON a.agent_id=o.submitted_by_agent_id
ORDER BY l.listing_id;
```

**Actual outcome:** 250 listing rows include 175 with a latest offer and 75 with NULL offer fields.

**Result: 250 rows.** First eight rows shown below; this preview is truncated.

| listing_id | listing_status | offer_id | latest_offer_status | offer_amount | submitted_at_calgary | submitting_agent |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | SOLD | 176 | REJECTED | 274752.50 | 2026-01-06 10:00:00 | Robin Baker |
| 2 | SOLD | 177 | REJECTED | 285670.00 | 2026-01-08 10:00:00 | Cameron Baker |
| 3 | SOLD | 178 | REJECTED | 296752.50 | 2026-01-10 10:00:00 | Reese Baker |
| 4 | SOLD | 179 | REJECTED | 308000.00 | 2026-01-12 10:00:00 | Blair Baker |
| 5 | SOLD | 180 | REJECTED | 303600.00 | 2026-01-14 10:00:00 | Devon Baker |
| 6 | SOLD | 181 | REJECTED | 314765.00 | 2026-01-16 10:00:00 | Skyler Baker |
| 7 | SOLD | 182 | REJECTED | 326095.00 | 2026-01-18 10:00:00 | Hayden Baker |
| 8 | SOLD | 183 | REJECTED | 337590.00 | 2026-01-20 10:00:00 | Elliot Baker |

**Complete output:** [Results.json business_queries.Q05](Results.json).

**Interpretation limit:** Latest submitted offer is not necessarily the accepted offer. Several synthetic offers share submission timestamps; the larger offer_id resolves those ties.

## Q06 - Marketed listings without offers

**Business question:** Which non-draft listings have no offer history?

**Result grain:** One non-draft listing without an offer.

**SQL techniques:** Correlated NOT EXISTS; joins; COALESCE; date arithmetic.

**Explanation:** The anti-join excludes every listing that has at least one offer, regardless of that offer's outcome. Closed listings use closed_on for duration; open ones use the fixed reference date.

**Executed SQL:** [Business_Queries.sql section Q06](Business_Queries.sql)

```sql
-- Q06: Which non-draft listings have never received an offer?
-- Grain: one listing. An anti-join avoids NULL-sensitive NOT IN semantics.
SELECT l.listing_id, p.property_ref, l.status, l.listed_on, l.closed_on,
       l.asking_price AS asking_price_cad,
       coalesce(l.closed_on,date '2026-10-19')-l.listed_on AS days_on_market
FROM tre.listing l JOIN tre.property p USING(property_id)
WHERE l.status <> 'DRAFT'
  AND NOT EXISTS (SELECT 1 FROM tre.offer o WHERE o.listing_id=l.listing_id)
ORDER BY days_on_market DESC,l.listing_id;
```

**Actual outcome:** 60 historical listings are returned: 35 WITHDRAWN and 25 EXPIRED. There are no ACTIVE results.

**Result: 60 rows.** First eight rows shown below; this preview is truncated.

| listing_id | property_ref | status | listed_on | closed_on | asking_price_cad | days_on_market |
| --- | --- | --- | --- | --- | --- | --- |
| 191 | TRE-P-0191 | WITHDRAWN | 2026-09-16 | 2026-10-07 | 530750.00 | 21 |
| 192 | TRE-P-0192 | WITHDRAWN | 2026-09-17 | 2026-10-08 | 539000.00 | 21 |
| 193 | TRE-P-0193 | WITHDRAWN | 2026-09-18 | 2026-10-09 | 547250.00 | 21 |
| 194 | TRE-P-0194 | WITHDRAWN | 2026-09-19 | 2026-10-10 | 555500.00 | 21 |
| 195 | TRE-P-0195 | WITHDRAWN | 2026-09-20 | 2026-10-11 | 563750.00 | 21 |
| 196 | TRE-P-0196 | WITHDRAWN | 2026-09-21 | 2026-10-12 | 572000.00 | 21 |
| 197 | TRE-P-0197 | WITHDRAWN | 2026-09-22 | 2026-10-13 | 580250.00 | 21 |
| 198 | TRE-P-0198 | WITHDRAWN | 2026-09-23 | 2026-10-14 | 588500.00 | 21 |

**Complete output:** [Results.json business_queries.Q06](Results.json).

**Interpretation limit:** All 60 results in this seed are WITHDRAWN or EXPIRED historical listings. They are not 60 current active sales leads. Drafts are excluded.

## Q07 - Accepted offers awaiting completion

**Business question:** Which accepted offers still lack a completed sale, and how long have they waited by October 19?

**Result grain:** One accepted offer with no sale.

**SQL techniques:** Multi-table joins; NOT EXISTS; local-date conversion.

**Explanation:** The query finds acceptance without completion, attributes the listing agent, and calculates waiting days using Calgary-local dates.

**Executed SQL:** [Business_Queries.sql section Q07](Business_Queries.sql)

```sql
-- Q07: Which accepted offers are still waiting for completion on the reference date?
SELECT o.offer_id, o.listing_id, p.property_ref, o.offer_amount,
       (o.accepted_at AT TIME ZONE 'America/Edmonton')::date AS accepted_on_calgary,
       date '2026-10-19'-(o.accepted_at AT TIME ZONE 'America/Edmonton')::date AS waiting_days,
       a.first_name || ' ' || a.last_name AS listing_agent
FROM tre.offer o JOIN tre.listing l USING(listing_id)
JOIN tre.property p USING(property_id) JOIN tre.agent a ON a.agent_id=l.agent_id
WHERE o.status='ACCEPTED'
  AND o.accepted_at < timestamp '2026-10-20 00:00' AT TIME ZONE 'America/Edmonton'
  AND NOT EXISTS (SELECT 1 FROM tre.sale_transaction s WHERE s.offer_id=o.offer_id)
ORDER BY waiting_days DESC,o.offer_id;
```

**Actual outcome:** 25 accepted offers await completion; their waiting times range from 14 to 38 days on the reference date.

**Result: 25 rows.** First eight rows shown below; this preview is truncated.

| offer_id | listing_id | property_ref | offer_amount | accepted_on_calgary | waiting_days | listing_agent |
| --- | --- | --- | --- | --- | --- | --- |
| 101 | 151 | TRE-P-0151 | 834927.50 | 2026-09-11 | 38 | Quinn Foster |
| 102 | 152 | TRE-P-0152 | 851620.00 | 2026-09-12 | 37 | Drew Foster |
| 103 | 153 | TRE-P-0153 | 868477.50 | 2026-09-13 | 36 | Robin Foster |
| 104 | 154 | TRE-P-0154 | 885500.00 | 2026-09-14 | 35 | Cameron Foster |
| 105 | 155 | TRE-P-0155 | 858000.00 | 2026-09-15 | 34 | Reese Foster |
| 106 | 156 | TRE-P-0156 | 874940.00 | 2026-09-16 | 33 | Blair Foster |
| 107 | 157 | TRE-P-0157 | 892045.00 | 2026-09-17 | 32 | Devon Foster |
| 108 | 158 | TRE-P-0158 | 909315.00 | 2026-09-18 | 31 | Skyler Foster |

**Complete output:** [Results.json business_queries.Q07](Results.json).

**Interpretation limit:** Acceptance alone is not a completed sale. The fixed reference date makes the result reproducible; statuses come from the stored sample snapshot.

## Q08 - Monthly completed-sale trends

**Business question:** How do completed-sale count and value change from January through October 2026?

**Result grain:** One calendar month.

**SQL techniques:** Calendar CTE; GROUP BY; LEFT JOIN; LAG; running SUM with explicit ROWS frame.

**Explanation:** A calendar fills months with zero sales before LAG calculates month-over-month changes. The running total counts each sale once. Percentage change is NULL when there is no previous month or its value is zero.

**Executed SQL:** [Business_Queries.sql section Q08](Business_Queries.sql)

```sql
-- Q08: How did completed sale value change each month, including zero-sale months?
-- Sale value means property transaction value, not company revenue/profit.
WITH months AS (
    SELECT d::date AS month_start FROM generate_series(
        timestamp '2026-01-01',timestamp '2026-10-01',interval '1 month') d
), monthly AS (
    SELECT date_trunc('month',completed_on)::date AS month_start,
           count(*) AS completed_sales, sum(sale_price) AS sale_value_cad
    FROM tre.sale_transaction
    WHERE completed_on >= date '2026-01-01' AND completed_on < date '2026-11-01'
    GROUP BY 1
), filled AS (
    SELECT m.month_start, coalesce(s.completed_sales,0) AS completed_sales,
           coalesce(s.sale_value_cad,0)::numeric(16,2) AS sale_value_cad
    FROM months m LEFT JOIN monthly s USING(month_start)
), compared AS (
    SELECT *,lag(sale_value_cad) OVER(ORDER BY month_start) AS previous_month_value
    FROM filled
)
SELECT month_start,completed_sales,sale_value_cad,previous_month_value,
       round(100.0*(sale_value_cad-previous_month_value)/nullif(previous_month_value,0),2) AS month_over_month_pct,
       sum(sale_value_cad) OVER(ORDER BY month_start ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_sale_value_cad
FROM compared ORDER BY month_start;
```

**Actual outcome:** 100 completed sales total CAD 54,205,030.00. September and October contain zero sample sales; both months remain visible.

**Result: 10 rows.** All rows shown below.

| month_start | completed_sales | sale_value_cad | previous_month_value | month_over_month_pct | cumulative_sale_value_cad |
| --- | --- | --- | --- | --- | --- |
| 2026-01-01 | 6 | 1779112.50 | NULL | NULL | 1779112.50 |
| 2026-02-01 | 14 | 5290945.00 | 1779112.50 | 197.39 | 7070057.50 |
| 2026-03-01 | 15 | 7486792.50 | 5290945.00 | 41.50 | 14556850.00 |
| 2026-04-01 | 15 | 9203700.00 | 7486792.50 | 22.93 | 23760550.00 |
| 2026-05-01 | 16 | 11867735.00 | 9203700.00 | 28.95 | 35628285.00 |
| 2026-06-01 | 15 | 11775720.00 | 11867735.00 | -0.78 | 47404005.00 |
| 2026-07-01 | 15 | 5125807.50 | 11775720.00 | -56.47 | 52529812.50 |
| 2026-08-01 | 4 | 1675217.50 | 5125807.50 | -67.32 | 54205030.00 |
| 2026-09-01 | 0 | 0.00 | 1675217.50 | -100.00 | 54205030.00 |
| 2026-10-01 | 0 | 0.00 | 0.00 | NULL | 54205030.00 |

**Complete output:** [Results.json business_queries.Q08](Results.json).

**Interpretation limit:** Sale value is the sum of property transaction prices, not TRE revenue, commission or profit. October covers the current sample snapshot, not a forecast of the whole month.

## Q09 - Listing-agent sales ranking

**Business question:** How do all agents rank by completed-sale value in the reporting period?

**Result grain:** One agent.

**SQL techniques:** Pre-aggregation; LEFT JOIN; DENSE_RANK.

**Explanation:** Sales are attributed through LISTING.agent_id. The date condition is inside the LEFT JOIN so an agent with no sale would remain with zero. Inactive agents remain because historical work still belongs to them.

**Executed SQL:** [Business_Queries.sql section Q09](Business_Queries.sql)

```sql
-- Q09: How do listing agents rank by completed sale value in Jan-Oct 2026?
-- Attribution uses LISTING.agent_id, not OFFER.submitted_by_agent_id.
WITH agent_totals AS (
    SELECT a.agent_id,a.first_name || ' ' || a.last_name AS listing_agent,a.is_active,
           count(s.sale_id) AS completed_sales,
           coalesce(sum(s.sale_price),0)::numeric(16,2) AS sale_value_cad
    FROM tre.agent a LEFT JOIN tre.v_completed_sales s
      ON s.listing_agent_id=a.agent_id
     AND s.completed_on>=date '2026-01-01' AND s.completed_on<date '2026-11-01'
    GROUP BY a.agent_id,a.first_name,a.last_name,a.is_active
)
SELECT dense_rank() OVER(ORDER BY sale_value_cad DESC) AS sales_rank,
       agent_id,listing_agent,is_active,completed_sales,sale_value_cad
FROM agent_totals ORDER BY sales_rank,agent_id;
```

**Actual outcome:** 100 agent rows are ranked. Each has one sale in this seed; their combined sale value reconciles to Q08 and the base sale table.

**Result: 100 rows.** First eight rows shown below; this preview is truncated.

| sales_rank | agent_id | listing_agent | is_active | completed_sales | sale_value_cad |
| --- | --- | --- | --- | --- | --- |
| 1 | 79 | Hayden Hall | t | 1 | 936017.50 |
| 2 | 78 | Skyler Hall | t | 1 | 918500.00 |
| 3 | 77 | Devon Hall | t | 1 | 901147.50 |
| 4 | 76 | Blair Hall | t | 1 | 883960.00 |
| 5 | 71 | Quinn Hall | t | 1 | 877965.00 |
| 6 | 75 | Reese Hall | t | 1 | 866937.50 |
| 7 | 70 | Elliot Green | t | 1 | 861025.00 |
| 8 | 74 | Cameron Hall | t | 1 | 850080.00 |

**Complete output:** [Results.json business_queries.Q09](Results.json).

**Interpretation limit:** The synthetic seed gives each of the 100 agents exactly one completed sale. This is a demonstration of ranking logic, not evidence of real employee performance.

## Q10 - Sale-to-asking ratios by property type

**Business question:** What are sale values, close times and sale-to-asking ratios for each property type?

**Result grain:** One property type.

**SQL techniques:** Fact-grain view; GROUP BY; AVG; ratio of totals.

**Explanation:** The query reports both the arithmetic mean of each sale's ratio and the asking-value-weighted ratio of totals. These differ because properties have different asking prices.

**Executed SQL:** [Business_Queries.sql section Q10](Business_Queries.sql)

```sql
-- Q10: What are the average close time and final-to-asking ratio for each type?
-- AVG of individual ratios and ratio of totals answer different questions.
SELECT property_type,count(*) AS completed_sales,
       sum(sale_price) AS sale_value_cad,round(avg(sale_price),2) AS avg_sale_price_cad,
       round(avg(days_to_close),2) AS avg_days_to_close,
       round(avg(100.0*sale_price/asking_price),2) AS mean_final_to_asking_pct,
       round(100.0*sum(sale_price)/sum(asking_price),2) AS value_weighted_final_to_asking_pct
FROM tre.v_completed_sales
WHERE completed_on>=date '2026-01-01' AND completed_on<date '2026-11-01'
GROUP BY property_type ORDER BY property_type;
```

**Actual outcome:** Four property-type groups each contain 25 completed sales. Every group has a 20-day average close time in this seed.

**Result: 4 rows.** All rows shown below.

| property_type | completed_sales | sale_value_cad | avg_sale_price_cad | avg_days_to_close | mean_final_to_asking_pct | value_weighted_final_to_asking_pct |
| --- | --- | --- | --- | --- | --- | --- |
| CONDO | 25 | 13623390.00 | 544935.60 | 20.00 | 97.92 | 98.10 |
| DETACHED | 25 | 13417525.00 | 536701.00 | 20.00 | 98.00 | 98.07 |
| OTHER | 25 | 13353010.00 | 534120.40 | 20.00 | 98.12 | 97.90 |
| TOWNHOUSE | 25 | 13811105.00 | 552444.20 | 20.00 | 97.84 | 97.99 |

**Complete output:** [Results.json business_queries.Q10](Results.json).

**Interpretation limit:** The available asking_price is the stored listing price, not a full price history. The seed sets all completed transactions to 20 days after listing, so all average close times are 20 days.

## Q11 - Clients with both buyer and seller roles

**Business question:** Which clients participate in both buyer and seller relationships, and how much activity is linked to them?

**Result grain:** One client who has both roles.

**SQL techniques:** Multiple pre-aggregating CTEs; inner/left joins; conditional count.

**Explanation:** Seller relationships, buyer relationships and bookings are aggregated independently before joining the client. This prevents many-to-many fanout from multiplying counts.

**Executed SQL:** [Business_Queries.sql section Q11](Business_Queries.sql)

```sql
-- Q11: Which clients participate as both buyers and sellers?
-- Aggregate each relationship first; joining raw many-to-many rows inflates counts.
WITH seller_roles AS (
    SELECT client_id,count(*) AS listings_as_seller FROM tre.listing_seller GROUP BY client_id
), buyer_roles AS (
    SELECT b.client_id,count(*) AS offers_as_buyer,count(s.sale_id) AS completed_purchase_participations
    FROM tre.offer_buyer b LEFT JOIN tre.sale_transaction s USING(offer_id) GROUP BY b.client_id
), bookings AS (
    SELECT client_id,count(*) AS booking_history_rows,
           count(*) FILTER(WHERE status IN ('PENDING','CONFIRMED')) AS active_booking_records
    FROM tre.showing_booking GROUP BY client_id
)
SELECT c.client_id,c.first_name || ' ' || c.last_name AS client_name,
       sr.listings_as_seller,br.offers_as_buyer,br.completed_purchase_participations,
       coalesce(b.booking_history_rows,0) AS booking_history_rows,
       coalesce(b.active_booking_records,0) AS active_booking_records
FROM tre.client c JOIN seller_roles sr USING(client_id) JOIN buyer_roles br USING(client_id)
LEFT JOIN bookings b USING(client_id) ORDER BY c.client_id;
```

**Actual outcome:** 165 clients have both relationship-based roles. Booking counts remain independent of the number of buyer/seller associations.

**Result: 165 rows.** First eight rows shown below; this preview is truncated.

| client_id | client_name | listings_as_seller | offers_as_buyer | completed_purchase_participations | booking_history_rows | active_booking_records |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Alex Chen | 2 | 1 | 0 | 2 | 1 |
| 2 | Sam Chen | 2 | 1 | 0 | 2 | 1 |
| 3 | Mei Chen | 2 | 1 | 0 | 2 | 1 |
| 4 | Jordan Chen | 2 | 1 | 0 | 2 | 1 |
| 5 | Taylor Chen | 2 | 1 | 0 | 2 | 1 |
| 6 | Avery Chen | 2 | 1 | 0 | 2 | 1 |
| 7 | Riley Chen | 2 | 1 | 0 | 2 | 1 |
| 8 | Morgan Chen | 2 | 1 | 0 | 2 | 1 |

**Complete output:** [Results.json business_queries.Q11](Results.json).

**Interpretation limit:** Roles are established by relationship participation, not separate client subtypes. Joint buyers each have a purchase participation; these counts must not be summed as a count of distinct company sales.

## Q12 - Active listings below their internal segment average

**Business question:** Which ACTIVE listings ask less than the average of ACTIVE inventory in the same municipality and property type?

**Result grain:** One qualifying ACTIVE listing.

**SQL techniques:** Correlated scalar aggregate subquery; CTE; comparison to segment mean.

**Explanation:** The peer group includes the listing itself and uses only ACTIVE records with the same municipality and property type. Filtering uses the unrounded average; rounding is for display.

**Executed SQL:** [Business_Queries.sql section Q12](Business_Queries.sql)

```sql
-- Q12: Which ACTIVE listings ask less than the internal location/type average?
-- This is a synthetic inventory comparison, not a market valuation/appraisal.
WITH benchmarked AS (
    SELECT l.listing_id,p.property_ref,p.municipality,p.property_type,l.asking_price,
           (SELECT avg(peer_l.asking_price)
            FROM tre.listing peer_l JOIN tre.property peer_p USING(property_id)
            WHERE peer_l.status='ACTIVE' AND peer_p.municipality=p.municipality
              AND peer_p.property_type=p.property_type) AS internal_segment_avg
    FROM tre.listing l JOIN tre.property p USING(property_id) WHERE l.status='ACTIVE'
)
SELECT listing_id,property_ref,municipality,property_type,asking_price,
       round(internal_segment_avg,2) AS internal_segment_avg,
       round(asking_price-internal_segment_avg,2) AS asking_minus_avg_cad
FROM benchmarked WHERE asking_price<internal_segment_avg
ORDER BY asking_minus_avg_cad,listing_id;
```

**Actual outcome:** 23 ACTIVE listings ask less than their own internal municipality/type mean. An independent Python calculation of the seed recipe reproduces the same listing IDs.

**Result: 23 rows.** First eight rows shown below; this preview is truncated.

| listing_id | property_ref | municipality | property_type | asking_price | internal_segment_avg | asking_minus_avg_cad |
| --- | --- | --- | --- | --- | --- | --- |
| 102 | TRE-P-0102 | Calgary | CONDO | 456500.00 | 646250.00 | -189750.00 |
| 101 | TRE-P-0101 | Calgary | DETACHED | 448250.00 | 632107.14 | -183857.14 |
| 103 | TRE-P-0103 | Calgary | TOWNHOUSE | 464750.00 | 638000.00 | -173250.00 |
| 104 | TRE-P-0104 | Airdrie | OTHER | 473000.00 | 638000.00 | -165000.00 |
| 105 | TRE-P-0105 | Cochrane | DETACHED | 481250.00 | 646250.00 | -165000.00 |
| 109 | TRE-P-0109 | Airdrie | DETACHED | 514250.00 | 679250.00 | -165000.00 |
| 110 | TRE-P-0110 | Cochrane | CONDO | 522500.00 | 687500.00 | -165000.00 |
| 106 | TRE-P-0106 | Calgary | CONDO | 489500.00 | 646250.00 | -156750.00 |

**Complete output:** [Results.json business_queries.Q12](Results.json).

**Interpretation limit:** This is a comparison within a small synthetic inventory. It is not a market appraisal, sale-price prediction or investment recommendation.

## Views

| View | Grain | Purpose |
|---|---|---|
| v_active_listings | Listing | Inventory enriched with property, agent and aggregated sellers |
| v_showing_capacity | Showing | Party capacity and visitor counts, including empty sessions |
| v_completed_sales | Sale | Stable one-sale grain for reporting; avoids participant fanout |

Definitions: [07_views.sql](../SQL_Scripts/07_views.sql). Installing views does not add business tables or change the 63 original attributes.

## Stored procedures

- `accept_offer(offer_id, accepted_at)` locks the listing then the offer, validates status and dates, and changes SUBMITTED/ACTIVE to ACCEPTED/UNDER_OFFER.
- `complete_sale(offer_id, coordinator_staff_id, completed_on, sale_price, NULL)` checks the workflow, inserts a sale, marks the listing SOLD and returns its generated sale ID.
- The caller controls the transaction. Neither procedure commits internally. These are SQL procedures invoked with CALL, not trigger functions.
- Invalid role/date/status inputs are rejected. A repeated close is rejected. Serialization failure (40001) or deadlock (40P01) requires retrying the complete transaction.

Definitions: [08_stored_procedures.sql](../SQL_Scripts/08_stored_procedures.sql). Recorded procedure and concurrency checks are included in the [validation summary](Results.json).

## Executed transaction and trigger examples

**T01 commits a new sale. Run it only in a separate demonstration copy.** T02-T05 preserve the original business rows; sequence increments can still leave gaps. Each recorded example was executed on its own sample-data copy.

### T01_atomic_commit

[Transaction_Examples.sql section T01](Transaction_Examples.sql) | [Results.json transaction_outputs.T01](Results.json)

```text
 stage  | offer_id | offer_status | listing_status
--------+----------+--------------+----------------
 before |      126 | SUBMITTED    | ACTIVE
(1 row)

  stage   | offer_id | offer_status | listing_status
----------+----------+--------------+----------------
 accepted |      126 | ACCEPTED     | UNDER_OFFER
(1 row)

 p_sale_id
-----------
       101
(1 row)

   stage   | offer_id | offer_status | listing_status | closed_on  | sale_id | sale_price | completed_sale_count
-----------+----------+--------------+----------------+------------+---------+------------+----------------------
 committed |      126 | ACCEPTED     | SOLD           | 2026-10-22 |     101 |  433000.00 |                  101
(1 row)

Recorded T01 output: NOTICE:  PASS: acceptance, sale INSERT and listing closure committed together
```

### T02_full_rollback

[Transaction_Examples.sql section T02](Transaction_Examples.sql) | [Results.json transaction_outputs.T02](Results.json)

```text
 p_sale_id
-----------
       101
(1 row)

       stage        | offer_id | offer_status | listing_status | sale_price
--------------------+----------+--------------+----------------+------------
 inside_transaction |      127 | ACCEPTED     | SOLD           |  440000.00
(1 row)

     stage      | offer_id | offer_status | listing_status | has_sale
----------------+----------+--------------+----------------+----------
 after_rollback |      127 | SUBMITTED    | ACTIVE         | f
(1 row)

Recorded T02 output: NOTICE:  PASS: ROLLBACK restored the offer/listing and removed the provisional sale
```

### T03_savepoint

[Transaction_Examples.sql section T03](Transaction_Examples.sql) | [Results.json transaction_outputs.T03](Results.json)

```text
 p_sale_id
-----------
       101
(1 row)

       stage       | status | sale_price
-------------------+--------+------------
 provisional_close | SOLD   |  450000.00
(1 row)

          stage           | offer_status | listing_status | has_sale
--------------------------+--------------+----------------+----------
 after_savepoint_rollback | ACCEPTED     | UNDER_OFFER    | f
(1 row)

 p_sale_id
-----------
       102
(1 row)

     stage     | status | closed_on  | sale_price
---------------+--------+------------+------------
 revised_close | SOLD   | 2026-10-23 |  448000.00
(1 row)

Recorded T03 output: NOTICE:  PASS: savepoint kept acceptance, reversed closing, then allowed revised closing
```

### T04_failure_atomicity

[Transaction_Examples.sql section T04](Transaction_Examples.sql) | [Results.json transaction_outputs.T04](Results.json)

```text
         stage         | offer_id | offer_status | listing_status | has_sale
-----------------------+----------+--------------+----------------+----------
 after_handled_failure |      129 | SUBMITTED    | ACTIVE         | f
(1 row)

Recorded T04 output: NOTICE:  Expected failure [23514]: BR16: assign an active COORDINATOR to the sale
Recorded T04 output: NOTICE:  PASS: failed closing left no accepted offer, changed listing or sale row
```

### T05_trigger_capacity

[Transaction_Examples.sql section T05](Transaction_Examples.sql) | [Results.json transaction_outputs.T05](Results.json)

```text
 stage  | showing_id | active_parties | active_visitors
--------+------------+----------------+-----------------
 before |          1 |              3 |               6
(1 row)

      stage      | showing_id | active_parties | active_visitors
-----------------+------------+----------------+-----------------
 after_rejection |          1 |              3 |               6
(1 row)

Recorded T05 output: NOTICE:  Expected trigger rejection [23514]: BR09: showing 1 exceeds three active party bookings
Recorded T05 output: NOTICE:  PASS: fourth party rejected and the three existing parties retained
```

## Execution plans and validation

[Q05 EXPLAIN ANALYZE](Results.json) and [Q08 EXPLAIN ANALYZE](Results.json) record real plans and buffers. Small sample tables can reasonably use sequential scans; these observations are not production-scale performance claims.

[Complete rows and validation evidence](Results.json) | [Reproduction guide](../README.md)

Technical references: [PostgreSQL window functions](https://www.postgresql.org/docs/18/functions-window.html), [CREATE PROCEDURE](https://www.postgresql.org/docs/18/sql-createprocedure.html), [transaction management](https://www.postgresql.org/docs/18/plpgsql-transactions.html), [SAVEPOINT](https://www.postgresql.org/docs/18/sql-savepoint.html).

AI assistance was used to draft and execute this portfolio. Team review and actual member contributions should be recorded in the Phase 2 implementation report.
