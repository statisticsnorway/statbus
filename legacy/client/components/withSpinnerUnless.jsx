import React from 'react'
import { shape, string, func } from 'prop-types'

import { Loader } from 'semantic-ui-react'

const withSpinnerUnless = assert => TargetComponent =>
  class SpinnerWrapper extends React.Component {
    static propTypes = {
      errors: shape({
        message: string,
      }),
      localize: func.isRequired,
    }

    static defaultProps = {
      errors: undefined,
    }

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
      if (this.props.errors) {
        return <div>{this.props.localize(this.props.errors.message)}</div>
      }
      return this.state.asserted ? <TargetComponent {...this.props} /> : <Loader active />
    }
  }

export default withSpinnerUnless
