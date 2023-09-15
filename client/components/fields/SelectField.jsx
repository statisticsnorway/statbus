import React, { useState, useEffect, useCallback } from 'react'
import { arrayOf, string, number, oneOfType, func, bool, shape } from 'prop-types'
import { Message, Select as SemanticUiSelect, Label } from 'semantic-ui-react'
import ReactSelect from 'react-select'
import debounce from 'lodash/debounce'
import R from 'ramda'

import { hasValue, createPropType } from 'helpers/validation'
import { internalRequest } from 'helpers/request'
import { getNewName } from 'helpers/locale'

import styles from './styles.pcss'
import './SelectField.css'

const notSelected = { value: undefined, text: 'NotSelected' }

const NameCodeOption = {
  transform: x => ({
    ...x,
    key: x.id,
    value: x.id,
    label: getNewName(x),
    text: getNewName(x),
  }),
  render: params => (
    <div className="content">
      <div className="title">
        {params.code && <div className={styles['select-field-code']}>{params.code}</div>}
        {params.code && <br />}
        {getNewName(params, false)}
        <hr />
      </div>
    </div>
  ),
}

const createRemovableValueComponent = localize => ({ value, onRemove }) => (
  <Label
    content={value.value === notSelected.value ? localize(value.label) : value.label}
    onRemove={() => onRemove(value)}
    removeIcon="delete"
    color="blue"
    basic
  />
)

const createValueComponent = localize => ({ value: { value, label } }) => (
  <div className="Select-value">
    <span className="Select-value-label" role="option" aria-selected="true">
      {value === notSelected.value ? localize(notSelected.text) : label}
    </span>
  </div>
)

const numOrStr = oneOfType([number, string])

const SelectField = ({
  name,
  value: initialValue,
  onChange,
  onBlur,
  error,
  errors: errorKeys,
  label: labelKey,
  title: titleKey,
  placeholder: placeholderKey,
  multiselect,
  required,
  touched,
  disabled,
  inline,
  width,
  createOptionComponent,
  localize,
  popuplocalizedKey,
  pageSize,
  waitTime,
  lookup,
  responseToOption,
  isEdit,
  locale,
  options: propOptions,
  url,
}) => {
  const [initialValueState, setInitialValueState] = useState(initialValue)
  const [value, setValue] = useState(hasValue(initialValue) ? initialValue : multiselect ? [] : notSelected.value)
  const [options, setOptions] = useState([])
  const [isLoading, setIsLoading] = useState(false)
  const [page, setPage] = useState(0)
  const [wildcard, setWildcard] = useState('')

  const loadOptions = useCallback(() => {
    if (isLoading) return

    internalRequest({
      url: `/api/lookup/paginated/${lookup}`,
      queryParams: { page, pageSize, wildcard },
      method: 'get',
      onSuccess: (data) => {
        let updatedOptions = [...data]

        if (responseToOption) updatedOptions = updatedOptions.map(responseToOption)
        setOptions(prevOptions => [...prevOptions, ...updatedOptions])
        setPage(prevPage => prevPage + 1)
      },
    })
  }, [isLoading, lookup, page, pageSize, wildcard, responseToOption])

  const handleLoadOptions = debounce(loadOptions, waitTime)

  const handleAsyncSelect = (data) => {
    const raw = data !== null ? data : { value: notSelected.value }
    const newValue = multiselect ? R.uniq(raw.map(x => x.value)) : raw.value

    if (!R.equals(value, newValue)) {
      setValue(multiselect ? raw.map(responseToOption) : responseToOption(raw), () => {
        onChange(undefined, { ...props, value: newValue }, data)
      })
    }
  }

  const handlePlainSelect = (event, { value, ...data }) => {
    const nextData = { ...data, ...props, value }
    if (!R.equals(value, value)) {
      setValue(value, () => onChange(event, nextData))
    }
  }

  const handleInputChange = (newValue) => {
    if (newValue && lookup !== null) {
      setIsLoading(true)

      internalRequest({
        url: `/api/lookup/paginated/${lookup}`,
        queryParams: { page: 0, pageSize, wildcard: newValue },
        method: 'get',
        onSuccess: (data) => {
          let updatedOptions = [...data]

          if (responseToOption) updatedOptions = updatedOptions.map(responseToOption)
          setOptions(updatedOptions)
          setPage(0)
          setIsLoading(false)
        },
      })
    }
  }

  useEffect(() => {
    const { value: ids, lookup, multiselect, responseToOption } = props
    setIsLoading(true)
    internalRequest({
      url: `/api/lookup/${lookup}/GetById/`,
      queryParams: { ids },
      method: 'get',
      onSuccess: (data) => {
        if (hasValue(data)) {
          setValue(multiselect ? data.map(responseToOption) : responseToOption(data[0]))
        }
      },
    })
    fetch(`/api/lookup/paginated/${lookup}?page=0&pageSize=10`, {
      method: 'GET',
      headers: { 'Content-Type': 'application/json' },
      credentials: 'same-origin',
    })
      .then(resp => resp.json())
      .then((result) => {
        const updatedOptions =
          Array.isArray(result) && result.length > 0 ? result.map(responseToOption) : []
        setOptions(updatedOptions)
        setIsLoading(false)
        setPage(prevPage => prevPage + 1)
      })
  }, [lookup, props])

  useEffect(() => {
    if (props.locale !== locale) {
      const currValue = hasValue(value) ? value : []
      const isArrayOfStrings =
        Array.isArray(currValue) && currValue.every(x => typeof x === 'string')
      setValue(
        multiselect
          ? isArrayOfStrings
            ? currValue
            : currValue.map(responseToOption)
          : typeof currValue === 'string'
            ? currValue
            : responseToOption(currValue),
        () => {
          setOptions(prevOptions => prevOptions.map(responseToOption))
        },
      )
      return
    }
    if (
      R.isEmpty(props.value) ||
      (Array.isArray(props.value) && props.value.every(x => x === '')) ||
      (R.is(Array, props.value) && R.isEmpty(props.value))
    ) {
      setValue('')
    }
    if (!R.equals(props.value && value)) {
      setValue(props.value)
    }
    if (R.isNil(props.value) || (R.is(Array, props.value) && R.isEmpty(props.value))) {
      setValue('', () => onChange(undefined, { ...props, value: '' }))
    }
  }, [props, value, locale, multiselect, responseToOption])

  useEffect(() => {
    setInitialValueState(initialValue)
  }, [initialValue])

  useEffect(() => {
    handleLoadOptions.cancel()
  }, [])

  const hasErrors = (touched && hasValue(errorKeys)) || (error && hasValue(errorKeys))
  const label = labelKey !== (undefined || null) ? localize(labelKey) : undefined
  const title = titleKey ? localize(titleKey) : label
  const placeholder = placeholderKey
    ? localize(placeholderKey)
    : placeholderKey !== null
      ? label
      : null
  const hasOptions = hasValue(options)
  const [Select, ownProps] = hasOptions
    ? [
      SemanticUiSelect,
      {
        onChange: handlePlainSelect,
        error: hasErrors,
        multiple: multiselect,
        options:
            multiselect || !required
              ? options
              : [{ value: notSelected.value, text: localize(notSelected.text) }, ...options],
        required,
        title,
        inline,
        width,
      },
    ]
    : [
      ReactSelect,
      {
        onChange: handleAsyncSelect,
        loadOptions: handleLoadOptions,
        getOptionLabel: option => option.text,
        getOptionValue: option => option.value,
        valueComponent: multiselect
          ? createRemovableValueComponent(localize)
          : createValueComponent(localize),
        optionRenderer: createOptionComponent,
        inputProps: { type: 'react-select', name },
        className: hasErrors ? 'react-select--error' : '',
        multi: multiselect,
        removeSelected: multiselect,
        backspaceRemoves: true,
        searchable: true,
        pagination: true,
        isLoading,
        onMenuScrollToBottom: handleLoadOptions,
        onInputChange: handleInputChange,
        required,
      },
    ]
  const className = `field${!hasOptions && required ? ' required' : ''}`

  return (
    <div
      className={className}
      style={{ opacity: `${disabled ? 0.25 : 1}` }}
      data-tooltip={popuplocalizedKey ? localize(popuplocalizedKey) : null}
      data-position="top left"
    >
      {label !== undefined && <label htmlFor={name}>{label}</label>}
      <Select
        {...ownProps}
        value={value}
        options={props.options ? props.options : options}
        onBlur={onBlur}
        name={name}
        placeholder={placeholder}
        disabled={disabled}
        autoComplete="off"
      />
      {hasErrors && (
        <Message title={label} list={errorKeys.map(localize)} compact={hasOptions} error />
      )}
    </div>
  )
}

SelectField.propTypes = {
  name: string.isRequired,
  value: createPropType(props => (props.multiselect ? arrayOf(numOrStr) : numOrStr)),
  onChange: func.isRequired,
  onBlur: func,
  error: bool,
  errors: arrayOf(string),
  label: string,
  title: string,
  placeholder: string,
  multiselect: bool,
  required: bool,
  touched: bool,
  disabled: bool,
  inline: bool,
  width: numOrStr,
  createOptionComponent: func,
  localize: func.isRequired,
  popuplocalizedKey: string,
  pageSize: number,
  waitTime: number,
  lookup: number,
  responseToOption: func,
  isEdit: bool,
  locale: string,
  options: arrayOf(shape({
    value: numOrStr.isRequired,
    text: numOrStr.isRequired,
  })),
  url: string,
}

SelectField.defaultProps = {
  value: null,
  onBlur: R.identity,
  label: null,
  title: null,
  placeholder: null,
  multiselect: false,
  required: false,
  error: false,
  errors: [],
  disabled: false,
  inline: false,
  width: null,
  createOptionComponent: NameCodeOption.render,
  pageSize: 10,
  waitTime: 250,
  lookup: null,
  responseToOption: NameCodeOption.transform,
  options: null,
  isEdit: false,
  locale: '',
  url: '',
  touched: false,
  popuplocalizedKey: null,
}

export default SelectField
