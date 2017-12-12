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

export default {
  fetchQueueStarted,
  fetchQueueSucceeded,
  fetchQueueFailed,
  fetchQueue,
  updateQueueFilter,
  setQuery,
  clear,
  editQueueItem,
}
