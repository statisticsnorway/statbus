import React from 'react'
import { arrayOf, bool, func, number, oneOfType, string } from 'prop-types'
import { Message, Form } from 'semantic-ui-react'

const TextField = ({
  name,
  value,
  label: labelKey,
  title: titleKey,
  placeholder: placeholderKey,
  touched,
  error,
  errors: errorKeys,
  setFieldValue,
  localize,
  ...restProps
}) => {
  const label = localize(labelKey)
  const title = titleKey ? localize(titleKey) : label
  const hasErrors = touched && errorKeys.length !== 0
  const props = {
    ...restProps,
    value: value !== null ? value : '',
    error: error || hasErrors,
    name,
    label,
    title,
    placeholder: placeholderKey ? localize(placeholderKey) : label,
    onChange: (_, { value: nextValue }) => setFieldValue(name, nextValue),
  }
  return (
    <div className="field">
      <Form.Input {...props} />
      {hasErrors && <Message title={label} list={errorKeys.map(localize)} compact error />}
    </div>
  )
}

TextField.propTypes = {
  name: string.isRequired,
  label: string.isRequired,
  title: string,
  placeholder: string,
  value: oneOfType([number, string]),
  touched: bool.isRequired,
  error: bool,
  errors: arrayOf(string),
  setFieldValue: func.isRequired,
  localize: func.isRequired,
}

TextField.defaultProps = {
  value: '',
  title: undefined,
  placeholder: undefined,
  error: false,
  errors: [],
}

export default TextField
