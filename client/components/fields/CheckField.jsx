import React from 'react'
import { arrayOf, func, string, bool } from 'prop-types'
import { Message, Form } from 'semantic-ui-react'

const CheckField = ({
  id: ambiguousId,
  name,
  value,
  label: labelKey,
  title: titleKey,
  touched,
  error,
  errors: errorKeys,
  setFieldValue,
  localize,
  ...restProps
}) => {
  const label = localize(labelKey)
  const title = titleKey ? localize(titleKey) : label
  const id = ambiguousId != null ? ambiguousId : name
  const hasErrors = touched && errorKeys.length !== 0
  const props = {
    ...restProps,
    id,
    name,
    label,
    title,
    checked: value,
    onChange: (_, { checked: nextValue }) => setFieldValue(name, nextValue),
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
  name: string.isRequired,
  label: string.isRequired,
  title: string,
  value: bool,
  touched: bool.isRequired,
  error: bool,
  errors: arrayOf(string),
  setFieldValue: func.isRequired,
  localize: func.isRequired,
}

CheckField.defaultProps = {
  id: undefined,
  value: false,
  title: undefined,
  error: false,
  errors: [],
}

export default CheckField
