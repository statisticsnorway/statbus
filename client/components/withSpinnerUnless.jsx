import React from 'react'
import { Loader } from 'semantic-ui-react'

const withSpinnerUnless = assert => TargetComponent =>
  class extends React.Component {
    state = {
      asserted: assert(this.props),
    }

    componentWillReceiveProps(nextProps) {
      if (!this.state.asserted) {
        if (assert(nextProps)) {
          this.setState({ asserted: true })
        }
      }
    }

    render() {
      return this.state.asserted
        ? <TargetComponent {...this.props} />
        : <Loader active />
    }
  }

export default withSpinnerUnless
