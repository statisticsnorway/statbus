import { createAction } from 'redux-act'
import { getLocalizeText } from '/helpers/locale'
import dispatchRequest from '/helpers/request'

import { updateFilter, setQuery } from '../actions.js'

export const fetchDataSucceeded = createAction('fetch StatUnits succeeded')

export const fetchDataFailed = createAction('fetch StatUnits failed')

export const clear = createAction('clear formData filter')

export const fetchDataStateChanged = createAction('fetch StatUnits status changed')

export const fetchLookupSucceeded = createAction('fetch Lookup succeeded')

export const deleteStatUnitSuccessed = createAction('delete StatUnit succeeded')

export const setSearchCondition = createAction('set search condition')

export const clearError = createAction('clear error')

const redirectToIndex = () => {
  window.location.href = '/'
}

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

  export const deleteStatUnit = (type, id) => {
    return fetch(`/api/statunits/${type}/${id}`, {
        method: 'DELETE',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'same-origin'
      })
    .then(response => {
      if (response.status >= 200 && response.status < 300) {
        redirectToIndex()
      } else if (response.status === 400 || response.status === 404 || response.status === 500) {
        // Here we are throwing a general error message text instead of a specific message text related to the error,
        // this is because the back-end does not return a specific message text related to the error
        throw new Error(getLocalizeText('StatUnitDeleteError'));
      }
    })
    .catch(() => {
      throw new Error(getLocalizeText('StatUnitDeleteError'));
    });
  };

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
