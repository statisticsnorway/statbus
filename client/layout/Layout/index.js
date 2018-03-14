import { lifecycle, withReducer } from 'recompose'
import { pipe, equals } from 'ramda'

import Layout from './Layout'

const SET = 'SET'

const hooks = {
  componentWillReceiveProps(nextProps) {
    if (!equals(nextProps.location, nextProps.stateLocation.currentLocation)) {
      nextProps.dispatchAction({
        type: 'SET',
        location: { ...nextProps.location },
      })
    }
  },
}

const locationReducer = (state, action) => {
  switch (action.type) {
    case SET:
      return {
        previousLocation: state.currentLocation,
        currentLocation: action.location,
      }
    default:
      return state
  }
}

const enhance = withReducer('stateLocation', 'dispatchAction', locationReducer, {
  previousLocation: undefined,
  currentLocation: undefined,
})

export default pipe(lifecycle(hooks), enhance)(Layout)
