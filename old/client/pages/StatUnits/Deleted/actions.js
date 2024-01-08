import { createAction } from 'redux-act'
import { pipe } from 'ramda'
import { NotificationManager } from 'react-notifications'
import { getLocalizeText } from '/helpers/locale'
import dispatchRequest from '/helpers/request'
import { updateFilter, setQuery } from '../actions.js'

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
const restore = (type, regId, queryParams, index, onFail) =>
  dispatchRequest({
    method: 'delete',
    url: '/api/statunits/deleted',
    queryParams: { type, regId },
    onSuccess: (dispatch) => {
      setTimeout(() => {
        dispatch(fetchData(queryParams))
      }, 250)
      NotificationManager.success(getLocalizeText('StatisticalUnitRestoredSuccessfully'))
    },
    onFail: (_, error) => {
      onFail(error.message)
      NotificationManager.error(getLocalizeText('StatUnitRestoreError'))
    },
  })

export const clearSearchFormForDeleted = createAction('clear search form for deleted')
export const setSearchConditionForDeleted = createAction('set search condition for deleted')

export default {
  updateFilter,
  setQuery,
  fetchData,
  restore,
  restoreSucceeded,
  clearSearchFormForDeleted,
  setSearchConditionForDeleted,
}
