import { createReducer } from 'redux-act'

import * as actions from './actions'

const initialState = {
  soates: [],
  totalCount: 0,
  fetching: false,
  error: undefined,
  editRow: undefined,
  addingSoate: false,
}

const soates = createReducer(
  {
    [actions.fetchSoatesSuccessed]: (state, data) => ({
      ...state,
      soates: data.result,
      totalCount: data.totalCount,
      fetching: false,
      error: undefined,
    }),
    [actions.fetchSoatesFailed]: (state, data) => ({
      ...state,
      soates: [],
      totalCount: 0,
      fetching: false,
      error: data,
    }),
    [actions.fetchSoatesStarted]: state => ({
      ...state,
      fetching: true,
      error: undefined,
    }),
    [actions.toggleDeleteSoatesStarted]: state => ({
      ...state,
      fetching: true,
      error: undefined,
    }),
    [actions.toggleDeleteSoatesSuccessed]: (state, { id, isDeleted }) => ({
      ...state,
      soates: state.soates.map(x => x.id !== id ? x : { ...x, isDeleted }),
      error: undefined,
      fetching: false,
    }),
    [actions.toggleDeleteSoatesFailed]: (state, data) => ({
      ...state,
      error: data,
      fetching: false,
    }),
    [actions.editSoatesStarted]: state => ({
      ...state,
      fetching: true,
    }),
    [actions.editSoatesSuccessed]: (state, data) => ({
      ...state,
      error: undefined,
      fetching: false,
      soates: state.soates.map(v => (v.id === data.id ? data : v)),
      editRow: undefined,
    }),
    [actions.editSoatesFailed]: (state, data) => ({
      ...state,
      fetching: false,
      error: data,
    }),
    [actions.soatesEditorAction]: (state, data) => ({
      ...state,
      editRow: data,
    }),
    [actions.soateAddEditorAction]: (state, data) => ({
      ...state,
      addingSoate: data,
    }),
    [actions.addSoatesStarted]: state => ({
      ...state,
      fetching: true,
    }),
    [actions.addSoatesSuccessed]: (state, data) => ({
      ...state,
      error: undefined,
      fetching: false,
      soates: [data, ...state.soates],
      addingSoate: false,
    }),
    [actions.addSoatesFailed]: (state, data) => ({
      ...state,
      fetching: false,
      error: data,
    }),
  },
  initialState,
)

export default {
  soates,
}
