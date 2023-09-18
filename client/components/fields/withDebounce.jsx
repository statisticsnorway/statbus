import React, { useState, useEffect, useCallback } from 'react'
import debounce from 'lodash/debounce'
import R from 'ramda'
import tryPersist from 'helpers/tryPersist'

const DebounceFieldWrapper = (Component, delay = 200) => (props) => {
  const [state, setState] = useState({
    pending: false,
    e: undefined,
    data: props,
  })

  const immediateChange = useCallback(() => {
    props.onChange(state.e, state.data)
  }, [state.e, state.data, props])

  const tryImmediateChange = useCallback(() => {
    if (state.pending) {
      setState(prevState => ({ ...prevState, pending: false }), immediateChange)
    }
  }, [immediateChange, state.pending])

  const delayedChange = useCallback(debounce(tryImmediateChange, delay), [
    delay,
    tryImmediateChange,
  ])

  const onChange = (e, data) => {
    tryPersist(e)
    setState({ e, data, pending: true })
    delayedChange()
  }

  const onBlur = (e) => {
    if (state.pending) delayedChange.flush()
    tryPersist(e)
    setTimeout(() => props.onBlur(e), delay)
  }

  const onKeyDown = (e) => {
    tryPersist(e)
    if (state.pending) {
      if (e.keyCode === 13) delayedChange.flush()
    } else if (props.onKeyDown) {
      props.onKeyDown(e)
    }
  }

  useEffect(() => {
    const nextValueEquals = R.equals(props.value)
    if (!nextValueEquals(props.value) && !nextValueEquals(state.data.value)) {
      setState(prevState => ({ ...prevState, data: props, pending: false }))
      delayedChange.cancel()
    }
  }, [props, state.data.value, delayedChange])

  const newProps = {
    ...props,
    value: state.data.value,
  }

  if (props.onChange !== undefined) newProps.onChange = onChange
  if (props.onBlur !== undefined) newProps.onBlur = onBlur
  if (props.onKeyDown !== undefined) newProps.onKeyDown = onKeyDown

  return <Component {...newProps} />
}

export default DebounceFieldWrapper
