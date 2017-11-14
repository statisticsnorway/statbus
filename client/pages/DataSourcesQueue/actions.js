import { createAction } from 'redux-act'
import { push } from 'react-router-redux'
import dispatchRequest from 'helpers/request'
import { pipe } from 'ramda'

import { navigateBack } from 'helpers/actionCreators'
import { castEmptyOrNull } from 'helpers/modelProperties'
import { createJsonReviver, toCamelCase } from 'helpers/string'

const updateQueueFilter = createAction('update search dataSourcesQueue form')
const fetchQueueStarted = createAction('fetch regions started')
const fetchQueueFailed = createAction('fetch DataSourceQueue failed')
const fetchQueueSucceeded = createAction('fetch DataSourceQueue successed')
const fetchLogStarted = createAction('fetch regions started')
const fetchLogFailed = createAction('fetch DataSourceQueue failed')
const fetchLogSucceeded = createAction('fetch DataSourceQueue successed')
const fetchLogEntryStarted = createAction('fetch log entry started')
const fetchLogEntrySucceeded = createAction('fetch log entry succeeded')
const fetchLogEntryFailed = createAction('fetch log entry failed')
const clear = createAction('clear filter on DataSourceQueue')

const setQuery = pathname => query => (dispatch) => {
  pipe(updateQueueFilter, dispatch)(query)
  const status = query.status === 'any' ? undefined : query.status
  pipe(push, dispatch)({ pathname, query: { ...query, status } })
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
    url: `/api/datasourcesqueue/${dataSourceId}/log`,
    queryParams,
    onSuccess: (dispatch, resp) => {
      dispatch(fetchLogSucceeded(resp))
    },
    onFail: (dispatch, errors) => {
      dispatch(fetchLogFailed(errors))
    },
  })

const camelCaseReviver = createJsonReviver(toCamelCase)

const fetchLogEntry = id =>
  dispatchRequest({
    url: `/api/datasourcesqueue/log/${id}`,
    onSuccess: (dispatch, resp) => {
      const { unit: rawUnit, statUnitType: type, properties, dataAccess, ...info } = resp
      const unit = Object.entries(JSON.parse(rawUnit, camelCaseReviver)).reduce(
        (acc, [k, v]) => ({ ...acc, [k]: castEmptyOrNull(v) }),
        {},
      )
      dispatch(fetchLogEntrySucceeded({ info, unit, type, properties, dataAccess }))
    },
    onFail: (dispatch, errors) => {
      dispatch(fetchLogEntryFailed(errors))
    },
  })

const submitLogEntry = (logId, queueId) => (formData, formikBag) =>
  dispatchRequest({
    url: `/api/datasourcesqueue/log/${logId}`,
    method: 'put',
    body: JSON.stringify({
      ...formikBag.props.unit,
      ...formData,
      dataAccess: formikBag.props.dataAccess,
    }),
    onStart: () => {
      formikBag.started()
    },
    onSuccess: (dispatch) => {
      dispatch(push(`datasourcesqueue/${queueId}/log`))
    },
    onFail: (_, errors) => {
      formikBag.failed(errors)
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

export const details = {
  fetchLogEntry,
  submitLogEntry,
  clear,
  navigateBack,
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
  fetchLogEntryStarted,
  fetchLogEntrySucceeded,
  fetchLogEntryFailed,
}
