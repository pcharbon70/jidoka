# Phase 4.4: Pending Memories Queue - Feature Planning

**Feature Branch**: `feature/phase-4.4-pending-memories`
**Date**: 2025-01-24
**Status**: ✅ Complete

## Problem Statement

Section 4.4 of the Phase 4 planning document specifies implementation of PendingMemories for the promotion queue. The core module was implemented in Phase 4.1, but several functions were missing and have now been added:

1. **`ready_for_promotion/2`** - Filter items ready for LTM promotion
2. **`calculate_importance/1`** - Importance scoring algorithm
3. **`clear_promoted/2`** - Remove promoted items from queue

## Implementation Summary

### Functions Added

#### `ready_for_promotion/2` - Filter items ready for promotion

Returns items that meet promotion criteria based on importance threshold and optionally age.

**Features:**
- `:min_importance` option (default: 0.7)
- `:max_age_seconds` option for age filtering
- Combines importance and age filters

#### `calculate_importance/1` - Calculate importance score

Calculates an importance score for a memory item based on type and age.

**Base Importance by Type:**
- `:analysis` - 0.8 (analysis results are high value)
- `:file_context` - 0.6 (file context is useful)
- `:fact` - 0.5 (facts are moderately important)
- `:conversation` - 0.4 (conversation excerpts are lower priority)

**Age Decay:**
- 10% decay per hour
- Maximum 50% decay (so even very old items retain 50% of base importance)

#### `clear_promoted/2` - Remove promoted items

Removes items that were successfully promoted to long-term memory by ID.

**Features:**
- Uses MapSet for efficient ID lookup
- Returns count of items actually removed
- Handles non-existent IDs gracefully

## Implementation Plan

- [x] Create feature branch
- [x] Add `ready_for_promotion/2` function
- [x] Add `calculate_importance/1` function with helper functions
- [x] Add `clear_promoted/2` function
- [x] Add tests for new functions
- [x] Run all tests to verify
- [x] Update planning document
- [x] Create summary

## Success Criteria

- [x] Feature branch created
- [x] `ready_for_promotion/2` implemented
- [x] `calculate_importance/1` implemented
- [x] `clear_promoted/2` implemented
- [x] Tests added for new functions
- [x] All tests passing (36 tests)
- [x] Planning document updated
- [x] Summary created

## Files Modified

1. `lib/jido_coder_lib/memory/short_term/pending_memories.ex` - Added 3 functions + helpers
2. `test/jido_coder_lib/memory/short_term/pending_memories_test.exs` - Added 3 test blocks
3. `notes/planning/01-foundation/phase-04.md` - Marked section 4.4 as complete

## Test Results

- **36 tests passing** for PendingMemories (up from 21 in Phase 4.1)
  - 15 new assertions across 3 test blocks
  - ready_for_promotion: 4 tests
  - calculate_importance: 7 tests
  - clear_promoted: 4 tests

## Notes

- Age decay uses a simple linear model (10% per hour, max 50%)
- Future enhancement: access frequency tracking in importance calculation
- Future enhancement: configurable decay rates
- Future enhancement: priority queue for highest-importance items first
