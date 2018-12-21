import { createAction } from 'redux-act'
import { pipe } from 'ramda'

import dispatchRequest from 'helpers/request'
import { updateFilter, setQuery } from '../actions'
import { clear, setSearchCondition } from '../Search/actions'

export const fetchDataStarted = createAction('fetch StatUnits status changed')
export const fetchDataSucceeded = createAction('fetch StatUnits succeeded')
const fetchData = queryParams =>
  dispatchRequest({
    url: '/api/statunits/deleted',
    queryParams,
    onSuccess: (dispatch, resp) => pipe(fetchDataSucceeded, dispatch)(resp),
    onStart: dispatch => dispatch(fetchDataStarted()),
  })

export const restoreSucceeded = createAction('restore StatUnit succeeded')
const restore = (type, regId, queryParams) =>
  dispatchRequest({
    method: 'delete',
    url: '/api/statunits/deleted',
    queryParams: { type, regId },
    onSuccess: dispatch => pipe(fetchData, dispatch)(queryParams),
  })

export default {
  updateFilter,
  setQuery,
  fetchData,
  restore,
  clear,
  setSearchCondition,
}
