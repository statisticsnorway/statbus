import React from 'react'
import { arrayOf, func, string, bool } from 'prop-types'
import { Message, Form } from 'semantic-ui-react'

const CheckField = ({
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
}) => {
  const label = labelKey !== undefined ? localize(labelKey) : undefined
  const title = titleKey ? localize(titleKey) : label
  const id =
    ambiguousId != null ? ambiguousId : ambiguousName != null ? ambiguousName : 'CheckField'
  const hasErrors = touched !== false && errorKeys.length !== 0
  const props = {
    ...restProps,
    id,
    name: ambiguousName,
    label,
    title,
    checked: value,
    onChange: (e, { checked, ...inputProps }) => onChange(e, { ...inputProps, value: checked }),
    error: error || hasErrors,
  }
  return (
    <div className="field">
      <label htmlFor={id}>&nbsp;</label>
      <Form.Checkbox {...props} />
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

export default CheckField
