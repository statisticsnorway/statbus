import { lifecycle, withReducer } from 'recompose'
import { pipe, equals } from 'ramda'
import { connect } from 'react-redux'

import { changePageTitle } from '/helpers/config'
import Layout from './Layout.jsx'

const SET = 'SET'

const hooks = {
  componentWillReceiveProps(nextProps) {
    if (!equals(nextProps.location, nextProps.stateLocation.currentLocation)) {
      nextProps.dispatchAction({
        type: 'SET',
        location: { ...nextProps.location },
      })
      changePageTitle(nextProps.location.pathname)
    }
    if (!equals(nextProps.locale, this.props.locale)) {
      changePageTitle(nextProps.location.pathname)
    }
  },
  componentDidMount() {
    changePageTitle(this.props.location.pathname)
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

const mapStateToProps = state => ({
  locale: state.locale,
})

const enhance = withReducer('stateLocation', 'dispatchAction', locationReducer, {
  previousLocation: undefined,
  currentLocation: undefined,
})

export default pipe(lifecycle(hooks), enhance, connect(mapStateToProps))(Layout)
