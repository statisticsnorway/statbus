import { createAction } from 'redux-act'
import R from 'ramda'

import dispatchRequest from 'helpers/request'
import { updateFilter, setQuery } from '../actions'

export const fetchDataSucceeded = createAction('fetch StatUnits succeeded')
const fetchData = queryParams =>
  dispatchRequest({
    url: '/api/statunits/deleted',
    queryParams,
    onSuccess: (dispatch, resp) => R.pipe(fetchDataSucceeded, dispatch)(resp),
  })

export const restoreSucceeded = createAction('restore StatUnit succeeded')
const restore = (type, regId) =>
  dispatchRequest({
    method: 'delete',
    url: '/api/statunits/deleted',
    queryParams: { type, regId },
    onSuccess: dispatch => R.pipe(restoreSucceeded, dispatch)(regId),
  })

export default {
  updateFilter,
  setQuery,
  fetchData,
  restore,
}
