# Phase 3 requirement coverage

Source: [Brightspace Phase 3 instructions](https://learn.sait.ca/d2l/lms/dropbox/user/folder_submit_files.d2l?db=1062432&grpid=910505&isprv=0&bp=0&ou=886971).

The final design plan is the **Design Plan** section of the [combined Word report](../Technical_Report/Phase%203%20Technical%20Report%20and%20Design%20Plan.docx). The technical report and contribution table are in the same document.

| Requirement | Files and evidence |
| --- | --- |
| Extend the Phase 2 model and document keys and data ownership | Combined report, Design Plan section; unchanged bigint property/listing keys; SQL_Scripts/phase2_baseline/ |
| At least 2,000 linked text records and a data-quality review | Embeddings/raw_documents.jsonl; Query_Results/data_audit.json; 2,500 linked documents |
| Class hierarchy, mapping alternatives, methods and multiplicities | Combined report, Design Plan section; Diagrams/UML_Class_Diagram.drawio and .png |
| Inheritance, polymorphism and encapsulation in PostgreSQL | SQL_Scripts/01_phase3_schema.sql; Query_Results/A1_polymorphism.csv; Query_Results/validation_checks.csv |
| Nested JSONB, validation and GIN index | property_features, valid_features and property_features_gin in the schema/index scripts |
| Containment, JSON path, array expansion with a relational join and nested update | SQL_Scripts/06_oo_jsonb_examples.sql; Query_Results/J1_containment.csv, J2_jsonpath.csv, J3_array_join.csv and J4_nested_update.json |
| JSONB query plan and interpretation | Query_Results/J1_default_plan.txt and J1_gin_diagnostic_plan.txt; combined report |
| Free open embedding model, dimensions and provenance | Embeddings/embed.py and model_manifest.json; SQL_Scripts/04_load_vectors.sql |
| Five natural-language searches, labelled top-five results and precision | Query_Results/S1_top5.csv through S5_top5.csv; precision_at_5.csv |
| Filtered vector search and execution plan | SQL_Scripts/C1_filtered.sql; Query_Results/C1_filtered.csv and C1_filtered_plan.txt |
| Hybrid full-text/vector search and vector-only comparison | SQL_Scripts/07_vector_search_examples.sql; Query_Results/C2_hybrid.csv and C2_vector_only.csv |
| HNSW versus exact search, top-ten overlap and performance | Query_Results/evaluation_summary.json, C3_exact_top10.csv, C3_hnsw_top10.csv and index_build.json |
| One query combining hierarchy, JSONB and vector similarity | SQL_Scripts/D1_combined.sql; Query_Results/D1_combined.csv and plan |
| UML and data pipeline diagrams | Diagrams/UML_Class_Diagram.* and Data_Pipeline_Diagram.* |
| Technical report, design plan and team contributions | Technical_Report/Phase 3 Technical Report and Design Plan.docx |
| Reproducible optional bonus workflow | Embeddings/run_pipeline.py; regeneration instructions in the package README |
| Dataset source, licence, AI disclosure and credential handling | Package README and .gitignore |
| Required repository folders | Design_Plan/, Diagrams/, SQL_Scripts/, Embeddings/, Query_Results/, Technical_Report/ and README.md |
