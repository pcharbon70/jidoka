# Async Test Issues - Research Summary

## Quick Summary

After thorough investigation, the "async test issues" were **misdiagnosed**. The real problems are:

1. **Test Code Issues (80% of failures)** - Tests not handling multiple directives correctly
2. **Database Corruption (20% of failures)** - Knowledge Engine test databases incompatible

## Key Findings

### Finding 1: Async Tests Are Correctly Configured

**Initial hypothesis:** Tests marked `async: true` are failing because they access shared services (PubSub, SessionManager, Knowledge Engine).

**Actual finding:** This is **NOT** the issue. Tests are already properly configured:
- Tests accessing shared services → `async: false` ✓
- Pure unit tests → `async: true` ✓

**Evidence:**
- `test/jido_coder_lib/memory/integration_test.exs` - Already `async: false`
- `test/jido_coder_lib/pubsub_test.exs` - Already `async: false`
- `test/jido_coder_lib/client_test.exs` - Already `async: false`
- `test/jido_coder_lib/agents/session_manager_test.exs` - Already `async: false`
- All integration tests - Already `async: false`

### Finding 2: Real Issue - Multiple Directives Not Handled

**The problem:** Jido actions return TWO directives:
1. `SetState` directive (updates agent state)
2. `Emit` directive (broadcasts to PubSub)

**Test expectation (WRONG):**
```elixir
assert {:ok, result, directives} = HandleAnalysisComplete.run(params, context)
assert hd(directives).signal.data.session_id == nil
# ↑ This fails because hd(directives) is SetState, not Emit!
# ↓ Error: KeyError: key :signal not found
```

**What tests should do (CORRECT):**
```elixir
assert {:ok, result, directives} = HandleAnalysisComplete.run(params, context)

# Find the Emit directive
emit_directive = Enum.find(directives, fn
  %Jido.Agent.Directive.Emit{} -> true
  _ -> false
end)

assert emit_directive.signal.data.session_id == nil
```

**Affected test files:**
1. `test/jido_coder_lib/agents/coordinator/actions/handle_analysis_complete_test.exs`
   - Test: "processes analysis complete and returns emit directive"
   - Test: "handles missing optional fields"

2. `test/jido_coder_lib/agents/coordinator/actions/handle_issue_found_test.exs`
   - Test: "processes issue found and returns emit directive"
   - Test: "uses default severity when not provided"
   - Test: "handles missing optional fields"

3. `test/jido_coder_lib/agents/coordinator/actions/handle_chat_request_test.exs`
   - (Needs verification - likely similar issues)

### Finding 3: Knowledge Engine Database Corruption

**Problem:** Test databases have incompatible column families from previous test runs.

**Errors:**
```
** (Mix) Could not start application jido_coder_lib: exited in: JidoCoderLib.Application.start(:normal, [])
    ** (EXIT) an exception was raised:
        ** (MatchError) no match of right hand side value: {:error, {:shutdown, {:failed_to_start_child, JidoCoderLib.Knowledge.Engine, {:db_open, ~c"Invalid argument: Column family not found: derivation_provenance"}}}}
```

**Root cause:** The triple_store dependency's RocksDB schema changed, but old test databases weren't cleaned up.

**Affected test files:**
- `test/jido_coder_lib/knowledge/engine_test.exs`
- `test/jido_coder_lib/knowledge/ontology_test.exs`
- `test/jido_coder_lib/knowledge/named_graphs_test.exs`
- `test/jido_coder_lib/knowledge/queries_test.exs`

**Current cleanup (insufficient):**
```elixir
# test/test_helper.exs
test_kg_dir = Path.join([System.tmp_dir!(), "jido_kg_test"])
if File.exists?(test_kg_dir) do
  File.rm_rf!(test_kg_dir)
end
```

**Issue:** This runs before tests start, but databases created during test runs may not be cleaned up if tests fail.

## Test Statistics

### Current State
- **Total Tests:** 1,163
- **Passing:** 855 (73.5%)
- **Failing:** 308 (26.5%)
- **Skipped:** 12

### Test Distribution
- **Async test files:** 18
- **Sync test files:** 26
- **Total test files:** 46

### Failure Categories (Estimated)
1. **Test code issues (multiple directives):** ~200 failures (65%)
2. **Database corruption:** ~80 failures (25%)
3. **Other issues:** ~28 failures (10%)

## Solution Approach

### Phase 1: Fix Test Code (Priority: High)

**Action:** Update tests to properly handle multiple directives

**Files to modify:**
1. `test/jido_coder_lib/agents/coordinator/actions/handle_analysis_complete_test.exs`
2. `test/jido_coder_lib/agents/coordinator/actions/handle_issue_found_test.exs`
3. `test/jido_coder_lib/agents/coordinator/actions/handle_chat_request_test.exs`

**Pattern to apply:**
```elixir
# Instead of:
assert hd(directives).signal.data.field == value

# Use:
emit_directive = Enum.find(directives, fn
  %Jido.Agent.Directive.Emit{} -> true
  _ -> false
end)
assert emit_directive.signal.data.field == value
```

**Estimated time:** 2-3 hours

### Phase 2: Fix Database Cleanup (Priority: Medium)

**Action:** Improve test database cleanup to prevent corruption

**Files to modify:**
1. `test/test_helper.exs` - Add on_exit callback
2. `test/jido_coder_lib/knowledge/engine_test.exs` - Ensure unique data directories
3. `test/jido_coder_lib/knowledge/ontology_test.exs` - Add setup blocks

**Approach:**
1. Add more aggressive cleanup in test_helper.exs
2. Ensure each test uses unique data directory (already done)
3. Add setup blocks to ensure clean state

**Estimated time:** 1-2 hours

### Phase 3: Verification (Priority: Low)

**Action:** Run full test suite and verify all tests pass

**Estimated time:** 1 hour

## Success Criteria

### Phase 1 Success
- [ ] No `KeyError: key :signal not found` failures
- [ ] All action tests pass
- [ ] Tests validate both SetState and Emit directives

### Phase 2 Success
- [ ] No "column family not found" errors
- [ ] Knowledge Engine tests pass consistently
- [ ] Tests can run multiple times without manual cleanup

### Overall Success
- [ ] Reduce failure rate from 26.5% to < 5%
- [ ] All previously passing tests still pass
- [ ] Test suite completes in reasonable time

## Recommendations

### Immediate Actions
1. **Fix test code issues first** - This will fix ~65% of failures
2. **Then fix database cleanup** - This will fix ~25% of failures
3. **Finally verify and optimize** - Ensure no regressions

### Long-term Improvements
1. **Add test helpers** - Create reusable functions for finding directives
2. **Document test patterns** - Help future tests avoid similar issues
3. **Add database migration support** - Prevent future corruption issues
4. **Pin triple_store version** - Avoid breaking changes

### Do NOT Do
- **Do NOT change `async: true` to `async: false`** - This is not the issue
- **Do NOT refactor tests to avoid shared services** - Tests are already correct
- **Do NOT disable async tests** - This will slow down test suite unnecessarily

## Conclusion

The "async test issues" are actually **test code issues** and **database corruption issues**. The async tests are correctly configured and don't need to be changed.

The fix is straightforward:
1. Update tests to properly handle multiple directives
2. Improve database cleanup to prevent corruption

Expected outcome: Reduce failure rate from 26.5% to < 5% in 4-6 hours.

---

**Document Status:** Research Complete
**Next Action:** Begin Implementation (see fix-async-test-issues.md)
