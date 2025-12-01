---
description: Update all project documentation (roadmap, status, CLAUDE.md, README) to mark a phase as complete
tags: [project, documentation]
---

# Update Phase Completion Documentation

**User will provide:** Phase number (e.g., "7" for Phase 7)

**Your task:** Update all project documentation files to reflect the completion of the specified phase.

## Files to Update

### 1. docs/roadmap.md
- Mark all tasks in the specified phase as ✅ **COMPLETED**
- Add completion date in status section
- Add implementation notes and key achievements
- Update progress bar to show phase at 100%
- Update overall progress percentage (add 10% for each phase, starting from 10%)
- Update "Last Updated" date at bottom

### 2. CLAUDE.md
- Add completed phase summary in "Current Project Status" → "Completed ✅" section
- Include key achievements bullet points
- Update "Next Steps" section to point to the next phase
- Update progress tracking bar to show phase at 100%
- Update overall completion percentage
- Add latest update note with date

### 3. docs/status.md
- Add completed phase to "Completed Phases ✅" section with full details
- Update "Current Phase" section to next phase
- Update progress bar to show phase at 100%
- Update overall progress percentage
- Update "Last Updated" date at top
- Update "Quick Status" message

### 4. README.md (if exists)
- Update project status section
- Update progress indicators
- Add latest milestone achieved

## Progress Calculation

**Formula:** `(number_of_completed_phases / 10) * 100 = X%`

Examples:
- Phase 5 complete: 5/10 = 50%
- Phase 6 complete: 6/10 = 60%
- Phase 7 complete: 7/10 = 70%
- Phase 8 complete: 8/10 = 80%
- Phase 9 complete: 9/10 = 90%
- Phase 10 complete: 10/10 = 100%

## Phase Names Reference

Use these exact names when updating:
- Phase 0: Bootstrap Infrastructure
- Phase 1: Data Lake Foundation
- Phase 2: Streaming Ingestion Path
- Phase 3: Batch Ingestion Path (EventBridge)
- Phase 4: Step Functions Orchestration
- Phase 5: DynamoDB Hot Store
- Phase 6: AI Enrichment Services
- Phase 7: Merge Lambda & Complete Orchestration
- Phase 8: Analytics & Query Layer
- Phase 9: Production Hardening & Documentation
- Phase 10: CI/CD Pipeline

## Instructions

1. **Read the roadmap** to understand what was accomplished in the specified phase
2. **Update all 4 files** with consistent information
3. **Use current date** (format: YYYY-MM-DD or "2025-01-30")
4. **Calculate correct progress percentage** using formula above
5. **Update progress bars** - use ████████████████████ for 100%, ░░░░░░░░░░░░░░░░░░░░ for 0%
6. **Set next phase** as the "Current Phase" in status.md
7. **Be consistent** - same completion date and percentage across all files

## Example Usage

**User says:** "Phase 7 complete"

**You do:**
1. Read `docs/roadmap.md` Phase 7 section to see what was built
2. Update `docs/roadmap.md`:
   - Mark Phase 7 tasks as ✅ COMPLETED
   - Add status: ✅ **COMPLETED** (All tasks finished on 2025-01-XX)
   - Update progress bar: Phase 7 shows ████████████████████ 100% ✅
   - Update overall: ~80% (8 of 10 phases complete)
3. Update `CLAUDE.md`:
   - Add Phase 7 summary to Completed section
   - Update Next Steps to Phase 8
   - Update progress bar to 80%
4. Update `docs/status.md`:
   - Add Phase 7 to Completed Phases section
   - Set Current Phase to Phase 8
   - Update progress to 80%
5. Update `README.md` (if exists)

## Important Notes

- **Always read existing content first** - don't guess what was implemented
- **Maintain existing formatting** - match the style of previous phase completions
- **Be thorough** - include implementation notes, key achievements, and testing details
- **Double-check percentages** - math must be correct across all files
- **Use consistent dates** - same completion date in all files
- **Don't skip files** - update ALL documentation files, even if tedious

## Output Format

After updating all files, provide a summary:

```
✅ Documentation Updated for Phase X Completion

Files Updated:
- docs/roadmap.md (Phase X marked complete, progress: Y%)
- CLAUDE.md (Phase X summary added, progress: Y%)
- docs/status.md (Current phase now: Phase Z, progress: Y%)
- README.md (Status updated)

Overall Progress: Y% (X of 10 phases complete)
Next Phase: Phase Z - [Phase Name]
```
