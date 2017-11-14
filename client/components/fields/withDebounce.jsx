import React from 'react'
import debounce from 'lodash/debounce'

export default (Target, delay = 200) =>
  class DebounceFieldWrapper extends React.Component {
    static propTypes = Target.propTypes

    static defaultProps = Target.defaultProps

    static displayName = `Debounced(${Target.displayName || Target.name || 'Field'})`

    state = {
      pending: false,
      value: this.props.value,
    }

    componentWillReceiveProps(nextProps) {
      if (nextProps.value !== this.props.value && nextProps.value !== this.state.value) {
        this.setState({ value: nextProps.value, pending: false }, this.delayedSetFieldValue.cancel)
      }
    }

    componentWillUnmount() {
      if (this.state.pending) this.delayedSetFieldValue.flush()
      clearTimeout(this.handleBlurTimeout)
    }

    immediateSetFieldValue() {
      this.props.setFieldValue(this.props.name, this.state.value)
    }

    tryImmediateSetFieldValue() {
      if (this.state.pending) {
        this.setState({ pending: false }, this.immediateSetFieldValue)
      }
    }

    delayedSetFieldValue = debounce(this.tryImmediateSetFieldValue, delay)

    handleSetFieldValue = (_, value) => {
      this.setState({ value, pending: true }, this.delayedSetFieldValue)
    }

    handleBlur = (event) => {
      if (this.state.pending) this.delayedSetFieldValue.flush()
      event.persist()
      this.handleBlurTimeout = setTimeout(() => this.props.onBlur(event), delay)
    }

    handleKeyDown = (event) => {
      event.persist()
      if (this.state.pending) {
        if (event.keyCode === 13) this.delayedSetFieldValue.flush()
      } else if (this.props.onKeyDown) {
        this.props.onKeyDown(event)
      }
    }

    render() {
      const { value: _, setFieldValue: __, onBlur: ___, onKeyDown: ____, ...props } = this.props
      const { value } = this.state
      return (
        <Target
          {...props}
          value={value}
          setFieldValue={this.handleSetFieldValue}
          onBlur={this.handleBlur}
          onKeyDown={this.handleKeyDown}
        />
      )
    }
  }
