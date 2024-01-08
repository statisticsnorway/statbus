import { createAction } from 'redux-act'
import { push } from 'react-router-redux'
import dispatchRequest from '/helpers/request'
import { pipe } from 'ramda'

import { navigateBack } from '/helpers/actionCreators'
import { castEmptyOrNull } from '/helpers/modelProperties'

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

const deleteDataSourceQueueSucceeded = createAction('delete DataSourceQueue succeeded')
const deleteDataSourceQueue = id =>
  dispatchRequest({
    url: `api/datasourcesqueue/${id}`,
    method: 'delete',
    onSuccess: (dispatch) => {
      dispatch(deleteDataSourceQueueSucceeded(id))
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

const parseUnit = pipe(
  x => JSON.parse(x),
  parsed => Object.entries(parsed),
  entries => entries.reduce((acc, [k, v]) => ({ ...acc, [k]: castEmptyOrNull(v) }), {}),
)

const fetchLogEntry = id =>
  dispatchRequest({
    url: `/api/datasourcesqueue/logs/${id}`,
    onSuccess: (dispatch, resp) => {
      const { unit, statUnitType, properties, permissions, ...info } = resp
      dispatch(fetchLogEntrySucceeded({
        unit: parseUnit(unit),
        type: statUnitType,
        properties,
        permissions,
        info: {
          ...info,
          rawUnit: JSON.parse(info.rawUnit),
        },
      }))
    },
    onFail: (dispatch, errors) => {
      dispatch(fetchLogEntryFailed(errors))
    },
  })

const submitLogEntry = (logId, queueId) => (formData, formikBag) =>
  dispatchRequest({
    url: `/api/datasourcesqueue/logs/${logId}`,
    method: 'put',
    body: JSON.stringify({
      ...formikBag.props.unit,
      ...formData,
      permissions: formikBag.props.permissions,
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

const fetchActivitiesDetailsSucceeded = createAction('fetch activities details succeeded')
const fetchActivitiesDetailsFailed = createAction('fetch activities details failed')

export const fetchActivitiesDetails = (queueId, regId) =>
  dispatchRequest({
    url: `/api/datasourcesqueue/queue/${queueId}/logs/${regId}`,
    onSuccess: (dispatch, resp) => {
      dispatch(fetchActivitiesDetailsSucceeded(resp))
    },
    onFail: (dispatch, errors) => {
      dispatch(fetchActivitiesDetailsFailed(errors))
    },
  })

const deleteLogSucceeded = createAction('delete log succeeded')
const deleteLog = logId =>
  dispatchRequest({
    url: `api/datasourcesqueue/logs/${logId}`,
    method: 'delete',
    onSuccess: (dispatch) => {
      dispatch(deleteLogSucceeded(logId))
    },
  })

export const list = {
  fetchQueue,
  setQuery,
  updateQueueFilter,
  clear,
  deleteDataSourceQueue,
}

export const log = {
  fetchLog,
  clear,
  deleteLog,
}

export const details = {
  fetchLogEntry,
  submitLogEntry,
  clear,
  navigateBack,
  fetchActivitiesDetails,
  fetchActivitiesDetailsSucceeded,
  fetchActivitiesDetailsFailed,
}

export default {
  updateQueueFilter,
  fetchQueueStarted,
  fetchQueueFailed,
  fetchQueueSucceeded,
  clear,
  deleteDataSourceQueueSucceeded,
  setQuery,
  fetchLogStarted,
  fetchLogFailed,
  fetchLogSucceeded,
  fetchLogEntryStarted,
  fetchLogEntrySucceeded,
  fetchLogEntryFailed,
  fetchActivitiesDetails,
  fetchActivitiesDetailsSucceeded,
  fetchActivitiesDetailsFailed,
  deleteLogSucceeded,
}
