# Phase 1 Database Modelling

Phase 1 provides the conceptual and logical database design. It contains three crow's-foot EER views, a relational schema normalized to 3NF, a data dictionary, and a technical report. PostgreSQL 18 is the target for Phase 2 implementation; Phase 1 does not require executable SQL or a deployed database.

The model has 11 tables: CLIENT, AGENT, STAFF, PROPERTY, LISTING, LISTING_SELLER, SHOWING, SHOWING_BOOKING, OFFER, OFFER_BUYER, and SALE_TRANSACTION. Together, they cover property listings, joint sellers, scheduled showings, party bookings, joint buyers, offers, and completed sales.

## Phase 1 Deliverables

| Deliverable | Editable source or document | Preview |
| --- | --- | --- |
| Property and Listing EER view | [draw.io source](EER_diagrams/Property%20and%20Listing.drawio) | [PNG](EER_diagrams/Property%20and%20Listing.png) |
| Showing and Booking EER view | [draw.io source](EER_diagrams/Showing%20and%20Booking.drawio) | [PNG](EER_diagrams/Showing%20and%20Booking.png) |
| Offers and Sales EER view | [draw.io source](EER_diagrams/Offers%20and%20Sales.drawio) | [PNG](EER_diagrams/Offers%20and%20Sales.png) |
| Relational schema and normalization | [Schema PDF](Relational_Schema/TRE_Phase1_Relational_Schema_seth.pdf) | Included in report Sections 5-6 |
| Data dictionary | [Dictionary PDF](Data%20dictionary/Data%20dictionary%20.pdf) | Included in report Appendices A-F |
| Technical report | [Phase 1 report PDF](Technical%20Report/Project%20Phase%201%20Technical%20Report.pdf) | Full report with EER views, schema, dictionary, and contributions |

The technical report brings the model, business rules, mapping choices, normalization, approval conditions, and contribution records together. The editable EER sources have the same filenames as their PNG exports.

## Phase 1 folder structure

```text
Phase1_Modelling/
├── README.md
├── EER_diagrams/        Editable .drawio sources and PNG exports
├── Relational_Schema/   Relational schema and normalization
├── Data dictionary/     Table and attribute definitions
└── Technical Report/    Complete Phase 1 report
```

[Return to the project overview](../README.md).

## Design Process

1. Identify the organization's records and business rules, including joint ownership, party bookings, and the difference between an offer and a completed sale.
2. Draw the EER views using consistent crow's-foot cardinalities and participation constraints. Use the same entity names and identifiers across the views.
3. Map entities to relations and replace many-to-many buyer and seller relationships with association tables. Record the primary keys, foreign keys, referenced tables, and intended delete/update rules.
4. State functional dependencies and show the 1NF, 2NF, and 3NF steps where normalization changes the design. Move repeated client, agent, and property details into their own tables.
5. Define each table's row meaning and each attribute's type, key, validation rules, and sample value in the dictionary. Bring the design and its explanations together in the report.

## Main Design Choices

- **Separate PROPERTY and LISTING:** A physical property can be listed again. Property characteristics and a listing's price, dates, and status have different lifecycles.
- **Support joint sellers and buyers:** LISTING_SELLER and OFFER_BUYER use composite primary keys. A client can participate as both a buyer and a seller.
- **Separate SHOWING and SHOWING_BOOKING:** SHOWING records the session and hosting agent. Each booking records one lead client, party size, status, and booking time; companions are counted without requiring separate client records.
- **Separate OFFER and SALE_TRANSACTION:** An accepted offer may not result in a completed sale. A sale references its offer through a unique foreign key, and the final sale price can differ from the offer amount. An offer references a listing directly and does not require a prior showing.
- **Keep STAFF and AGENT separate:** Internal staff use role_code, while independent agents have license details. The current scope has no role-specific attributes requiring a supertype/subtype hierarchy.
- **Preserve business history:** Cancelled and closed records remain in the model. All foreign keys are mandatory, with RESTRICT intended for both deletion and key updates of referenced records.

## Key Business Rules

- A property has at most one ACTIVE or UNDER_OFFER listing. A non-draft listing requires at least one seller.
- A showing allows at most three active bookings, with one to three visitors per booking. PENDING and CONFIRMED bookings count as active. A client has at most one active booking for the same showing.
- Non-cancelled showing intervals must not overlap for the same property or agent, and each showing must end after it starts.
- Each offer requires at least one buyer. A listing has at most one ACCEPTED offer, and an offer can lead to at most one sale.
- A sale must reference an accepted offer and an active staff member with the COORDINATOR role. Prices must be positive, and completion cannot precede offer acceptance.

The report lists all 18 business rules in Section 3. Conditional counts and rules involving other records are documented for later implementation; ordinary attribute CHECK constraints alone cannot express all of them.

## Phase 1 Tools

The EER model is maintained in editable draw.io (diagrams.net) format. Microsoft Word is used to prepare the technical report and data dictionary, while GitHub stores the design files and records team contributions. PostgreSQL 18 is the target database for the relational schema.

To edit a diagram, open its `.drawio` file in diagrams.net and export the corresponding PNG after making changes. Keep the EER views, relational schema, data dictionary, and report consistent when changing a table or relationship.

## Team Contributions

The following roles and tasks are recorded in the Phase 1 report.

| Team member | Phase 1 role | Specific contributions |
| --- | --- | --- |
| Troy Franks | Data dictionary | Created and filled the data dictionary. |
| Seth Garciano | Relational schema and normalization | Converted the EER diagram into the relational schema and normalized it from 1NF to 3NF. |
| Tristin Bates | Technical report | Created, formatted, and structured the technical report. |
| Yisong Wang | Business rules and EERD | Improved business rules, designed database tables, and created EER diagrams. |

GitHub commit history provides the repository record of file changes and contributions.

## Approval Conditions and Later Scope

Report Section 8 explains the planned use of Calgary Historical Property Assessments (Parcel), 2021-2025, Spark/PySpark on Databricks Free Edition, Delta analytical tables, Databricks SQL Warehouse, Power BI Desktop, Neon PostgreSQL, and a limited Cloud Firestore extension. These are later-phase plans. Public assessment data stays separate from synthetic TRE business data, and PostgreSQL remains authoritative for core amounts and states.

## AI Use Disclosure

ChatGPT/Codex assisted with basic brainstorming, syntax support and translation between languages.
