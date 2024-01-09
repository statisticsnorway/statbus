import { createReducer } from 'redux-act'

import actions from './actions.js'

const defaultState = {
  list: {
    formData: { wildcard: '' },
    result: [],
    totalCount: 0,
    fetching: false,
    errors: undefined,
  },
  edit: {
    formData: undefined,
    isFetching: false,
    isSubmitting: false,
    errors: undefined,
    isEdit: true,
  },
}

const listHandlers = {
  [actions.updateFilter]: (state, formData) => ({
    ...state,
    list: {
      ...state.list,
      formData: { ...state.list.formData, ...formData },
    },
  }),
  [actions.getSampleFramesStarted]: state => ({
    ...state,
    list: {
      ...state.list,
      fetching: true,
      errors: undefined,
    },
  }),
  [actions.getSampleFramesSucceeded]: (state, data) => ({
    ...state,
    list: {
      ...state.list,
      ...data,
      fetching: false,
      errors: undefined,
    },
  }),
  [actions.getSampleFramesFailed]: (state, errors) => ({
    ...state,
    list: {
      ...state.list,
      errors,
      fetching: false,
    },
  }),
  [actions.deleteSampleFrameSucceeded]: (state, id) => ({
    ...state,
    list: {
      ...state.list,
      result: state.list.result.filter(x => x.id !== id),
      totalCount: state.list.totalCount - 1,
    },
  }),
  [actions.clearSearchForm]: state => ({
    ...state,
    list: defaultState.list,
  }),
}

const editHandlers = {
  [actions.getSampleFrameStarted]: state => ({
    ...state,
    edit: {
      ...state.edit,
      formData: undefined,
      isFetching: true,
    },
  }),
  [actions.getSampleFrameSucceeded]: (state, formData) => ({
    ...state,
    edit: {
      ...state.edit,
      formData,
      isFetching: false,
    },
  }),
  [actions.getSampleFrameFailed]: (state, errors) => ({
    ...state,
    edit: {
      ...state.edit,
      formData: undefined,
      isFetching: false,
      errors,
    },
  }),
  [actions.clearEditForm]: state => ({
    ...state,
    edit: defaultState.edit,
  }),
}

export default createReducer({ ...listHandlers, ...editHandlers }, defaultState)
