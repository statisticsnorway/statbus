import { createAction } from 'redux-act'
import { push } from 'react-router-redux'
import dispatchRequest from 'helpers/request'
import { pipe } from 'ramda'

const fetchQueueStarted = createAction('fetch Analysis Queue started')
const fetchQueueFailed = createAction('fetch Analysis Queue failed')
const fetchQueueSucceeded = createAction('fetch Analysis Queue successed')
const updateQueueFilter = createAction('update search Analysis Queue form')
const clear = createAction('clear filter on DataSourceQueue')
const editQueueItem = createAction('edit Queue Item')
const fetchAnalysisLogsStarted = createAction('fetch Analysis Logs started')
const fetchAnalysisLogsFailed = createAction('fetch Analysis Logs failed')
const fetchAnalysisLogsSucceeded = createAction('fetch Analysis Logs successed')

const fetchQueue = queryParams =>
  dispatchRequest({
    url: '/api/analysisqueue',
    queryParams,
    onSuccess: (dispatch, resp) => {
      dispatch(fetchQueueSucceeded({ ...resp }))
    },
    onFail: (dispatch, errors) => {
      dispatch(fetchQueueFailed(errors))
    },
  })

const fetchAnalysisLogs = queueId => queryParams =>
  dispatchRequest({
    url: `/api/analysisqueue/log/${queueId}`,
    queryParams,
    onSuccess: (dispatch, resp) => {
      dispatch(fetchAnalysisLogsSucceeded({ ...resp }))
    },
    onFail: (dispatch, errors) => {
      dispatch(fetchAnalysisLogsFailed(errors))
    },
  })

const setQuery = pathname => query => (dispatch) => {
  pipe(updateQueueFilter, dispatch)(query)
  pipe(push, dispatch)({ pathname, query })
}

const submitItem = data =>
  dispatchRequest({
    url: '/api/analysisqueue',
    method: 'post',
    body: data,
    onSuccess: (dispatch) => {
      dispatch(push('/analysisqueue'))
    },
  })

export const queue = {
  fetchQueueStarted,
  fetchQueueSucceeded,
  fetchQueueFailed,
  fetchQueue,
  updateQueueFilter,
  setQuery,
  clear,
}

export const create = {
  editQueueItem,
  submitItem,
  clear,
}

export const logs = {
  fetchAnalysisLogs,
}

export default {
  fetchQueueStarted,
  fetchQueueSucceeded,
  fetchQueueFailed,
  fetchQueue,
  updateQueueFilter,
  setQuery,
  clear,
  editQueueItem,
  fetchAnalysisLogs,
  fetchAnalysisLogsSucceeded,
  fetchAnalysisLogsStarted,
  fetchAnalysisLogsFailed,
}
