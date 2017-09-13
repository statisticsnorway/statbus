import { createAction } from 'redux-act'
import { push } from 'react-router-redux'
import R from 'ramda'

export const updateFilter = createAction('update search form')

export const setQuery = pathname => query => (dispatch) => {
  R.pipe(updateFilter, dispatch)(query)
  const type = query.type === 'any' ? undefined : query.type
  R.pipe(push, dispatch)({ pathname, query: { ...query, type } })
}

