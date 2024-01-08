import { createAction } from 'redux-act'
import { push } from 'react-router-redux'
import * as R from 'ramda'

import { navigateBack } from '/helpers/actionCreators'
import dispatchRequest from '/helpers/request'
import * as fns from './predicateFns.js'

const updateFilter = createAction('update sample frames search query')
const setQuery = pathname => query => (dispatch) => {
  R.pipe(updateFilter, dispatch)(query)
  R.pipe(push, dispatch)({ pathname, query })
}

const getSampleFramesStarted = createAction('get sample frames started')
const getSampleFramesSucceeded = createAction('get sample frames succeeded')
const getSampleFramesFailed = createAction('get sample frames failed')
const getSampleFrames = queryParams =>
  dispatchRequest({
    url: 'api/sampleframes',
    queryParams,
    onSuccess: (dispatch, resp) => dispatch(getSampleFramesSucceeded(resp)),
    onFail: (dispatch, err) => dispatch(getSampleFramesFailed(err)),
  })

const clearSearchForm = createAction('clear sample frame search form')

const deleteSampleFrameSucceeded = createAction('delete sample frame succeeded')
const deleteSampleFrame = id =>
  dispatchRequest({
    url: `api/sampleframes/${id}`,
    method: 'delete',
    onSuccess: dispatch => dispatch(deleteSampleFrameSucceeded(id)),
  })

const updatePredicate = R.over(R.lensProp('predicate'))
const fromVm = R.pipe(x => ({ predicate: x }), fns.fromVm)
const toVm = R.pipe(fns.toVm, R.prop('predicate'))

const getSampleFrameStarted = createAction('get sample frame started')
const getSampleFrameSucceeded = createAction('get sample frame succeeded')
const getSampleFrameFailed = createAction('get sample frame failed')
const getSampleFrame = id =>
  dispatchRequest({
    url: `api/sampleframes/${id}`,
    onSuccess: (dispatch, resp) =>
      R.pipe(updatePredicate(fromVm), getSampleFrameSucceeded, dispatch)(resp),
    onFail: (dispatch, err) => dispatch(getSampleFrameFailed(err)),
  })

const postSampleFrame = (body, formikBag) =>
  dispatchRequest({
    url: 'api/sampleframes',
    method: 'post',
    body: updatePredicate(toVm, body),
    onStart: () => formikBag.started(),
    onSuccess: dispatch => dispatch(push('sampleframes')),
    onFail: (_, err) => formikBag.failed(err),
  })

const putSampleFrame = (id, body, formikBag) =>
  dispatchRequest({
    url: `api/sampleframes/${id}`,
    method: 'put',
    body: updatePredicate(toVm, body),
    onStart: () => formikBag.started(),
    onSuccess: dispatch => dispatch(push('sampleframes')),
    onFail: (_, err) => formikBag.failed(err),
  })

const clearEditForm = createAction('clear sample frame edit form')

export const list = {
  getSampleFrames,
  updateFilter,
  setQuery,
  deleteSampleFrame,
  clearSearchForm,
}

export const create = {
  postSampleFrame,
  navigateBack,
}

export const edit = {
  putSampleFrame,
  navigateBack,
  clearEditForm,
  getSampleFrame,
}

export default {
  updateFilter,
  getSampleFramesStarted,
  getSampleFramesSucceeded,
  getSampleFramesFailed,
  getSampleFrameStarted,
  getSampleFrameSucceeded,
  getSampleFrameFailed,
  deleteSampleFrameSucceeded,
  clearSearchForm,
  clearEditForm,
}
