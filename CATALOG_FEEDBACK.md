# WayTask Catalog Feedback

This document tracks catalog, autocomplete, ranking, and personalization issues found during QA.

## Status values

- Open
- In Progress
- Fixed
- Verified
- Implemented
- Deferred

## Issue types

- Missing product
- Missing alias
- Missing keyword
- Incorrect ranking
- Weak match shown
- Duplicate product
- Incorrect canonical resolution
- Brand-term issue
- Incorrect category
- Localization
- Personalization
- Other

## Feedback Log

| ID | Search query | Expected result | Actual result | Issue type | Required fix | Regression test | Status |
|---|---|---|---|---|---|---|---|
| CAT-001 | מלח | מלח should appear as a catalog result | No catalog match; only custom product option appears | Missing product | Add מלח to the spices category with appropriate aliases and keywords | `testCAT001SaltIsAnExactSpiceResult` | Fixed |
| CAT-002 | סוכ | סוכר should rank first or near first | Only סוכר וניל appeared | Missing product / Incorrect ranking | Add or verify סוכר and ensure prefix ranking places it above סוכר וניל | `testCAT002SugarPrefixAndExactRankGenericSugarFirst` | Fixed |
| CAT-003 | קמ | קמח should rank first | קמח לבן appeared, followed by weak unrelated matches | Missing generic product / Weak match shown | Add generic קמח entry or alias and tighten weak-match filtering for two-letter queries | `testCAT003FlourTwoCharacterAndExactQueriesRankGenericFlourFirst` | Fixed |
| CAT-004 | פס | Only strongly relevant products should appear | Several weak or unrelated results appeared | Weak match shown | Tighten filtering for two-letter queries and prevent weak keyword matches from filling the list | `testCAT004TwoCharacterPastaQueryExcludesWeakMatches` | Fixed |
| CAT-005 | ל | Products beginning with ל should appear before products containing ל elsewhere | Prefix results appeared first | Ranking | Keep current behavior and add regression coverage | `testCAT005SingleLetterLamedKeepsNamePrefixesFirst` | Verified |
| CAT-006 | ח | Products beginning with ח should appear first | Relevant prefix results appeared first | Ranking | Keep current behavior | `testCAT006SingleLetterHetKeepsNamePrefixesFirst` | Verified |
| CAT-007 | No catalog match | Hebrew interface text should be shown | English text is displayed | Localization | Replace with Hebrew copy | `testCAT007NoMatchCopyIsAlwaysHebrew` | Fixed |
| CAT-008 | Add “…” as a custom product | Hebrew interface text should be shown | English text is displayed | Localization | Replace with Hebrew copy such as הוסף את “…” כמוצר מותאם אישית | `testCAT008CustomAddCopyIsAlwaysHebrew` | Fixed |
| CAT-009 | Past purchases | Frequently selected products should receive a controlled ranking boost | No history-based personalization yet | Personalization | Add frequency and recency boosts without overriding strong textual relevance | `testFrequencyBoostReordersProductsWithinTheSameStrongLevel`, `testRecencyBoostReordersOtherwiseEqualStrongMatches`, `testPersonalizationNeverOverridesStrongerTextualRelevance`, `testBuilderMapsCatalogLinkedHistoryToExactProductID`, `testBuilderKeepsLegacyCustomHistoryAsNormalizedNameFallback` | Implemented |
