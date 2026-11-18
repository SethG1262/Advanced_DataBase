# Second review — November 17, 2026

The review found and corrected two numeric edge cases. JSONB accepts `2.0` as an integral number, but the amenity reference trigger previously cast its text directly to bigint. The cast now passes through numeric after checking that the ID is positive, integral and within bigint range. The amenity array query now reads distance as numeric, preserving values such as 400.5 metres instead of raising an integer conversion error.

Four regression checks cover a decimal spelling of an integral ID, a fractional distance, a non-integral ID and an out-of-range ID. All 35 integration checks pass. Standalone C1 and D1 SQL files now include the same HNSW settings used by the evaluator, avoiding dependence on a previous session setup.

The release-candidate archive was extracted into a separate folder and run from a different working directory against a new database. Full regeneration produced the same vector file and all 18 table fingerprints. All 12,500 qrels were independently recomputed from the declared topic and feature rules; the 25 reported search rows were matched to the saved source text. These remain synthetic rules, not independent human judgments. The four SQL example files succeeded in separate psql sessions and preserved the database contents.

`second_review.json` identifies the tested release-candidate archive. The report was then regenerated from the new measured results, all report/design pages were visually reviewed, and the final archive was rebuilt and hash-verified. Timings are observations from this rerun and may differ from the earlier report. The separate SHA256 file beside the final ZIP identifies that final artifact.

The team's actual contributions still need confirmation. GitHub publication and Brightspace submission remain pending; this review did not publish or submit anything.
