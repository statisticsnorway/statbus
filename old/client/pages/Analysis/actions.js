import { createAction } from 'redux-act'
import { push } from 'react-router-redux'
import { pipe } from 'ramda'

import dispatchRequest from '/helpers/request'
import { navigateBack } from '/helpers/actionCreators'

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
const deleteAnalyzeQueueSucceeded = createAction('delete AnalyzeQueue succeeded')
const deleteAnalyzeQueue = id =>
  dispatchRequest({
    url: `api/analysisqueue/${id}`,
    method: 'delete',
    onSuccess: (dispatch) => {
      dispatch(deleteAnalyzeQueueSucceeded(id))
    },
  })
const fetchAnalysisLogs = queueId => queryParams =>
  dispatchRequest({
    url: `/api/analysisqueue/${queueId}/log`,
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

const fetchDetailsStarted = createAction('fetch analysis log details started')
const fetchDetailsSucceeded = createAction('fetch analysis log details succeeded')
const fetchDetailsFailed = createAction('fetch analysis log details failed')
const fetchDetails = logId =>
  dispatchRequest({
    url: `/api/analysisqueue/logs/${logId}`,
    onStart: dispatch => dispatch(fetchDetailsStarted()),
    onSuccess: (dispatch, resp) => {
      const { properties, permissions, ...logEntry } = resp
      dispatch(fetchDetailsSucceeded({
        logEntry,
        properties,
        permissions,
      }))
    },
    onFail: (dispatch, errors) => dispatch(fetchDetailsFailed(errors)),
  })

const submitDetails = (logId, queueId) => (data, formikBag) =>
  dispatchRequest({
    url: `/api/analysisqueue/logs/${logId}`,
    method: 'put',
    body: JSON.stringify({ ...data, permissions: formikBag.props.permissions }),
    onStart: () => formikBag.started(),
    onSuccess: dispatch => dispatch(push(`analysisqueue/${queueId}/log`)),
    onFail: (_, errors) => formikBag.failed(errors),
  })

const clearDetails = createAction('clear analysis log details')

export const queue = {
  fetchQueueStarted,
  fetchQueueSucceeded,
  fetchQueueFailed,
  fetchQueue,
  updateQueueFilter,
  deleteAnalyzeQueue,
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

export const details = {
  fetchDetails,
  submitDetails,
  clearDetails,
  navigateBack,
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
  fetchDetailsStarted,
  fetchDetailsSucceeded,
  fetchDetailsFailed,
  clearDetails,
  deleteAnalyzeQueueSucceeded,
}
