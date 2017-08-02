import { createAction } from 'redux-act'
import { push } from 'react-router-redux'
import dispatchRequest from 'helpers/request'
import R from 'ramda'

const updateQueueFilter = createAction('update search dataSourcesQueue form')
const fetchQueueStarted = createAction('fetch regions started')
const fetchQueueFailed = createAction('fetch DataSourceQueue failed')
const fetchQueueSucceeded = createAction('fetch DataSourceQueue successed')
const fetchLogStarted = createAction('fetch regions started')
const fetchLogFailed = createAction('fetch DataSourceQueue failed')
const fetchLogSucceeded = createAction('fetch DataSourceQueue successed')
const clear = createAction('clear filter on DataSourceQueue')

const setQuery = pathname => query => (dispatch) => {
  R.pipe(updateQueueFilter, dispatch)(query)
  const status = query.status === 'any' ? undefined : query.status
  R.pipe(push, dispatch)({ pathname, query: { ...query, status } })
}

const fetchQueue = queryParams =>
  dispatchRequest({
    url: '/api/datasourcesqueue',
    queryParams,
    onSuccess: (dispatch, resp) => {
      dispatch(fetchQueueSucceeded({ ...resp, queryObj: queryParams }))
    },
    onFail: (dispatch, errors) => {
      dispatch(fetchQueueFailed(errors))
    },
  })

const fetchLog = dataSourceId => queryParams =>
  dispatchRequest({
    url: `/api/datasourcesqueue/${dataSourceId}`,
    queryParams,
    onSuccess: (dispatch, resp) => {
      dispatch(fetchLogSucceeded(resp))
    },
    onFail: (dispatch, errors) => {
      dispatch(fetchLogFailed(errors))
    },
  })

export const list = {
  fetchQueue,
  setQuery,
  updateQueueFilter,
  clear,
}

export const log = {
  fetchLog,
  clear,
}

export default {
  updateQueueFilter,
  fetchQueueStarted,
  fetchQueueFailed,
  fetchQueueSucceeded,
  clear,
  setQuery,
  fetchLogStarted,
  fetchLogFailed,
  fetchLogSucceeded,
}
