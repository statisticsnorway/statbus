import { createAction } from 'redux-act'
import { push } from 'react-router-redux'
import { pipe } from 'ramda'

export const updateFilter = createAction('update search form')

export const setQuery = pathname => query => (dispatch) => {
  pipe(updateFilter, dispatch)(query)
  pipe(push, dispatch)({ pathname, query })
}
