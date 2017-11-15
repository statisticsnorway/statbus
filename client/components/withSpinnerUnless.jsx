import React from 'react'
import { Loader } from 'semantic-ui-react'

const withSpinnerUnless = assert => TargetComponent =>
  class SpinnerWrapper extends React.Component {
    state = {
      asserted: assert(this.props),
    }

    componentWillReceiveProps(nextProps) {
      const nextAsserted = assert(nextProps)
      if (this.state.asserted !== nextAsserted) {
        this.setState({ asserted: nextAsserted })
      }
    }

    render() {
      return this.state.asserted ? <TargetComponent {...this.props} /> : <Loader active />
    }
  }

export default withSpinnerUnless
