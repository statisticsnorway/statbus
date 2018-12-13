import { createAction } from 'redux-act'

import dispatchRequest from 'helpers/request'
import { updateFilter, setQuery } from '../actions'

export const fetchDataSucceeded = createAction('fetch StatUnits succeeded')

export const clear = createAction('clear formData filter')

export const fetchDataStateChanged = createAction('fetch StatUnits status changed')

export const fetchLookupSucceeded = createAction('fetch Lookup succeeded')

export const setSearchCondition = createAction('set search condition')

const fetchData = queryParams =>
  dispatchRequest({
    url: '/api/statunits',
    queryParams,
    onSuccess: (dispatch, resp) => {
      dispatch(fetchDataSucceeded({ ...resp, queryObj: this.queryParams }))
      dispatch(fetchDataStateChanged(false))
    },
    onStart: dispatch => dispatch(fetchDataStateChanged(true)),
  })

const deleteStatUnit = (type, id, queryParams) =>
  dispatchRequest({
    url: `/api/statunits/${type}/${id}`,
    method: 'delete',
    onSuccess: (dispatch) => {
      dispatch(fetchData(queryParams))
    },
  })

const fetchLookup = id =>
  dispatchRequest({
    url: `/api/lookup/${id}`,
    method: 'get',
    onSuccess: (dispatch, lookup) => {
      dispatch(fetchLookupSucceeded({ id, lookup }))
    },
  })

export default {
  updateFilter,
  setQuery,
  fetchData,
  deleteStatUnit,
  clear,
  fetchDataStateChanged,
  fetchLookup,
  setSearchCondition,
}
