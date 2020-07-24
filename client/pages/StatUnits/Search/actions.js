import { createAction } from 'redux-act'
import { NotificationManager } from 'react-notifications'
import { getLocalizeText } from 'helpers/locale'
import dispatchRequest from 'helpers/request'
import { updateFilter, setQuery } from '../actions'

export const fetchDataSucceeded = createAction('fetch StatUnits succeeded')

export const fetchDataFailed = createAction('fetch StatUnits failed')

export const clear = createAction('clear formData filter')

export const fetchDataStateChanged = createAction('fetch StatUnits status changed')

export const fetchLookupSucceeded = createAction('fetch Lookup succeeded')

export const deleteStatUnitSuccessed = createAction('delete StatUnit succeeded')

export const setSearchCondition = createAction('set search condition')

export const clearError = createAction('clear error')

const fetchData = queryParams =>
  dispatchRequest({
    url: '/api/statunits',
    queryParams,
    onSuccess: (dispatch, resp) => {
      dispatch(fetchDataSucceeded({ ...resp, queryObj: queryParams }))
      dispatch(fetchDataStateChanged(false))
    },
    onFail: (dispatch, error) => {
      dispatch(fetchDataFailed(error.message))
    },
    onStart: dispatch => dispatch(fetchDataStateChanged(true)),
  })

const deleteStatUnit = (type, id, queryParams, index, onFail) =>
  dispatchRequest({
    url: `/api/statunits/${type}/${id}`,
    method: 'delete',
    onSuccess: (dispatch) => {
      dispatch(fetchData(queryParams))
      NotificationManager.success(getLocalizeText('StatUnitDeleteSuccessfully'))
    },
    onFail: (_, error) => {
      onFail(error.message)
      NotificationManager.error(getLocalizeText('StatUnitDeleteError'))
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
  fetchDataFailed,
  deleteStatUnitSuccessed,
  clearError,
}
