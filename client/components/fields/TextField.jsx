import React from 'react'
import { arrayOf, bool, func, number, oneOfType, string } from 'prop-types'
import { Message, Form } from 'semantic-ui-react'

export const TextField = ({
  value,
  label: labelKey,
  title: titleKey,
  placeholder: placeholderKey,
  touched,
  error,
  errors: errorKeys,
  localize,
  highlighted,
  popuplocalizedKey,
  ...restProps
}) => {
  const label = labelKey !== undefined ? localize(labelKey) : undefined
  const title = titleKey ? localize(titleKey) : label
  const hasErrors =
    (touched !== false && errorKeys.length !== 0) || (error === true && errorKeys.length !== 0)

  const cssClass = `field ${highlighted && touched ? 'valid-highlight' : null}`

  const inputProps = {
    ...restProps,
    value: value !== null ? value : '',
    error: error || hasErrors,
    label,
    title,
    placeholder: placeholderKey ? localize(placeholderKey) : label,
    autoComplete: 'off',
  }

  return (
    <div
      className={cssClass}
      data-tooltip={popuplocalizedKey ? localize(popuplocalizedKey) : null}
      data-position="top left"
    >
      {restProps.name === 'name' ? (
        <Form.TextArea {...inputProps} />
      ) : (
        <Form.Input {...inputProps} />
      )}

      {hasErrors && <Message title={label} list={errorKeys.map(localize)} compact error />}
    </div>
  )
}

TextField.propTypes = {
  label: string,
  title: string,
  placeholder: string,
  value: oneOfType([number, string]),
  touched: bool,
  error: bool,
  errors: arrayOf(string),
  localize: func.isRequired,
  highlighted: bool,
  popuplocalizedKey: string,
}

TextField.defaultProps = {
  value: '',
  label: undefined,
  title: undefined,
  placeholder: undefined,
  touched: undefined,
  error: false,
  errors: [],
  highlighted: false,
  popuplocalizedKey: undefined,
}
