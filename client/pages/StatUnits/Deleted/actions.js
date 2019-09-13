import { createAction } from 'redux-act'
import { pipe } from 'ramda'

import dispatchRequest from 'helpers/request'
import { updateFilter, setQuery } from '../actions'

export const fetchDataStarted = createAction('fetch StatUnits status changed')
export const fetchDataSucceeded = createAction('fetch StatUnits succeeded')
const fetchData = queryParams =>
  dispatchRequest({
    url: '/api/statunits/deleted',
    queryParams,
    onSuccess: (dispatch, resp) =>
      pipe(
        fetchDataSucceeded,
        dispatch,
      )(resp),
    onStart: dispatch => dispatch(fetchDataStarted()),
  })

export const restoreSucceeded = createAction('restore StatUnit succeeded')
const restore = (type, regId, queryParams, onFail) =>
  dispatchRequest({
    method: 'delete',
    url: '/api/statunits/deleted',
    queryParams: { type, regId },
    onSuccess: dispatch =>
      pipe(
        fetchData,
        dispatch,
      )(queryParams),
    onFail: (_, error) => {
      onFail(error.message)
    },
  })

export const clearSearchFormForDeleted = createAction('clear search form for deleted')
export const setSearchConditionForDeleted = createAction('set search condition for deleted')

export default {
  updateFilter,
  setQuery,
  fetchData,
  restore,
  clearSearchFormForDeleted,
  setSearchConditionForDeleted,
}
