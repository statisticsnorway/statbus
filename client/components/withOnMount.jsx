import React from 'react'
import PropTypes from 'prop-types'

const withOnMount = TargetComponent =>
  class extends React.Component {
    static propTypes = {
      onMount: PropTypes.func.isRequired,
    }

    componentDidMount() {
      this.props.onMount()
    }

    render() {
      const { onMount, ...props } = this.props
      return <TargetComponent {...props} />
    }
  }

export default withOnMount
