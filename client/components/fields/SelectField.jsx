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
import regeneratorRuntime from 'regenerator-runtime'

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

// eslint-disable-next-line react/prop-types
const createRemovableValueComponent = localize => ({ value, onRemove }) => (
  <Label
    content={value.value === notSelected.value ? localize(value.label) : value.label}
    onRemove={() => onRemove(value)}
    removeIcon="delete"
    color="blue"
    basic
  />
)

// eslint-disable-next-line react/prop-types
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
  value: initialValueProp,
  onChange,
  onBlur = R.identity,
  error = false,
  errors = [],
  label: labelKey,
  title: titleKey,
  placeholder: placeholderKey,
  multiselect = false,
  required = false,
  touched = false,
  disabled = false,
  inline = false,
  width,
  createOptionComponent,
  localize,
  popuplocalizedKey,
  pageSize = 10,
  waitTime = 250,
  lookup,
  responseToOption,
  isEdit = false,
  locale = '',
  options: optionsProp,
  url,
}) => {
  const [value, setValue] = useState(hasValue(initialValueProp) ? initialValueProp : multiselect ? [] : notSelected.value)
  const [options, setOptions] = useState([])
  const [isLoading, setIsLoading] = useState(false)
  const [page, setPage] = useState(0)
  const [wildcard, setWildcard] = useState('')

  useEffect(() => {
    if (hasValue(optionsProp)) return

    const fetchData = async () => {
      try {
        setIsLoading(true)

        const response = await internalRequest({
          url: `/api/lookup/${lookup}/GetById/`,
          queryParams: { ids: initialValueProp },
          method: 'get',
        })

        if (hasValue(response)) {
          setValue(multiselect ? response.map(responseToOption) : responseToOption(response[0]))
        }

        const fetchOptionsResponse = await fetch(
          `/api/lookup/paginated/${lookup}?page=0&pageSize=${pageSize}`,
          {
            method: 'GET',
            headers: { 'Content-Type': 'application/json' },
            credentials: 'same-origin',
          },
        )

        const result = await fetchOptionsResponse.json()
        const fetchedOptions =
          Array.isArray(result) && result.length > 0 ? result.map(responseToOption) : []

        setOptions(fetchedOptions)
        setIsLoading(false)
        setPage(1)
      } catch (error) {
        console.error('Error fetching data:', error)
        setIsLoading(false)
      }
    }

    fetchData()
  }, [lookup, multiselect, pageSize, optionsProp, initialValueProp, responseToOption])

  useEffect(() => {
    const isEditDataSource = url.includes('datasources' && 'edit')

    if (isEdit || isEditDataSource) {
      if (R.equals(initialValueProp, value)) {
        setValue(initialValueProp)
      } else {
        setValue(initialValueProp)
      }
    }
  }, [isEdit, initialValueProp, value, url])

  useEffect(() => {
    if (locale !== locale) {
      const currValue = hasValue(value) ? value : []
      const isArrayOfStrings =
        Array.isArray(currValue) && currValue.every(x => typeof x === 'string')

      setValue(multiselect
        ? isArrayOfStrings
          ? currValue
          : currValue.map(responseToOption)
        : typeof currValue === 'string'
          ? currValue
          : responseToOption(currValue))

      setOptions(options.map(responseToOption))
      return
    }

    if (
      R.isEmpty(initialValueProp) ||
      (Array.isArray(initialValueProp) && initialValueProp.every(x => x === '')) ||
      (R.is(Array, initialValueProp) && R.isEmpty(initialValueProp))
    ) {
      setValue('')
    }

    if (!R.equals(initialValueProp && value)) {
      setValue(initialValueProp)
    }

    if (
      R.isNil(initialValueProp) ||
      (R.is(Array, initialValueProp) && R.isEmpty(initialValueProp))
    ) {
      setValue('')
      onChange(undefined, { ...{}, value: '' })
    }
  }, [locale, multiselect, initialValueProp, value, options, responseToOption, onChange])

  useEffect(() => {
    const fetchData = async () => {
      if (!isLoading) {
        try {
          setIsLoading(true)

          const response = await internalRequest({
            url: `/api/lookup/paginated/${lookup}`,
            queryParams: { page, pageSize, wildcard },
            method: 'get',
          })

          let fetchedOptions = [...response]

          if (responseToOption) {
            fetchedOptions = fetchedOptions.map(responseToOption)
          }

          setOptions(prevOptions => prevOptions.concat(fetchedOptions))
          setPage(page + 1)
        } catch (error) {
          console.error('Error fetching options:', error)
        } finally {
          setIsLoading(false)
        }
      }
    }

    const handleLoadOptions = debounce(fetchData, waitTime)
    handleLoadOptions()

    return () => {
      handleLoadOptions.cancel()
    }
  }, [lookup, pageSize, multiselect, required, responseToOption, wildcard, page, isLoading])

  const handleAsyncSelect = (data) => {
    const raw = data !== null ? data : { value: notSelected.value }
    const nextValue = multiselect ? R.uniq(raw.map(x => x.value)) : raw.value

    if (!R.equals(value, nextValue)) {
      setValue(multiselect ? raw.map(responseToOption) : responseToOption(raw))

      onChange(undefined, { ...{}, value: nextValue }, data)
    }
  }

  const handlePlainSelect = (event, { value: selectedValue, ...data }) => {
    const nextData = { ...data, ...{}, value: selectedValue }

    if (!R.equals(value, selectedValue)) {
      setValue(selectedValue)
      onChange(event, nextData)
    }
  }

  const handleInputChange = useCallback(
    (newValue) => {
      const fetchData = async () => {
        if (newValue && lookup !== null) {
          setIsLoading(true)

          try {
            const response = await internalRequest({
              url: `/api/lookup/paginated/${lookup}`,
              queryParams: { page: 0, pageSize, wildcard: newValue },
              method: 'get',
            })

            let fetchedOptions = [...response]

            if (responseToOption) {
              fetchedOptions = fetchedOptions.map(responseToOption)
            }

            setOptions(fetchedOptions)
            setPage(0)
          } catch (error) {
            console.error('Error fetching options:', error)
          } finally {
            setIsLoading(false)
          }
        }
      }

      const handleInputChangeDebounced = debounce(fetchData, waitTime)
      handleInputChangeDebounced()
    },
    [lookup, pageSize, responseToOption, waitTime],
  )

  const hasErrors = (touched && hasValue(errors)) || (error && hasValue(errors))
  const label = labelKey !== (undefined || null) ? localize(labelKey) : undefined
  const title = titleKey ? localize(titleKey) : label
  const placeholder = placeholderKey ? localize(placeholderKey) : labelKey !== null ? label : null
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
      },
    ]
    : [
      ReactSelect,
      {
        onChange: handleAsyncSelect,
        loadOptions: handleInputChangeDebounced,
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
        onMenuScrollToBottom: handleInputChangeDebounced,
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
        options={optionsProp || options}
        onBlur={onBlur}
        name={name}
        placeholder={placeholder}
        disabled={disabled}
        autoComplete="off"
      />
      {hasErrors && (
        <Message title={label} list={errors.map(localize)} compact={hasOptions} error />
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
