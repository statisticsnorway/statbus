import React from 'react'
import PropTypes from 'prop-types'

const withOnUnmount = TargetComponent =>
  class extends React.Component {
    static propTypes = {
      onUnmount: PropTypes.func.isRequired,
    }

    componentWillUnmount() {
      this.props.onUnmount()
    }

    render() {
      const { onUnmount, ...props } = this.props
      return <TargetComponent {...props} />
    }
  }

export default withOnUnmount
