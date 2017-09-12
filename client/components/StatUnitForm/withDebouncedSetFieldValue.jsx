import React from 'react'
import debounce from 'lodash/debounce'

export default (Target, delay = 250) =>
  class DebouncedFieldWrapper extends React.Component {

    static propTypes = Target.propTypes

    static defaultProps = Target.defaultProps

    state = {
      pending: false,
      value: this.props.value,
    }

    componentWillReceiveProps(nextProps) {
      if (nextProps.value !== this.props.value && nextProps.value !== this.state.value) {
        this.setState(
          { value: nextProps.value, pending: false },
          this.delayedSetFieldValue.cancel,
        )
      }
    }

    immediateSetFieldValue = () => {
      this.props.setFieldValue(
        this.props.name,
        this.state.value,
      )
    }

    tryImmediateSetFieldValue = () => {
      if (this.state.pending) {
        this.setState(
          { pending: false },
          this.immediateSetFieldValue,
        )
      }
    }

    delayedSetFieldValue = debounce(
      this.tryImmediateSetFieldValue,
      delay,
    )

    handleSetFieldValue = (_, value) => {
      this.setState(
        { value, pending: true },
        this.delayedSetFieldValue,
      )
    }

    render() {
      const { value: _, setFieldValue: __, ...props } = this.props
      const { value } = this.state
      return <Target {...props} value={value} setFieldValue={this.handleSetFieldValue} />
    }
  }
