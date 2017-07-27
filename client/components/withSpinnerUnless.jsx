import React from 'react'
import PropTypes from 'prop-types'
import { Loader } from 'semantic-ui-react'
import { view, equals } from 'ramda'

const getView = _ => _

const withSpinnerUnless = TargetComponent =>
  class extends React.Component {
    static propTypes = {
      propPaths: PropTypes.arrayOf(PropTypes.string).isRequired,
    }

    state = {
      loaded: false,
    }

    componentWillReceiveProps({ nextPropPaths, ...nextProps }) {
      if (equals(this.getView, getView(nextPropPaths, nextProps))) {
        this.setState({ loaded: false })
      }
    }

    getView() {
      const { propPaths, ...props } = this.props
      return getView(propPaths, props)
    }

    render() {
      const { propPaths, ...props } = this.props
      return this.state.loaded
        ? <TargetComponent {...props} />
        : <Loader active />
    }
  }

export default withSpinnerUnless
