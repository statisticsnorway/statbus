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
  }, [props, state.e, state.data])

  const tryImmediateChange = useCallback(() => {
    if (state.pending) {
      setState(
        prevState => ({
          ...prevState,
          pending: false,
        }),
        immediateChange,
      )
    }
  }, [state.pending, immediateChange])

  const delayedChange = useCallback(debounce(tryImmediateChange, delay), [
    tryImmediateChange,
    delay,
  ])

  const onChange = (e, data) => {
    tryPersist(e)
    setState(prevState => ({
      ...prevState,
      e,
      data,
      pending: true,
    }))
    delayedChange()
  }

  const onBlur = (e) => {
    if (state.pending) delayedChange.flush()
    tryPersist(e)
    setTimeout(() => {
      props.onBlur(e)
    }, delay)
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
    if (!nextValueEquals(state.data.value) && !nextValueEquals(props.value)) {
      setState(prevState => ({
        ...prevState,
        data: props,
        pending: false,
      }))
      delayedChange.cancel()
    }
  }, [props, state.data.value, state.pending, delayedChange])

  const componentProps = {
    ...props,
    value: state.data.value,
    onChange,
    onBlur,
    onKeyDown,
  }

  return <Component {...componentProps} />
}

export default DebounceFieldWrapper
