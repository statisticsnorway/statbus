import { createAction } from 'redux-act'
import { pipe } from 'ramda'

import dispatchRequest from 'helpers/request'
import { updateFilter, setQuery } from '../actions'

export const fetchDataSucceeded = createAction('fetch StatUnits succeeded')
const fetchData = queryParams =>
  dispatchRequest({
    url: '/api/statunits/deleted',
    queryParams,
    onSuccess: (dispatch, resp) => pipe(fetchDataSucceeded, dispatch)(resp),
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
}
