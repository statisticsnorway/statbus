import React, { useState, useEffect, useCallback } from 'react'
import { arrayOf, string, number, oneOfType, func, bool, shape } from 'prop-types'
import { Message, Label } from 'semantic-ui-react'
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
  options: initialOptions,
  url,
}) => {
  const label = labelKey ? localize(labelKey) : undefined
  const title = titleKey ? localize(titleKey) : label
  const placeholder = placeholderKey ? localize(placeholderKey) : label
  const hasOptions = hasValue(options)
  const [value, setValue] = useState(hasValue(initialValue) ? initialValue : multiselect ? [] : notSelected.value)
  const [options, setOptions] = useState([])
  const [isLoading, setIsLoading] = useState(false)
  const [page, setPage] = useState(0)
  const [wildcard, setWildcard] = useState('')

  const loadOptions = useCallback(
    debounce(() => {
      if (!isLoading) {
        internalRequest({
          url: `/api/lookup/paginated/${lookup}`,
          queryParams: { page, pageSize, wildcard },
          method: 'get',
          onSuccess: (data) => {
            let newOptions = [...data]

            if (responseToOption) {
              newOptions = newOptions.map(responseToOption)
            }
            setOptions(prevOptions => [...prevOptions, ...newOptions])
            setPage(page + 1)
          },
        })
      }
    }, waitTime),
    [isLoading, lookup, pageSize, wildcard, responseToOption, page, waitTime],
  )

  const handleAsyncSelect = (data) => {
    const raw = data !== null ? data : { value: notSelected.value }
    const selectedValue = multiselect ? raw.map(x => x.value) : raw.value
    setValue(selectedValue)
    onChange(undefined, { ...selectedValue })
  }

  const handlePlainSelect = (event, { value: selectedValue, ...data }) => {
    const nextData = { ...data, ...selectedValue }
    setValue(selectedValue)
    onChange(event, nextData)
  }

  const handleInputChange = (newValue) => {
    if (newValue && lookup !== null) {
      setIsLoading(true)

      internalRequest({
        url: `/api/lookup/paginated/${lookup}`,
        queryParams: { page: 0, pageSize, wildcard: newValue },
        method: 'get',
        onSuccess: (data) => {
          let newOptions = [...data]

          if (responseToOption) {
            newOptions = newOptions.map(responseToOption)
          }
          setOptions(newOptions)
          setPage(0)
          setIsLoading(false)
        },
      })
    }
  }

  useEffect(() => {
    if (hasValue(initialOptions)) return

    setIsLoading(true)

    internalRequest({
      url: `/api/lookup/${lookup}/GetById/`,
      queryParams: { ids: initialValue },
      method: 'get',
      onSuccess: (valueData) => {
        if (hasValue(valueData)) {
          setValue(multiselect ? valueData.map(responseToOption) : responseToOption(valueData[0]))
          setIsLoading(false)
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
        const newOptions =
          Array.isArray(result) && result.length > 0 ? result.map(responseToOption) : []
        setOptions(newOptions)
        setIsLoading(false)
        setPage(1)
      })
  }, [initialOptions, initialValue, multiselect, lookup, responseToOption, pageSize])

  useEffect(() => {
    const ids = R.is(Array, initialValue)
      ? R.is(Array, initialValue) && initialValue.map(x => x.id)
      : initialValue && initialValue.id
    if (isEdit && R.equals(ids, value)) {
      setValue(initialValue)
    }
    if (!R.equals(initialValue && value)) {
      setValue(initialValue)
    }
    if (initialValue === 0 || initialValue.length === 0 || initialValue[0] === 0) {
      setValue('')
    }
    if (locale !== locale) {
      setValue(multiselect ? value.map(responseToOption) : responseToOption(value))
      setOptions(options.map(responseToOption))
    }
  }, [locale, multiselect, responseToOption, isEdit, initialValue, value, options])

  const hasErrors = (touched && hasValue(errorKeys)) || (error && hasValue(errorKeys))

  const selectProps = hasValue(options)
    ? {
      onChange: handlePlainSelect,
      error: hasErrors,
      multiple: multiselect,
      options:
          multiselect || !required
            ? options
            : [
              {
                value: notSelected.value,
                text: localize(notSelected.text),
              },
              ...options,
            ],
      required,
      title,
      inline,
      width,
    }
    : {
      onChange: handleAsyncSelect,
      loadOptions,
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
      onMenuScrollToBottom: loadOptions,
      onInputChange: handleInputChange,
      required,
    }

  const className = `field${!hasOptions && required ? ' required' : ''}`

  return (
    <div
      className={className}
      style={{ opacity: `${disabled ? 0.25 : 1}` }}
      data-tooltip={popuplocalizedKey ? localize(popuplocalizedKey) : null}
      data-position="top left"
    >
      {label !== undefined && <label htmlFor={name}>{label}</label>}
      <ReactSelect
        {...selectProps}
        value={value}
        options={initialOptions || options}
        onBlur={onBlur}
        name={name}
        placeholder={placeholder}
        isDisabled={disabled}
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
