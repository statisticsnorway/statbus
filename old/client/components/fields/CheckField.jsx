import React from 'react'
import { arrayOf, func, string, bool } from 'prop-types'
import { Message, Form } from 'semantic-ui-react'

export function CheckField({
  id: ambiguousId,
  name: ambiguousName,
  value,
  onChange,
  label: labelKey,
  title: titleKey,
  touched,
  error,
  errors: errorKeys,
  localize,
  popuplocalizedKey,
  ...restProps
}) {
  const label = labelKey !== undefined ? localize(labelKey) : undefined
  const title = titleKey ? localize(titleKey) : label
  const id =
    ambiguousId != null ? ambiguousId : ambiguousName != null ? ambiguousName : 'CheckField'
  const hasErrors = touched !== false && errorKeys.length !== 0

  const handleChange = (e, { checked, ...inputProps }) => {
    onChange(e, { ...inputProps, value: checked })
  }

  return (
    <div
      className="field"
      data-tooltip={popuplocalizedKey ? localize(popuplocalizedKey) : null}
      data-position="top left"
    >
      <label htmlFor={id}>&nbsp;</label>
      <Form.Checkbox
        id={id}
        name={ambiguousName}
        label={label}
        title={title}
        checked={value}
        onChange={handleChange}
        error={error || hasErrors}
        {...restProps}
      />
      {hasErrors && <Message title={label} list={errorKeys.map(localize)} compact error />}
    </div>
  )
}

CheckField.propTypes = {
  id: string,
  name: string,
  label: string,
  title: string,
  value: bool,
  onChange: func.isRequired,
  touched: bool,
  error: bool,
  errors: arrayOf(string),
  localize: func.isRequired,
  popuplocalizedKey: string,
}

CheckField.defaultProps = {
  id: undefined,
  name: undefined,
  value: false,
  label: undefined,
  title: undefined,
  touched: undefined,
  error: false,
  errors: [],
  popuplocalizedKey: undefined,
}
