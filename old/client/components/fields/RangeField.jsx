import React, { useState, useCallback } from 'react'
import PropTypes from 'prop-types'
import { Input, Icon, Message } from 'semantic-ui-react'
import * as R from 'ramda'
import { hasValue } from '/helpers/validation'

const style = { width: '100%' }

export function RangeField({
  from: ambiguousFrom,
  to: ambiguousTo,
  onChange,
  delimiter,
  name,
  id: ambiguousId,
  label: labelKey,
  touched,
  error,
  errors: errorKeys,
  localize,
  popuplocalizedKey,
  ...restProps
}) {
  const label = labelKey !== undefined ? localize(labelKey) : undefined
  const hasErrors = touched && hasValue(errorKeys)
  const id = ambiguousId != null ? ambiguousId : name
  const [from, setFrom] = useState(Number(ambiguousFrom) || 0)
  const [to, setTo] = useState(Number(ambiguousTo) || 0)

  const handleChange = useCallback(
    (e, inputProps) => {
      const updatedValue = Number(inputProps.value) || 0
      if (inputProps.name === 'from') {
        setFrom(updatedValue)
      } else if (inputProps.name === 'to') {
        setTo(updatedValue)
      }
      const data = {
        ...restProps,
        from,
        to,
        [inputProps.name]: updatedValue,
        name: name != null ? name : inputProps.name,
      }
      onChange(e, data)
    },
    [onChange, name, restProps, from, to],
  )

  return (
    <div
      className="field"
      data-tooltip={popuplocalizedKey ? localize(popuplocalizedKey) : null}
      data-position="top left"
    >
      {label && <label htmlFor={id}>{label}</label>}
      <Input fluid>
        {from > to && (
          <Icon
            title={localize('RangeInputWrong')}
            name="exclamation circle"
            color="red"
            size="big"
          />
        )}
        &nbsp;&nbsp;
        <Input
          {...restProps}
          onChange={handleChange}
          type="number"
          style={style}
          name="from"
          label={localize('RangeFrom')}
          value={from}
        />
        &nbsp;&nbsp;{delimiter}&nbsp;&nbsp;
        <Input
          {...restProps}
          onChange={handleChange}
          type="number"
          style={style}
          name="to"
          label={localize('RangeTo')}
          value={to}
        />
      </Input>
      {hasErrors && <Message title={label} list={errorKeys.map(localize)} compact error />}
    </div>
  )
}

RangeField.propTypes = {
  from: PropTypes.number.isRequired,
  to: PropTypes.number.isRequired,
  onChange: PropTypes.func.isRequired,
  name: PropTypes.string,
  id: PropTypes.string,
  delimiter: PropTypes.string,
  label: PropTypes.string,
  touched: PropTypes.bool,
  error: PropTypes.bool,
  errors: PropTypes.arrayOf(PropTypes.string),
  localize: PropTypes.func,
  popuplocalizedKey: PropTypes.string,
}

RangeField.defaultProps = {
  name: undefined,
  id: undefined,
  delimiter: '—',
  label: undefined,
  touched: false,
  error: false,
  errors: [],
  localize: R.identity,
  popuplocalizedKey: undefined,
}
