# Jotai Migration Guide

This guide will help you migrate from your current Context + useEffect patterns to Jotai for simpler, more performant state management.

## 🎯 Why Migrate to Jotai?

Your current codebase has complex patterns that Jotai can simplify:

- **Complex Provider Nesting**: 8+ nested Context providers
- **Cascading useEffect Chains**: Dependencies causing unnecessary re-renders
- **Performance Issues**: Entire component trees re-rendering on small state changes
- **Maintenance Overhead**: Hard to track state dependencies and side effects

## 📦 What's Included

The migration includes these new files:

- `src/atoms/index.ts` - Core atoms replacing all Context providers
- `src/atoms/hooks.ts` - Utility hooks for common patterns
- `src/atoms/JotaiAppProvider.tsx` - Simple app setup component
- `src/atoms/migration-example.tsx` - Before/after comparisons

## 🚀 Quick Start (5 Minutes)

### Step 1: Update Your App Root

Replace your complex provider nesting:

```tsx
// Before: app/src/app/layout.tsx or your root component
<AuthProvider>
  <ClientBaseDataProvider>
    <TimeContextProvider>
      <SearchProvider>
        <SelectionProvider>
          <TableColumnsProvider>
            <GettingStartedProvider>
              <ImportUnitsProvider>
                <YourApp />
              </ImportUnitsProvider>
            </GettingStartedProvider>
          </TableColumnsProvider>
        </SelectionProvider>
      </SearchProvider>
    </TimeContextProvider>
  </ClientBaseDataProvider>
</AuthProvider>

// After: Simple single provider
import { JotaiAppProvider } from '@/atoms/JotaiAppProvider'

<JotaiAppProvider>
  <YourApp />
</JotaiAppProvider>
```

### Step 2: Update a Simple Component

Pick a component that uses multiple contexts and replace the hooks:

```tsx
// Before: Complex context usage
import { useAuth } from '@/hooks/useAuth'
import { useBaseData } from '@/app/BaseDataClient'
import { useTimeContext } from '@/app/time-context'
import { useSelectionContext } from '@/app/search/use-selection-context'

const MyComponent = () => {
  const { isAuthenticated, user } = useAuth()
  const { statDefinitions, refreshBaseData } = useBaseData()
  const { selectedTimeContext } = useTimeContext()
  const { selected, toggle } = useSelectionContext()

  useEffect(() => {
    if (isAuthenticated) {
      refreshBaseData()
    }
  }, [isAuthenticated, refreshBaseData])

  // Complex component logic...
}

// After: Simple Jotai hooks
import { useAuth, useBaseData, useTimeContext, useSelection } from '@/atoms/hooks'

const MyComponent = () => {
  const auth = useAuth()
  const baseData = useBaseData()
  const timeContext = useTimeContext()
  const selection = useSelection()

  // No useEffect needed! Auto-initialization handled by JotaiAppProvider
  // Component only re-renders when atoms it uses actually change
}
```

### Step 3: See the Results

- **Reduced Bundle Size**: Fewer Context providers and useEffect dependencies
- **Better Performance**: Only components using changed atoms re-render
- **Simpler Code**: No more useEffect chains or complex state management
- **Better DevEx**: TypeScript support and easier debugging

## 📋 Full Migration Checklist

### Phase 1: Setup (30 minutes)
- [x] ✅ Jotai installed (`pnpm add jotai`)
- [ ] 🔄 Replace app root with `JotaiAppProvider`
- [ ] 🔄 Test that app still loads and basic functionality works

### Phase 2: Migrate Core Components (1-2 hours)
- [ ] 🔄 Replace `useAuth()` calls with new `useAuth()` from atoms/hooks
- [ ] 🔄 Replace `useBaseData()` calls with new `useBaseData()` from atoms/hooks  
- [ ] 🔄 Replace `useTimeContext()` calls with new `useTimeContext()` from atoms/hooks
- [ ] 🔄 Remove manual `useEffect` chains for data fetching (handled by provider)

### Phase 3: Migrate Feature Components (2-3 hours)
- [ ] 🔄 Replace `useSearchContext()` with new `useSearch()` from atoms/hooks
- [ ] 🔄 Replace `useSelectionContext()` with new `useSelection()` from atoms/hooks
- [ ] 🔄 Replace `useTableColumns()` with atoms/hooks equivalent
- [ ] 🔄 Replace `useGettingStarted()` with atoms equivalent
- [ ] 🔄 Replace `useImportUnits()` with atoms equivalent

### Phase 4: Remove Old Code (1 hour)
- [ ] 🔄 Delete old Context provider components
- [ ] 🔄 Delete old useEffect-heavy hooks
- [ ] 🔄 Clean up unused imports
- [ ] 🔄 Run tests to ensure everything still works

### Phase 5: Optimization (30 minutes)
- [ ] 🔄 Add `AtomDevtools` component for development debugging
- [ ] 🔄 Review and optimize any remaining performance issues
- [ ] 🔄 Document any custom patterns for your team

## 🔧 Migration Patterns

### Pattern 1: Replace Context + useEffect with Simple Hook

```tsx
// Before: AuthContext pattern
const { isAuthenticated, user } = useAuth() // From AuthContext
const { refreshBaseData } = useBaseData()

useEffect(() => {
  if (isAuthenticated) {
    refreshBaseData()
  }
}, [isAuthenticated, refreshBaseData])

// After: Simple atom hook
const auth = useAuth() // From atoms/hooks
// Auto-initialization handled by JotaiAppProvider, no useEffect needed
```

### Pattern 2: Replace State + Reducer with Atoms

```tsx
// Before: Complex reducer pattern
const [searchState, dispatch] = useReducer(searchReducer, initialState)

const updateQuery = (query: string) => {
  dispatch({ type: 'UPDATE_QUERY', query })
  dispatch({ type: 'RESET_PAGINATION' })
}

// After: Simple atom updates
const search = useSearch()

const updateQuery = (query: string) => {
  search.updateSearchQuery(query)
  search.updatePagination(1) // Reset to first page
}
```

### Pattern 3: Replace SSE useEffect with Hook

```tsx
// Before: Complex SSE management
useEffect(() => {
  let eventSource: EventSource | null = null
  
  if (isAuthenticated) {
    eventSource = new EventSource('/api/sse')
    eventSource.onmessage = (event) => {
      // Handle messages...
    }
  }
  
  return () => {
    if (eventSource) {
      eventSource.close()
    }
  }
}, [isAuthenticated])

// After: Handled automatically by JotaiAppProvider
// No code needed in your components!
```

## 🎨 Component Examples

### Simple Search Component

```tsx
import { useSearch } from '@/atoms/hooks'

export const SearchComponent = () => {
  const search = useSearch()
  
  return (
    <div>
      <input 
        value={search.searchState.query}
        onChange={(e) => search.updateSearchQuery(e.target.value)}
        placeholder="Search..."
      />
      
      <button onClick={search.executeSearch}>
        Search
      </button>
      
      {search.searchResult.loading && <div>Loading...</div>}
      
      <div>
        Results: {search.searchResult.total}
      </div>
    </div>
  )
}
```

### Simple Selection Component

```tsx
import { useSelection } from '@/atoms/hooks'

export const SelectionComponent = () => {
  const selection = useSelection()
  
  return (
    <div>
      <div>Selected: {selection.count} items</div>
      
      <button onClick={selection.clear}>
        Clear Selection
      </button>
      
      {/* Your item list here */}
      {yourItems.map(item => (
        <div key={item.id}>
          <input
            type="checkbox"
            checked={selection.isSelected(item)}
            onChange={() => selection.toggle(item)}
          />
          {item.name}
        </div>
      ))}
    </div>
  )
}
```

### Simple Time Context Component

```tsx
import { useTimeContext } from '@/atoms/hooks'

export const TimeContextSelector = () => {
  const { selectedTimeContext, setSelectedTimeContext, timeContexts } = useTimeContext()
  
  return (
    <select 
      value={selectedTimeContext?.id || ''} 
      onChange={(e) => {
        const tc = timeContexts.find(tc => tc.id === parseInt(e.target.value))
        if (tc) setSelectedTimeContext(tc)
      }}
    >
      <option value="">Select Time Context</option>
      {timeContexts.map(tc => (
        <option key={tc.id} value={tc.id}>
          {tc.year} {/* Adjust based on your TimeContextRow type */}
        </option>
      ))}
    </select>
  )
}
```

## 🐛 Debugging

### Development Tools

Add this to your app for debugging:

```tsx
import { AtomDevtools } from '@/atoms/JotaiAppProvider'

// In your app root
<JotaiAppProvider>
  <YourApp />
  <AtomDevtools /> {/* Shows current atom states in development */}
</JotaiAppProvider>
```

### Common Issues

1. **Components not re-rendering**: Make sure you're using atoms, not accessing them directly
2. **SSE connection issues**: Check the SSE endpoint URL in `JotaiAppProvider.tsx`
3. **Auth state not persisting**: Verify that auth atoms are being set correctly
4. **Performance not improved**: Ensure you're using specific atom hooks, not reading entire objects

## 📈 Performance Benefits

After migration, you should see:

- **Fewer re-renders**: Components only update when their specific atoms change
- **Smaller bundle**: Less Context provider code and useEffect dependencies  
- **Faster development**: Simpler patterns and better TypeScript support
- **Easier testing**: Atoms can be tested in isolation
- **Better debugging**: Clear atom dependency graph

## 🔄 Gradual Migration

You can migrate gradually:

1. **Start with `JotaiAppProvider`**: Replace your provider nesting
2. **Migrate one component at a time**: Update individual components to use new hooks
3. **Keep old contexts temporarily**: Both systems can coexist during migration
4. **Remove old code last**: Clean up once everything is migrated

## 📚 Additional Resources

- [Jotai Documentation](https://jotai.org/)
- [Migration Examples](./src/atoms/migration-example.tsx)
- [Atom Patterns](./src/atoms/index.ts)
- [Utility Hooks](./src/atoms/hooks.ts)

## 🤝 Getting Help

If you run into issues during migration:

1. Check the migration examples in `src/atoms/migration-example.tsx`
2. Look at the before/after patterns above
3. Use the `AtomDevtools` component to see current atom states
4. Compare with your old Context patterns to identify what might be missing

## ✅ Success Metrics

You'll know the migration is successful when:

- [ ] App loads without errors
- [ ] Authentication flow works correctly  
- [ ] Data fetching and caching work as expected
- [ ] Search and filtering function properly
- [ ] Selection state is maintained correctly
- [ ] SSE connections work (if you use them)
- [ ] Performance is improved (fewer re-renders)
- [ ] Code is simpler and easier to understand

---

**Ready to get started?** Begin with Step 1 above and migrate one component at a time. The new system is designed to be much simpler and more maintainable than your current Context + useEffect patterns!