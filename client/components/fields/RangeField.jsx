import React from 'react'
import PropTypes from 'prop-types'
import { Input, Icon, Message } from 'semantic-ui-react'
import R from 'ramda'

import { hasValue } from 'helpers/validation'

const style = { width: '100%' }

export default function RangeField({
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
  ...restProps
}) {
  const label = labelKey !== undefined ? localize(labelKey) : undefined
  const hasErrors = touched && hasValue(errorKeys)
  const id = ambiguousId != null ? ambiguousId : name
  const from = Number(ambiguousFrom) || 0
  const to = Number(ambiguousTo) || 0
  const props = {
    ...restProps,
    onChange: (e, inputProps) => {
      const data = {
        ...restProps,
        from,
        to,
        [inputProps.name]: Number(inputProps.value) || 0,
        name: name != null ? name : inputProps.name,
      }
      onChange(e, data)
    },
    type: 'number',
    style,
  }
  return (
    <div className="field">
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
        <Input {...props} name="from" label={localize('RangeFrom')} value={from} />
        &nbsp;&nbsp;{delimiter}&nbsp;&nbsp;
        <Input {...props} name="to" label={localize('RangeTo')} value={to} />
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
}
