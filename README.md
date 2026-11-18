# Advanced_DataBase Project Group 6

TotallyRealEstate is a hypothetical mid-sized real estate company with 8 full-time employees and 100 independent agents. As the company grows, it is managing more clients, property listings, showings, offers, and transactions. Its current systems use separate spreadsheets and applications, leading to duplicate records, outdated information, scheduling conflicts, and slow reporting. A centralized database would improve data accuracy, efficiency, and accessibility while supporting the company's future growth.

Our proposed solution is to create a centralized PostgreSQL relational database to manage TotallyRealEstate's clients, agents, properties, listings, showings, offers, and transactions. Data from existing spreadsheets can be imported and standardized within the database, reducing duplicate or inconsistent records while making information easier to manage and access.

The project will include designing an EER model, creating the PostgreSQL database with primary keys, foreign keys, and constraints, populating it with sample data, and developing SQL queries for common business needs. We will also create a spreadsheet data-import process, develop reports or visualizations, and test and document the database.

## Project phases

| Phase | Contents | Start here |
| --- | --- | --- |
| Phase 1 | EER diagrams, relational schema, data dictionary, business rules and modelling report | [Phase 1 modelling](Phase1_Modelling/README.md) |
| Phase 2 | PostgreSQL implementation, sample data, business rules, query portfolio, JSONB mapping and Firestore prototype | [Phase 2 implementation](Phase2_Implementation/README.md) |
| Phase 3 | Object-oriented mapping, JSONB features, text embeddings, search evaluation and final report | [Phase 3 implementation](Phase3_Implementation/README.md) |

## Repository structure

```text
Advanced_DataBase/
├── README.md
├── Phase1_Modelling/
│   ├── README.md
│   ├── EER_diagrams/
│   ├── Relational_Schema/
│   ├── Data dictionary/
│   └── Technical Report/
├── Phase2_Implementation/
│   └── README.md
└── Phase3_Implementation/
    ├── README.md
    └── advanceddb_project/
        └── Phase3_OO_JSONB_Vector/
            ├── Design_Plan/
            ├── Diagrams/
            ├── SQL_Scripts/
            ├── Embeddings/
            ├── Query_Results/
            ├── Technical_Report/
            └── README.md
```

The Phase 1 design process, business rules, contributions and planned later scope are documented in [Phase1_Modelling/README.md](Phase1_Modelling/README.md). Each phase's README contains its own setup instructions, evidence and applicable disclosures.

## Phase 3 final document

The [final technical report and design plan](Phase3_Implementation/advanceddb_project/Phase3_OO_JSONB_Vector/Technical_Report/Phase%203%20Technical%20Report%20and%20Design%20Plan.docx) are combined in one editable Word document. The design plan begins at the **Design Plan** heading; the same document also contains the team's contribution table.

## Team

Seth Garciano, Tristin Bates, Troy Franks and Yisong Wang.
